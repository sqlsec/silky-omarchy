// silky-dock-glass — Liquid Glass for the MacShell Dock, drawn by Hyprland itself in the
// same frame as everything under it: no window captures, no polling, no lag.
//
// How it works (Hyprland 0.57, aarch64-safe: no function hooks, only the public render-stage event):
//   1. At RENDER_POST_WINDOWS (windows queued, Top / Overlay layers not yet) one pass element per monitor is queued
//      when a MacShell layer (macdock, macbar, macspot, ...) carries glass.
//   2. When it draws, the framebuffer holds exactly what is under those layers in THIS frame. The area under the glass
//      (+ refraction reach) is copied at half resolution into a mipmapped texture per layer.
//   3. A shader paints the glass (rounded-rect bevel, Snell refraction, dispersion, blur from mip levels, adaptive tint,
//      edge light — ported from MacShell's dockglass.frag), one instance per glass rectangle. Hyprland then draws the
//      layers (icons, menu text) on top as usual.
//   4. Where the glass is changes every frame (magnifying Dock, popovers scaling / fading in). Each MacShell window
//      writes its glass rectangles into a hidden marker on the bottom row of its own surface (SilkyGlassMarker.qml:
//      alpha 1..4 / 255 per pixel = one base-4 digit, invisible). The vertex shader decodes it from the very buffer
//      Hyprland is about to draw, so shape and refraction are always in step.
//   5. The CPU only needs to know roughly where the glass is (what to copy, what to add to the damage): the marker row
//      is also read back asynchronously (PBO + fence), one frame late, with a safety margin.
//
// Any frame whose damage touches a glass area adds that whole area (+ refraction reach) to the damage, so the copied
// backdrop never mixes in last frame's layer pixels. See docs/02-macshell.md.

#include <hyprland/src/plugins/PluginAPI.hpp>
#include <hyprland/src/Compositor.hpp>
#include <hyprland/src/desktop/view/LayerSurface.hpp>
#include <hyprland/src/event/EventBus.hpp>
#include <hyprland/src/output/Monitor.hpp>
#include <hyprland/src/protocols/core/Compositor.hpp>
#include <hyprland/src/protocols/types/Buffer.hpp>
#include <hyprland/src/render/Renderer.hpp>
#include <hyprland/src/render/Context.hpp>
#include <hyprland/src/render/pass/PassElement.hpp>
#include <hyprland/src/state/MonitorState.hpp>

#include <GLES3/gl32.h>
#include <GLES2/gl2ext.h>

#include <array>
#include <cstdlib>
#include <format>
#include <fstream>
#include <string>
#include <sys/stat.h>
#include <unordered_map>
#include <vector>

inline HANDLE PHANDLE = nullptr;

namespace {
    std::vector<CHyprSignalListener> g_listeners;

    constexpr int    MAX_RECTS   = 24;
    constexpr int    HEADER      = 8;  // magic (4) + count (4)
    constexpr int    PER_RECT    = 46; // x y w h r (8 each) + alpha (4) + dark (1) + kind (1)
    constexpr int    MAX_DIGITS  = HEADER + MAX_RECTS * PER_RECT;
    constexpr double REACH       = 96; // logical px the glass reads around itself (refraction + blur)
    constexpr double CPU_MARGIN  = 48; // the CPU copy of the rects is a frame old: margin for moving / growing glass

    // Layers whose glass rectangles are painted by this plugin (macbarbg — the thin top bar strip — stays on plain blur).
    const char* NAMESPACES[] = {"macdock", "macbar", "macspot", "macosd", "macswitch", "macwall"};

    struct SStats {
        uint64_t frames = 0, damaged = 0;
    } g_stats;

    // ── parameters (per kind: 0 = Dock, 1 = menus / panels, 2 = Control Center bubbles), live-tunable ──────────────
    struct SKind {
        float blur, tint, bezel, thickness, dispersion, magnify, saturation, lift, rim, tintDark;
    };
    struct SParams {
        // Tuned toward macOS 26/27 Liquid Glass (physical Convex Squircle Snell refraction):
        //   0 = Dock: clean optical glass, crisp narrow bezel that reflects interior icons/dots at the rim
        //   1 = Menus / Notification Center / Spotlight: slightly more frosted so dense text stays crisp
        //   2 = Control Center floating tiles: clear jewel-like liquid bubbles with lively Snell rim refraction
        SKind k[3] = {
            {6.5f, 0.10f, 14.f, 22.f, 0.08f, 0.00f, 1.12f, 0.012f, 0.72f, 0.22f},
            {11.f, 0.16f, 12.f, 18.f, 0.06f, 0.00f, 1.12f, 0.015f, 0.72f, 0.26f},
            {5.5f, 0.09f, 14.f, 24.f, 0.09f, 0.00f, 1.22f, 0.018f, 0.88f, 0.18f},
        };
    };
    // ~/.config/silky-omarchy/dock-glass.conf: "key = value"; plain = Dock, "menu_" = menus/panels, "cc_" = Control Center bubbles
    const SParams& params() {
        static SParams  p;
        static int64_t  lastMtime = -1;
        static uint64_t lastCheck = 0;
        if (g_stats.frames - lastCheck < 30 && lastMtime != -1)
            return p;
        lastCheck = g_stats.frames;
        const char* home = std::getenv("HOME");
        if (!home)
            return p;
        const std::string path = std::string(home) + "/.config/silky-omarchy/dock-glass.conf";
        struct stat       st{};
        const int64_t     m = ::stat(path.c_str(), &st) == 0 ? (int64_t)st.st_mtime : 0;
        if (m == lastMtime)
            return p;
        lastMtime = m;
        p         = SParams{};
        std::ifstream f(path);
        std::string   line;
        auto          trim = [](std::string v) {
            v.erase(0, v.find_first_not_of(" \t"));
            v.erase(v.find_last_not_of(" \t") + 1);
            return v;
        };
        while (std::getline(f, line)) {
            if (const auto hash = line.find('#'); hash != std::string::npos)
                line.resize(hash);
            const auto eq = line.find('=');
            if (eq == std::string::npos)
                continue;
            std::string k    = trim(line.substr(0, eq));
            int         kind = 0;
            if (k.starts_with("menu_")) {
                kind = 1;
                k    = k.substr(5);
            } else if (k.starts_with("cc_")) {
                kind = 2;
                k    = k.substr(3);
            }
            float v = 0;
            try {
                v = std::stof(trim(line.substr(eq + 1)));
            } catch (...) { continue; }
            auto& K = p.k[kind];
            if (k == "blur") K.blur = v;
            else if (k == "tint") K.tint = v;
            else if (k == "tint_dark") K.tintDark = v;
            else if (k == "bezel") K.bezel = v;
            else if (k == "thickness") K.thickness = v;
            else if (k == "dispersion") K.dispersion = v;
            else if (k == "magnify") K.magnify = v;
            else if (k == "saturation") K.saturation = v;
            else if (k == "lift") K.lift = v;
            else if (k == "rim") K.rim = v;
        }
        return p;
    }

    // ── shaders ───────────────────────────────────────────────────────────────────────────────────────────────────
    const char* VERT = R"GLSL(
precision highp float;
precision highp int;
layout(location = 0) in vec2 aPos;          // unit quad 0..1, one instance per glass rectangle

uniform SURF_SAMPLER uSurf;                 // the layer's current buffer
uniform vec2  uSurfPx;                      // buffer size, px
uniform float uBufScale;                    // buffer px per logical px of the surface
uniform vec2  uLayerFb;                     // layer top-left in framebuffer px (Hyprland framebuffers are top-left origin)
uniform float uMonScale;                    // framebuffer px per logical px
uniform vec2  uFb;                          // framebuffer size, px
uniform float uLayerHLogical;               // layer height, logical px

flat out vec4  vRect;                       // glass rect in framebuffer px: x, y (top), w, h
flat out float vRadius;
flat out float vDark;
flat out float vAlpha;
flat out int   vKind;
out vec2 vFb;

int digitAt(int i) {
    vec2 p = (vec2(float(i), uLayerHLogical - 1.0) + 0.5) * uBufScale;
    float a = SURF_FETCH(uSurf, p, uSurfPx).a;
    return int(floor(a * 255.0 + 0.5)) - 1;   // 1..4 -> 0..3, 0 (no marker) -> -1
}
int number(int start, int n) {
    int v = 0;
    for (int k = 0; k < n; ++k) {
        int d = digitAt(start + k);
        if (d < 0 || d > 3) return -1;
        v = v * 4 + d;
    }
    return v;
}

void main() {
    bool ok = digitAt(0) == 2 && digitAt(1) == 3 && digitAt(2) == 1 && digitAt(3) == 1;
    int count = ok ? number(4, 4) : -1;
    int i = gl_InstanceID;
    ok = ok && count > i;
    int b = 8 + i * 46;
    int fx = ok ? number(b, 8) : -1, fy = ok ? number(b + 8, 8) : -1, fw = ok ? number(b + 16, 8) : -1;
    int fh = ok ? number(b + 24, 8) : -1, fr = ok ? number(b + 32, 8) : -1, fa = ok ? number(b + 40, 4) : -1;
    int fd = ok ? digitAt(b + 44) : -1, fk = ok ? digitAt(b + 45) : -1;
    ok = ok && fx >= 0 && fy >= 0 && fw > 0 && fh > 0 && fr >= 0 && fa > 0 && fd >= 0 && fk >= 0;
    vec2 xy = vec2(float(fx), float(fy)) * 0.5;
    vec2 wh = vec2(float(fw), float(fh)) * 0.5;
    vec4 r  = vec4(uLayerFb + xy * uMonScale, wh * uMonScale);
    vRect   = r;
    vRadius = float(fr) * 0.5 * uMonScale;
    vDark   = float(fd);
    vAlpha  = float(fa) / 255.0;
    vKind   = clamp(fk, 0, 2);
    vec2 p  = r.xy - 2.0 + aPos * (r.zw + 4.0);
    vFb     = p;
    gl_Position = ok ? vec4(p / uFb * 2.0 - 1.0, 0.0, 1.0) : vec4(-2.0, -2.0, 0.0, 1.0);
}
)GLSL";

    const char* FRAG = R"GLSL(
precision highp float;
precision highp int;
flat in vec4  vRect;
flat in float vRadius;
flat in float vDark;
flat in float vAlpha;
flat in int   vKind;
in vec2 vFb;
layout(location = 0) out vec4 fragColor;

uniform sampler2D uBack;                    // half-resolution copy of the framebuffer under the layer (mipmapped)
uniform vec4  uBand;                        // area the copy covers, framebuffer px: x, y (top), w, h
uniform vec4  uValid;                       // part refreshed this frame (x0, y0, x1, y1): glass outside it waits a frame
uniform float uS;                           // framebuffer px per logical px
uniform float uTexScale;                    // backdrop texels per framebuffer px
// per kind (0 = Dock, 1 = menus / panels, 2 = Control Center bubbles)
uniform float uTint[3];                     // light mode
uniform float uTintDark[3];                 // dark mode: a little deeper, like macOS dark glass
uniform float uBlur[3];
uniform float uBezel[3];
uniform float uThick[3];
uniform float uDisperse[3];
uniform float uMagnify[3];
uniform float uSat[3];
uniform float uLift[3];
uniform float uRim[3];

const int   TAPS   = 20;
const float GOLDEN = 2.39996323;

vec3 back(vec2 p, float lod) {
    vec2 uv = (p - uBand.xy) / uBand.zw;
    return textureLod(uBack, clamp(uv, vec2(0.001), vec2(0.999)), lod).rgb;
}
float ign(vec2 p) { return fract(52.9829189 * fract(dot(p, vec2(0.06711056, 0.00583715)))); }
float hash12(vec2 p) { vec3 p3 = fract(vec3(p.xyx) * 0.1031); p3 += dot(p3, p3.yzx + 33.33); return fract((p3.x + p3.y) * p3.z); }

vec3 blurredDisp(vec2 p, vec2 disp, float disperse, float rad) {
    float R   = max(rad, 0.5);
    float gap = R * sqrt(3.14159265 / float(TAPS));
    float lod = clamp(log2(max(gap * uTexScale, 1.0)) + 0.35, 0.0, 6.0);
    float rot = ign(gl_FragCoord.xy) * 6.2831853;
    bool dispersed = length(disp) * disperse > 0.25;   // subtle chromatic fringes along high-contrast edges
    vec3 acc = vec3(0.0); float ws = 0.0;
    for (int i = 0; i < TAPS; ++i) {
        float fi = float(i) + 0.5, r = sqrt(fi / float(TAPS)), a = fi * GOLDEN + rot, w = exp(-2.2 * r * r);
        vec2 o = vec2(cos(a), sin(a)) * r * R;
        vec3 c;
        if (dispersed) {
            c.r = back(p + o + disp * (1.0 + disperse), lod).r;
            c.g = back(p + o + disp, lod).g;
            c.b = back(p + o + disp * (1.0 - disperse), lod).b;
        } else
            c = back(p + o + disp, lod);
        acc += c * w; ws += w;
    }
    return acc / ws;
}
float roundBox(vec2 q, vec2 hs, float r) { vec2 d = abs(q) - (hs - r); return length(max(d, 0.0)) + min(max(d.x, d.y), 0.0) - r; }

void main() {
    int K = vKind;
    vec2 hsPx = vRect.zw * 0.5;
    vec2 q    = (vFb - (vRect.xy + hsPx)) / uS;                // y down, logical
    vec2 hs   = hsPx / uS;
    float r   = min(vRadius / uS, min(hs.x, hs.y));
    float sd  = roundBox(q, hs, r);
    float cov = clamp(0.5 - sd * uS, 0.0, 1.0);
    if (cov <= 0.0) discard;
    if (vFb.x < uValid.x || vFb.y < uValid.y || vFb.x > uValid.z || vFb.y > uValid.w) discard;
#ifdef DEBUG_RAW
    fragColor = vec4(back(vFb, 0.0), 1.0) * cov; return;
#endif

    float t  = max(-sd, 0.0);
    vec2 d2  = abs(q) - (hs - r);
    vec2 sg  = vec2(q.x >= 0.0 ? 1.0 : -1.0, q.y >= 0.0 ? 1.0 : -1.0);
    vec2 m   = max(d2, 0.0);
    vec2 g   = (length(m) > 1e-4) ? normalize(m) * sg : ((d2.x > d2.y) ? vec2(sg.x, 0.0) : vec2(0.0, sg.y));

    // Physical Convex Squircle bezel + Snell's Law refraction (macOS 26/27 Liquid Glass):
    // Surface height h(u) = (1 - (1 - u)^4)^(1/4) for u = t / bz in [0, 1].
    //   - For t >= bz (flat interior): slope = 0, displacement = 0, so lines crossing the glass stay
    //     pixel-aligned with the background outside.
    //   - For t < bz (convex bezel): the surface normal tilts outward (+g), so Snell's Law bends the
    //     view ray INWARD (-g) into the glass interior. Nearby interior features (like a red traffic-light
    //     button under the Dock) naturally refract/reflect onto the curved glass rim instead of pulling
    //     outside wallpaper inward.
    float bz    = clamp(uBezel[K], 1.0, min(hs.x, hs.y) * 0.65);
    float u     = clamp(t / bz, 0.0, 1.0);
    float om    = 1.0 - u;
    float om3   = om * om * om;
    float om4   = om3 * om;
    float h     = pow(max(1.0 - om4, 1e-4), 0.25);
    // Exact analytical derivative dh/du = om^3 / h^3, softly capped at the very lip for stability
    float slope = om3 / max(h * h * h, 0.10);
    // 3D outward surface normal (z pointing toward viewer); Snell refraction of view ray I = (0, 0, -1)
    vec3  N     = normalize(vec3(g * slope, 1.0));
    float eta   = 1.0 / 1.50;                                         // air (1.0) -> optical glass (1.50)
    vec3  R     = refract(vec3(0.0, 0.0, -1.0), N, eta);
    // R.xy points along -g (inward); scale by glass thickness and local height
    vec2  rayOff = (R.xy / max(abs(R.z), 0.25)) * (abs(uThick[K]) * (0.45 + 0.55 * h));
    vec2  disp   = (uThick[K] >= 0.0 ? rayOff : -rayOff);             // logical px, inward along -g

    // Keep the refracting bevel slightly crisper than the interior so rim reflections stay well-defined.
    float blurR = uBlur[K] * mix(0.55, 1.0, smoothstep(0.0, 0.80, u));
    vec2  lens  = q * -uMagnify[K];
    vec3  col   = blurredDisp(vFb, (disp + lens) * uS, uDisperse[K], blurR * uS);

    float l = dot(col, vec3(0.2126, 0.7152, 0.0722));
    col = mix(vec3(l), col, uSat[K]);
    float lw    = smoothstep(0.28, 0.78, l);
    float adapt = mix(0.78, 1.32, mix(1.0 - lw, lw, vDark));
    vec3  tintC = mix(vec3(1.0), vec3(0.08, 0.09, 0.10), vDark);
    col = mix(col, tintC, clamp(mix(uTint[K], uTintDark[K], vDark) * adapt, 0.0, 0.85));
    col += uLift[K] * mix(1.0, 0.35, vDark);
    float ty = clamp((q.y + hs.y) / (hs.y * 2.0), 0.0, 1.0);
    col += (1.0 - ty) * uLift[K] * mix(0.65, 0.45, vDark);

    // Refined macOS 26/27 hairline specular rim: ultra-crisp 1-px glass silhouette edge with
    // subtle top-left / bottom-right directional glints and no heavy white halo.
    vec2  lightDir = normalize(vec2(-0.50, -0.86));
    float dKey     = max(0.0, dot(g, lightDir));
    float dOpp     = max(0.0, dot(g, -lightDir));
    float topBias  = smoothstep(-0.35, 0.75, -g.y);
    float specArc  = pow(dKey, 2.4) * 0.42 + pow(dOpp, 2.8) * 0.24 + pow(abs(g.y), 1.6) * 0.12;
    float baseRing = 0.16 + 0.10 * topBias;
    float rimLine  = exp(-pow((t - 0.50) / 0.34, 2.0));
    float rimGlow  = exp(-t / mix(2.6, 3.8, topBias));
    float rimAmt   = (rimLine * (baseRing + specArc) + rimGlow * (0.025 + specArc * 0.10)) * uRim[K];
    col = col * (1.0 + rimAmt * 0.40) + vec3(rimAmt * mix(0.55, 0.38, vDark));

    float gn = hash12(gl_FragCoord.xy) + hash12(gl_FragCoord.xy * 1.7 + 17.0) - 1.0;
    col += gn * 0.004;
    col = clamp(col, 0.0, 1.0);
    float a = cov * vAlpha;
    fragColor = vec4(col * a, a);
}
)GLSL";

    GLuint compile(GLenum type, const std::string& src) {
        GLuint      s = glCreateShader(type);
        const char* p = src.c_str();
        glShaderSource(s, 1, &p, nullptr);
        glCompileShader(s);
        GLint ok = 0;
        glGetShaderiv(s, GL_COMPILE_STATUS, &ok);
        if (!ok) {
            char log[4096] = {0};
            glGetShaderInfoLog(s, sizeof(log), nullptr, log);
            Log::logger->log(Log::ERR, std::string("[silky-dock-glass] shader compile failed: ") + log);
            glDeleteShader(s);
            return 0;
        }
        return s;
    }

    GLuint link(bool external) {
        std::string head = "#version 320 es\n";
        if (external)
            head += "#extension GL_OES_EGL_image_external_essl3 : require\n"
                    "#define SURF_SAMPLER samplerExternalOES\n"
                    "#define SURF_FETCH(s, p, size) texture(s, (p) / (size))\n";
        else
            head += "#define SURF_SAMPLER sampler2D\n"
                    "#define SURF_FETCH(s, p, size) texelFetch(s, ivec2(p), 0)\n";
        GLuint vs = compile(GL_VERTEX_SHADER, head + VERT);
        GLuint fs = compile(GL_FRAGMENT_SHADER, std::string("#version 320 es\n") + (std::getenv("SILKY_DOCK_GLASS_RAW") ? "#define DEBUG_RAW 1\n" : "") + FRAG);
        if (!vs || !fs)
            return 0;
        GLuint p = glCreateProgram();
        glAttachShader(p, vs);
        glAttachShader(p, fs);
        glLinkProgram(p);
        glDeleteShader(vs);
        glDeleteShader(fs);
        GLint ok = 0;
        glGetProgramiv(p, GL_LINK_STATUS, &ok);
        if (!ok) {
            char log[4096] = {0};
            glGetProgramInfoLog(p, sizeof(log), nullptr, log);
            Log::logger->log(Log::ERR, std::string("[silky-dock-glass] link failed: ") + log);
            glDeleteProgram(p);
            return 0;
        }
        return p;
    }

    struct SGL {
        bool   ready = false, failed = false;
        GLuint prog[2] = {0, 0}; // [0] sampler2D surface, [1] samplerExternalOES surface
        GLuint vao = 0, vbo = 0, fbo = 0, readFbo = 0;
    } g_gl;

    bool ensureGL() {
        if (g_gl.ready || g_gl.failed)
            return g_gl.ready;
        g_gl.prog[0] = link(false);
        g_gl.prog[1] = link(true);
        if (!g_gl.prog[0]) {
            g_gl.failed = true;
            return false;
        }
        const float quad[] = {0, 0, 1, 0, 0, 1, 1, 1};
        GLint       prevVao = 0, prevBuf = 0;
        glGetIntegerv(GL_VERTEX_ARRAY_BINDING, &prevVao);
        glGetIntegerv(GL_ARRAY_BUFFER_BINDING, &prevBuf);
        glGenVertexArrays(1, &g_gl.vao);
        glGenBuffers(1, &g_gl.vbo);
        glBindVertexArray(g_gl.vao);
        glBindBuffer(GL_ARRAY_BUFFER, g_gl.vbo);
        glBufferData(GL_ARRAY_BUFFER, sizeof(quad), quad, GL_STATIC_DRAW);
        glEnableVertexAttribArray(0);
        glVertexAttribPointer(0, 2, GL_FLOAT, GL_FALSE, 0, nullptr);
        glBindVertexArray(prevVao);
        glBindBuffer(GL_ARRAY_BUFFER, prevBuf);
        glGenFramebuffers(1, &g_gl.fbo);
        glGenFramebuffers(1, &g_gl.readFbo);
        g_gl.ready = true;
        return true;
    }

    // ── per-layer state ───────────────────────────────────────────────────────────────────────────────────────────
    struct SLayer {
        GLuint                   backdrop = 0, pbo = 0;
        int                      tw = 0, th = 0, pboW = 0;
        GLsync                   fence = nullptr;
        bool                     pending = false;
        std::vector<CBox>        rects;     // CPU copy (logical, layer-local), one frame old
        std::vector<CBox>        rectAreas; // per-rect (rect + reach + margin) clipped to layer, logical
        CBox                     area;      // union of rectAreas, logical layer-local (empty: no glass)
        uint64_t                 lastSeen = 0;
    };
    std::unordered_map<void*, SLayer> g_layers;

    void freeLayer(SLayer& L) {
        if (L.backdrop)
            glDeleteTextures(1, &L.backdrop);
        if (L.pbo)
            glDeleteBuffers(1, &L.pbo);
        if (L.fence)
            glDeleteSync(L.fence);
        L = {};
    }

    bool isGlassNamespace(const std::string& ns) {
        for (auto n : NAMESPACES)
            if (ns == n)
                return true;
        return false;
    }

    std::vector<PHLLS> glassLayers(PHLMONITOR mon) {
        std::vector<PHLLS> out;
        if (!mon)
            return out;
        for (auto& lvl : mon->m_layerSurfaceLayers)
            for (auto& ref : lvl) {
                auto ls = ref.lock();
                // Fullscreen can hide a layer without unmapping it. Match the
                // compositor so glass never paints above a hidden Dock.
                if (ls && ls->mapped() && isGlassNamespace(ls->m_namespace) && !ls->isHiddenByFullscreen(mon))
                    out.push_back(ls);
            }
        return out;
    }

    SP<Render::ITexture> layerTexture(const PHLLS& ls) {
        auto res = ls->resource();
        if (!res || !res->m_current.buffer || !res->m_current.buffer->m_texture)
            return nullptr;
        auto tex = res->m_current.buffer->m_texture;
        return tex->m_texID ? tex : nullptr;
    }

    // decode the marker digits the async readback fetched (alpha bytes, one per digit)
    void decode(SLayer& L, const uint8_t* rgba, int pixels, double bufScale, const CBox& layerBox) {
        auto digit = [&](int i) -> int {
            const int x = (int)((i + 0.5) * bufScale);
            if (x >= pixels)
                return -1;
            return (int)rgba[x * 4 + 3] - 1;
        };
        auto number = [&](int start, int n) -> int {
            int v = 0;
            for (int k = 0; k < n; ++k) {
                const int d = digit(start + k);
                if (d < 0 || d > 3)
                    return -1;
                v = v * 4 + d;
            }
            return v;
        };
        L.rects.clear();
        L.rectAreas.clear();
        L.area = {};
        if (!(digit(0) == 2 && digit(1) == 3 && digit(2) == 1 && digit(3) == 1))
            return;
        const int  count = std::min(number(4, 4), MAX_RECTS);
        const CBox bounds{0, 0, layerBox.width, layerBox.height};
        CRegion    u;
        for (int i = 0; i < count; ++i) {
            const int b = HEADER + i * PER_RECT;
            const int x = number(b, 8), y = number(b + 8, 8), w = number(b + 16, 8), h = number(b + 24, 8);
            if (x < 0 || y < 0 || w <= 0 || h <= 0)
                continue;
            CBox r{x * 0.5, y * 0.5, w * 0.5, h * 0.5};
            L.rects.push_back(r);
            CBox ra = r.copy().expand(REACH + CPU_MARGIN).intersection(bounds);
            if (ra.width > 0 && ra.height > 0) {
                L.rectAreas.push_back(ra);
                u.add(ra);
            }
        }
        if (!u.empty())
            L.area = u.getExtents().intersection(bounds);
    }

    bool sameBoxes(const std::vector<CBox>& a, const std::vector<CBox>& b) {
        if (a.size() != b.size())
            return false;
        for (size_t i = 0; i < a.size(); ++i)
            if (a[i].x != b[i].x || a[i].y != b[i].y || a[i].width != b[i].width || a[i].height != b[i].height)
                return false;
        return true;
    }

    // collect last frame's readback (non-blocking) and remember if the glass area changed (so it gets repainted)
    void collect(const PHLLS& ls, SLayer& L, PHLMONITOR mon) {
        if (!L.pending || !L.fence)
            return;
        const GLenum st = glClientWaitSync(L.fence, 0, 0);
        if (st != GL_ALREADY_SIGNALED && st != GL_CONDITION_SATISFIED)
            return;
        glDeleteSync(L.fence);
        L.fence   = nullptr;
        L.pending = false;
        GLint prev = 0;
        glGetIntegerv(GL_PIXEL_PACK_BUFFER_BINDING, &prev);
        glBindBuffer(GL_PIXEL_PACK_BUFFER, L.pbo);
        auto* data = (const uint8_t*)glMapBufferRange(GL_PIXEL_PACK_BUFFER, 0, L.pboW * 4, GL_MAP_READ_BIT);
        if (data) {
            const auto  oldRectAreas = L.rectAreas;
            auto        tex          = layerTexture(ls);
            const auto& g            = ls->m_geometry;
            const double bs          = tex && g.width > 0 ? tex->m_size.x / g.width : 1.0;
            decode(L, data, L.pboW, bs, g);
            glUnmapBuffer(GL_PIXEL_PACK_BUFFER);
            // glass appeared / moved / went away: repaint each old and new rect area individually
            if (!sameBoxes(oldRectAreas, L.rectAreas)) {
                for (const auto& a : oldRectAreas)
                    if (a.width > 0 && a.height > 0)
                        g_pHyprRenderer->damageBox(CBox{g.x + a.x, g.y + a.y, a.width, a.height});
                for (const auto& a : L.rectAreas)
                    if (a.width > 0 && a.height > 0)
                        g_pHyprRenderer->damageBox(CBox{g.x + a.x, g.y + a.y, a.width, a.height});
            }
        }
        glBindBuffer(GL_PIXEL_PACK_BUFFER, prev);
    }

    // queue an async read of the marker row of the layer's buffer
    void requestReadback(const PHLLS& ls, SLayer& L) {
        if (L.pending)
            return;
        auto tex = layerTexture(ls);
        if (!tex || tex->m_type == Render::TEXTURE_EXTERNAL)
            return;
        const auto&  g  = ls->m_geometry;
        const double bs = g.width > 0 ? tex->m_size.x / g.width : 1.0;
        const int    w  = std::min((int)tex->m_size.x, (int)std::ceil(MAX_DIGITS * bs) + 2);
        if (w <= 0)
            return;
        if (!L.pbo || L.pboW != w) {
            if (L.pbo)
                glDeleteBuffers(1, &L.pbo);
            glGenBuffers(1, &L.pbo);
            GLint prev = 0;
            glGetIntegerv(GL_PIXEL_PACK_BUFFER_BINDING, &prev);
            glBindBuffer(GL_PIXEL_PACK_BUFFER, L.pbo);
            glBufferData(GL_PIXEL_PACK_BUFFER, w * 4, nullptr, GL_STREAM_READ);
            glBindBuffer(GL_PIXEL_PACK_BUFFER, prev);
            L.pboW = w;
        }
        GLint prevRead = 0, prevPack = 0;
        glGetIntegerv(GL_READ_FRAMEBUFFER_BINDING, &prevRead);
        glGetIntegerv(GL_PIXEL_PACK_BUFFER_BINDING, &prevPack);
        glBindFramebuffer(GL_READ_FRAMEBUFFER, g_gl.readFbo);
        glFramebufferTexture2D(GL_READ_FRAMEBUFFER, GL_COLOR_ATTACHMENT0, GL_TEXTURE_2D, tex->m_texID, 0);
        if (glCheckFramebufferStatus(GL_READ_FRAMEBUFFER) == GL_FRAMEBUFFER_COMPLETE) {
            glReadBuffer(GL_COLOR_ATTACHMENT0);
            glBindBuffer(GL_PIXEL_PACK_BUFFER, L.pbo);
            // the marker sits in the bottom buffer row; read the centre of the last logical pixel row
            const int row = std::max(0, (int)tex->m_size.y - 1 - (int)(bs * 0.5));
            glReadPixels(0, row, w, 1, GL_RGBA, GL_UNSIGNED_BYTE, nullptr);
            L.fence   = glFenceSync(GL_SYNC_GPU_COMMANDS_COMPLETE, 0);
            L.pending = true;
        }
        glFramebufferTexture2D(GL_READ_FRAMEBUFFER, GL_COLOR_ATTACHMENT0, GL_TEXTURE_2D, 0, 0);
        glBindBuffer(GL_PIXEL_PACK_BUFFER, prevPack);
        glBindFramebuffer(GL_READ_FRAMEBUFFER, prevRead);
    }

    CBox layerFbBox(PHLMONITOR mon, const PHLLS& ls) {
        const double s = mon->m_scale;
        const auto&  g = ls->m_geometry;
        return CBox{(g.x - mon->m_position.x) * s, (g.y - mon->m_position.y) * s, g.width * s, g.height * s}.round();
    }

    // convert a layer-local logical box to monitor-local framebuffer px
    CBox boxFb(PHLMONITOR mon, const PHLLS& ls, const CBox& b) {
        if (b.width <= 0 || b.height <= 0)
            return {};
        const double s  = mon->m_scale;
        const CBox   lb = layerFbBox(mon, ls);
        return CBox{lb.x + b.x * s, lb.y + b.y * s, b.width * s, b.height * s}.round();
    }

    // glass area of a layer in monitor-local framebuffer px (empty if none)
    CBox areaFb(PHLMONITOR mon, const PHLLS& ls, const SLayer& L) {
        return boxFb(mon, ls, L.area);
    }

    void drawLayer(PHLMONITOR mon, const PHLLS& ls, SLayer& L, const Vector2D& fb, GLint drawFb) {
        auto tex = layerTexture(ls);
        if (!tex)
            return;
        const bool external = tex->m_type == Render::TEXTURE_EXTERNAL;
        GLuint     prog     = g_gl.prog[external ? 1 : 0];
        if (!prog)
            return;
        const double s  = mon->m_scale;
        const CBox   lb = layerFbBox(mon, ls);
        const CBox   ar = areaFb(mon, ls, L);
        if (ar.width <= 0 || ar.height <= 0)
            return;

        // 1. half-resolution copy of what is under the glass (texture covers the whole layer, only the area is refreshed)
        const int tw = std::max(1, (int)lb.width / 2), th = std::max(1, (int)lb.height / 2);
        glActiveTexture(GL_TEXTURE0);
        if (!L.backdrop || L.tw != tw || L.th != th) {
            if (L.backdrop)
                glDeleteTextures(1, &L.backdrop);
            glGenTextures(1, &L.backdrop);
            glBindTexture(GL_TEXTURE_2D, L.backdrop);
            int levels = 1;
            for (int m = std::max(tw, th); m > 1 && levels < 7; m >>= 1)
                levels++;
            glTexStorage2D(GL_TEXTURE_2D, levels, GL_RGBA8, tw, th);
            glTexParameteri(GL_TEXTURE_2D, GL_TEXTURE_MIN_FILTER, GL_LINEAR_MIPMAP_LINEAR);
            glTexParameteri(GL_TEXTURE_2D, GL_TEXTURE_MAG_FILTER, GL_LINEAR);
            glTexParameteri(GL_TEXTURE_2D, GL_TEXTURE_WRAP_S, GL_CLAMP_TO_EDGE);
            glTexParameteri(GL_TEXTURE_2D, GL_TEXTURE_WRAP_T, GL_CLAMP_TO_EDGE);
            glTexParameteri(GL_TEXTURE_2D, GL_TEXTURE_MAX_LEVEL, levels - 1);
            L.tw = tw;
            L.th = th;
        }
        GLint readFb = 0;
        glGetIntegerv(GL_READ_FRAMEBUFFER_BINDING, &readFb);
        // Hyprland binds only the DRAW framebuffer: read from it, or the copy comes from a stale buffer
        glBindFramebuffer(GL_READ_FRAMEBUFFER, drawFb);
        glBindFramebuffer(GL_DRAW_FRAMEBUFFER, g_gl.fbo);
        glFramebufferTexture2D(GL_DRAW_FRAMEBUFFER, GL_COLOR_ATTACHMENT0, GL_TEXTURE_2D, L.backdrop, 0);
        int vx0 = (int)fb.x, vy0 = (int)fb.y, vx1 = 0, vy1 = 0;
        for (const auto& ra : L.rectAreas) {
            const CBox rfb = boxFb(mon, ls, ra);
            const int  bx0 = std::clamp((int)rfb.x, 0, (int)fb.x) & ~1;
            const int  bx1 = std::clamp((int)(rfb.x + rfb.width), 0, (int)fb.x);
            const int  by0 = std::clamp((int)rfb.y, 0, (int)fb.y) & ~1;
            const int  by1 = std::clamp((int)(rfb.y + rfb.height), 0, (int)fb.y);
            if (bx1 <= bx0 || by1 <= by0)
                continue;
            const int dx0 = (bx0 - (int)lb.x) / 2, dy0 = (by0 - (int)lb.y) / 2;
            const int dx1 = (bx1 - (int)lb.x) / 2, dy1 = (by1 - (int)lb.y) / 2;
            glBlitFramebuffer(bx0, by0, bx1, by1, std::clamp(dx0, 0, tw), std::clamp(dy0, 0, th), std::clamp(dx1, 0, tw), std::clamp(dy1, 0, th), GL_COLOR_BUFFER_BIT,
                              GL_LINEAR);
            vx0 = std::min(vx0, bx0);
            vy0 = std::min(vy0, by0);
            vx1 = std::max(vx1, bx1);
            vy1 = std::max(vy1, by1);
        }
        glBindFramebuffer(GL_DRAW_FRAMEBUFFER, drawFb);
        glBindFramebuffer(GL_READ_FRAMEBUFFER, readFb);
        if (vx1 <= vx0 || vy1 <= vy0)
            return;
        glBindTexture(GL_TEXTURE_2D, L.backdrop);
        glGenerateMipmap(GL_TEXTURE_2D);

        // 2. the glass, one instance per rectangle
        glActiveTexture(GL_TEXTURE1);
        glBindTexture(external ? GL_TEXTURE_EXTERNAL_OES : GL_TEXTURE_2D, tex->m_texID);
        glUseProgram(prog);
        const auto& g = ls->m_geometry;
        glUniform1i(glGetUniformLocation(prog, "uSurf"), 1);
        glUniform2f(glGetUniformLocation(prog, "uSurfPx"), tex->m_size.x, tex->m_size.y);
        glUniform1f(glGetUniformLocation(prog, "uBufScale"), g.width > 0 ? tex->m_size.x / g.width : 1.0);
        glUniform2f(glGetUniformLocation(prog, "uLayerFb"), lb.x, lb.y);
        glUniform1f(glGetUniformLocation(prog, "uMonScale"), s);
        glUniform2f(glGetUniformLocation(prog, "uFb"), fb.x, fb.y);
        glUniform1f(glGetUniformLocation(prog, "uLayerHLogical"), g.height);
        glUniform1i(glGetUniformLocation(prog, "uBack"), 0);
        glUniform4f(glGetUniformLocation(prog, "uBand"), lb.x, lb.y, tw * 2.0, th * 2.0);
        glUniform1f(glGetUniformLocation(prog, "uS"), s);
        glUniform1f(glGetUniformLocation(prog, "uTexScale"), 0.5f);
        glUniform4f(glGetUniformLocation(prog, "uValid"), vx0, vy0, vx1, vy1);
        const auto& P = params();
        auto        set3 = [&](const char* name, float a, float b, float c) {
            const float v[3] = {a, b, c};
            glUniform1fv(glGetUniformLocation(prog, name), 3, v);
        };
        set3("uTint", P.k[0].tint, P.k[1].tint, P.k[2].tint);
        set3("uTintDark", P.k[0].tintDark, P.k[1].tintDark, P.k[2].tintDark);
        set3("uBlur", P.k[0].blur, P.k[1].blur, P.k[2].blur);
        set3("uBezel", P.k[0].bezel, P.k[1].bezel, P.k[2].bezel);
        set3("uThick", P.k[0].thickness, P.k[1].thickness, P.k[2].thickness);
        set3("uDisperse", P.k[0].dispersion, P.k[1].dispersion, P.k[2].dispersion);
        set3("uMagnify", P.k[0].magnify, P.k[1].magnify, P.k[2].magnify);
        set3("uSat", P.k[0].saturation, P.k[1].saturation, P.k[2].saturation);
        set3("uLift", P.k[0].lift, P.k[1].lift, P.k[2].lift);
        set3("uRim", P.k[0].rim, P.k[1].rim, P.k[2].rim);
        glBindVertexArray(g_gl.vao);
        // every slot: the marker (decoded on the GPU) is newer than the CPU copy; unused slots collapse to nothing
        glDrawArraysInstanced(GL_TRIANGLE_STRIP, 0, 4, MAX_RECTS);
    }

    // one id per frame and monitor: only the newest element draws (a queued but unrendered one can never match)
    uint64_t                            g_nextId = 1;
    std::unordered_map<void*, uint64_t> g_lastId;

    class CGlassElement : public IPassElement {
      public:
        CGlassElement(PHLMONITOR mon, uint64_t id) : m_mon(mon), m_id(id) {}

        std::vector<UP<IPassElement>> draw(Render::CRenderContext& ctx) override {
            auto mon = m_mon.lock();
            if (!mon || g_lastId[mon.get()] != m_id || !ensureGL())
                return {};
            GLint vp[4] = {0, 0, 0, 0};
            glGetIntegerv(GL_VIEWPORT, vp); // ctx.m_data.fbSize is not filled in here
            const Vector2D fb = {(double)vp[2], (double)vp[3]};
            if (fb.x <= 0 || fb.y <= 0)
                return {};

            GLint     prevProg, prevVao, prevActive, prevTex0, prevTex1, prevTexExt1, prevSrc, prevDst, prevSrcA, prevDstA, drawFb;
            GLboolean prevBlend = glIsEnabled(GL_BLEND), prevScissor = glIsEnabled(GL_SCISSOR_TEST);
            glGetIntegerv(GL_CURRENT_PROGRAM, &prevProg);
            glGetIntegerv(GL_VERTEX_ARRAY_BINDING, &prevVao);
            glGetIntegerv(GL_ACTIVE_TEXTURE, &prevActive);
            glActiveTexture(GL_TEXTURE0);
            glGetIntegerv(GL_TEXTURE_BINDING_2D, &prevTex0);
            glActiveTexture(GL_TEXTURE1);
            glGetIntegerv(GL_TEXTURE_BINDING_2D, &prevTex1);
            glGetIntegerv(GL_TEXTURE_BINDING_EXTERNAL_OES, &prevTexExt1);
            glGetIntegerv(GL_BLEND_SRC_RGB, &prevSrc);
            glGetIntegerv(GL_BLEND_DST_RGB, &prevDst);
            glGetIntegerv(GL_BLEND_SRC_ALPHA, &prevSrcA);
            glGetIntegerv(GL_BLEND_DST_ALPHA, &prevDstA);
            glGetIntegerv(GL_DRAW_FRAMEBUFFER_BINDING, &drawFb);
            glDisable(GL_SCISSOR_TEST);
            glEnable(GL_BLEND);
            glBlendFuncSeparate(GL_ONE, GL_ONE_MINUS_SRC_ALPHA, GL_ONE, GL_ONE_MINUS_SRC_ALPHA);

            for (auto& ls : glassLayers(mon)) {
                auto& L = g_layers[ls.get()];
                L.lastSeen = g_stats.frames;
                drawLayer(mon, ls, L, fb, drawFb);
                glBlendFuncSeparate(GL_ONE, GL_ONE_MINUS_SRC_ALPHA, GL_ONE, GL_ONE_MINUS_SRC_ALPHA);
                requestReadback(ls, L);
            }

            glBindVertexArray(prevVao);
            glUseProgram(prevProg);
            glActiveTexture(GL_TEXTURE1);
            glBindTexture(GL_TEXTURE_2D, prevTex1);
            glBindTexture(GL_TEXTURE_EXTERNAL_OES, prevTexExt1);
            glActiveTexture(GL_TEXTURE0);
            glBindTexture(GL_TEXTURE_2D, prevTex0);
            glActiveTexture(prevActive);
            glBlendFuncSeparate(prevSrc, prevDst, prevSrcA, prevDstA);
            if (!prevBlend)
                glDisable(GL_BLEND);
            if (prevScissor)
                glEnable(GL_SCISSOR_TEST);
            g_stats.frames++;
            return {};
        }

        bool                needsLiveBlur(Render::CRenderContext&) override { return false; }
        bool                needsPrecomputeBlur(Render::CRenderContext&) override { return false; }
        const char*         passName() override { return "CSilkyGlassElement"; }
        ePassElementType    type() override { return EK_CUSTOM; }
        bool                undiscardable(Render::CRenderContext&) override { return true; }
        bool                disableSimplification(Render::CRenderContext&) override { return true; }
        std::optional<CBox> boundingBox(Render::CRenderContext&) override {
            auto mon = m_mon.lock();
            if (!mon)
                return std::nullopt;
            return CBox{0, 0, mon->m_size.x, mon->m_size.y};
        }
        CRegion opaqueRegion(Render::CRenderContext&) override { return {}; }
        // The copied backdrop must be from this frame everywhere under each glass rect: when anything within reach of
        // a glass rect changes, only that rect's area joins this frame's damage (never the whole monitor or unrelated
        // rects on the same layer).
        bool requiresFullDamage(Render::CRenderContext& ctx) override {
            auto mon = m_mon.lock();
            if (!mon)
                return false;
            for (auto& ls : glassLayers(mon)) {
                auto it = g_layers.find(ls.get());
                if (it == g_layers.end())
                    continue;
                for (const auto& ra : it->second.rectAreas) {
                    const CBox a = boxFb(mon, ls, ra);
                    if (a.width <= 0 || ctx.m_data.damage.copy().intersect(a).empty())
                        continue;
                    ctx.m_data.damage.add(a);
                    g_stats.damaged++;
                }
            }
            return false;
        }

      private:
        PHLMONITORREF m_mon;
        uint64_t      m_id = 0;
    };

    void onStage(const Event::SRenderStageEvent& e) {
        if (e.stage != RENDER_POST_WINDOWS || !e.context || !e.monitor)
            return;
        auto& ctx = e.context->get();
        if (ctx.m_renderingCapture || ctx.m_renderingSnapshot)
            return;
        auto layers = glassLayers(e.monitor);
        if (layers.empty())
            return;
        // last frame's readbacks: where the glass is now (GL context is current at this stage)
        if (ensureGL())
            for (auto& ls : layers)
                collect(ls, g_layers[ls.get()], e.monitor);
        // forget layers that are gone (their GL objects too)
        for (auto it = g_layers.begin(); it != g_layers.end();) {
            if (g_stats.frames > it->second.lastSeen + 600) {
                freeLayer(it->second);
                it = g_layers.erase(it);
            } else
                ++it;
        }
        const uint64_t id = g_nextId++;
        g_lastId[e.monitor.get()] = id;
        Render::IHyprRenderer::addPassElement(ctx, makeUnique<CGlassElement>(e.monitor, id));
    }
}

APICALL EXPORT std::string PLUGIN_API_VERSION() {
    return HYPRLAND_API_VERSION;
}

APICALL EXPORT PLUGIN_DESCRIPTION_INFO PLUGIN_INIT(HANDLE handle) {
    PHANDLE = handle;
    if (__hyprland_api_get_hash() != std::string(__hyprland_api_get_client_hash()))
        throw std::runtime_error("[silky-dock-glass] built for a different Hyprland: rebuild the plugin");
    g_listeners.emplace_back(Event::bus()->m_events.render.stage.listen([](const Event::SRenderStageEvent& e) { onStage(e); }));
    for (auto& m : State::monitorState()->monitors())
        g_pHyprRenderer->damageMonitor(m);
    return {"silky-dock-glass", "Zero-latency Liquid Glass for MacShell Dock, menus, Control Center and overlays, refracted by the compositor", "sqlsec", "0.4.0"};
}

APICALL EXPORT void PLUGIN_EXIT() {
    g_listeners.clear();
    Log::logger->log(Log::INFO, std::format("[silky-dock-glass] frames drawn: {}, glass-area damage additions: {}", g_stats.frames, g_stats.damaged));
    if (g_gl.ready) {
        for (auto& [k, L] : g_layers)
            freeLayer(L);
        for (auto p : g_gl.prog)
            if (p)
                glDeleteProgram(p);
        glDeleteVertexArrays(1, &g_gl.vao);
        glDeleteBuffers(1, &g_gl.vbo);
        glDeleteFramebuffers(1, &g_gl.fbo);
        glDeleteFramebuffers(1, &g_gl.readFbo);
    }
    g_layers.clear();
    g_gl = {};
    for (auto& m : State::monitorState()->monitors())
        g_pHyprRenderer->damageMonitor(m);
}
