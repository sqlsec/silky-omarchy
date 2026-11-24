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
#include <hyprland/src/desktop/view/window/Window.hpp>
#include <hyprland/src/desktop/view/window/WindowMetadata.hpp>
#include <hyprland/src/desktop/view/window/WindowPresentation.hpp>
#include <hyprland/src/event/EventBus.hpp>
#include <hyprland/src/output/Monitor.hpp>
#include <hyprland/src/protocols/core/Compositor.hpp>
#include <hyprland/src/protocols/types/Buffer.hpp>
#include <hyprland/src/render/Renderer.hpp>
#include <hyprland/src/render/Context.hpp>
#include <hyprland/src/render/WindowRenderPresentation.hpp>
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
    SP<IPC::Socket1::SCommand>       g_statsCmd;

    constexpr int    MAX_RECTS   = 24;
    constexpr int    HEADER      = 8;  // magic (4) + count (4)
    constexpr int    PER_RECT    = 46; // x y w h r (8 each) + alpha (4) + dark (1) + kind (1)
    constexpr int    CLIP_DIGITS = 24; // viewport top, bottom and bottom feather (8 digits each, in half px)
    constexpr int    MAX_DIGITS  = HEADER + MAX_RECTS * PER_RECT + CLIP_DIGITS;
    constexpr double REACH       = 48; // logical px the glass reads around itself (refraction + blur)
    constexpr double CPU_MARGIN  = 24; // the CPU copy of the rects is a frame old: margin for moving / growing glass

    // Layers whose glass rectangles are painted by this plugin (macbarbg — the thin top bar strip — stays on plain blur).
    const char* NAMESPACES[] = {"macdock", "macbar", "macspot", "macosd", "macswitch", "macwall"};

    struct SStats {
        uint64_t frames = 0, skipped = 0, readbacks = 0, damaged = 0, winFrames = 0, winDamaged = 0;
    } g_stats;

    // ── parameters (per kind: 0 = Dock, 1 = menus / panels, 2 = Control Center bubbles), live-tunable ──────────────
    struct SKind {
        float blur, tint, bezel, thickness, dispersion, magnify, saturation, lift, rim, tintDark;
    };
    struct SWinBlurParams {
        float blur       = 20.0f; // logical px blur radius
        float saturation = 1.15f;
        float contrast   = 1.04f;
        float brightness = 1.00f;
    };
    struct SParams {
        static constexpr SKind controlCenter{5.5f, 0.09f, 14.f, 24.f, 0.09f, 0.00f, 1.22f, 0.018f, 0.88f, 0.18f};

        // Tuned toward macOS 26/27 Liquid Glass (physical Convex Squircle Snell refraction):
        //   0 = Dock: clean optical glass, crisp narrow bezel that reflects interior icons/dots at the rim
        //   1 = Menus / Notification Center / Spotlight: CC optics with a little more blur and tint for text
        //   2 = Control Center floating tiles: clear jewel-like liquid bubbles with lively Snell rim refraction
        SKind k[3] = {
            {6.5f, 0.10f, 14.f, 22.f, 0.08f, 0.00f, 1.12f, 0.012f, 0.72f, 0.22f},
            {7.5f, 0.11f, controlCenter.bezel, controlCenter.thickness, controlCenter.dispersion,
             controlCenter.magnify, controlCenter.saturation, controlCenter.lift, controlCenter.rim, 0.20f},
            controlCenter,
        };
        SWinBlurParams win{};
    };
    // ~/.config/silky-omarchy/dock-glass.conf: "key = value"; plain = Dock, "menu_" = menus/panels, "cc_" = Control Center bubbles, "win_" = floating window blur
    const SParams& params() {
        static SParams  p;
        static int64_t  lastMtime = -1;
        static uint64_t lastCheck = 0;
        const uint64_t  tick      = g_stats.frames + g_stats.winFrames;
        if (tick - lastCheck < 30 && lastMtime != -1)
            return p;
        lastCheck = tick;
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
            if (k.starts_with("win_")) {
                const std::string wk = k.substr(4);
                float             v  = 0;
                try {
                    v = std::stof(trim(line.substr(eq + 1)));
                } catch (...) { continue; }
                if (wk == "blur") p.win.blur = v;
                else if (wk == "saturation") p.win.saturation = v;
                else if (wk == "contrast") p.win.contrast = v;
                else if (wk == "brightness") p.win.brightness = v;
                continue;
            }
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
flat out vec2  vBottomFade;                 // framebuffer y of the viewport bottom and feather width
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
    bool clipped = fk == 3;
    if (clipped) fy -= 32768;               // a scrolling card can start above the surface
    vec2 xy = vec2(float(fx), float(fy)) * 0.5;
    vec2 wh = vec2(float(fw), float(fh)) * 0.5;
    vec4 r  = vec4(uLayerFb + xy * uMonScale, wh * uMonScale);
    vRect   = r;
    vRadius = float(fr) * 0.5 * uMonScale;
    vDark   = float(fd);
    vAlpha  = float(fa) / 255.0;
    vKind   = clamp(fk, 0, 2);
    vBottomFade = vec2(0.0);
    vec2 lo = r.xy - 2.0, hi = r.xy + r.zw + 2.0;
    if (clipped) {
        int clip = 8 + count * 46;
        int top = number(clip, 8), bottom = number(clip + 8, 8), fade = number(clip + 16, 8);
        ok = ok && top >= 0 && bottom > top && fade >= 0;
        lo.y = max(lo.y, uLayerFb.y + float(top) * 0.5 * uMonScale);
        hi.y = min(hi.y, uLayerFb.y + float(bottom) * 0.5 * uMonScale);
        vBottomFade = vec2(uLayerFb.y + float(bottom) * 0.5 * uMonScale, float(fade) * 0.5 * uMonScale);
        ok = ok && hi.y > lo.y;
    }
    vec2 p  = mix(lo, hi, aPos);
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
flat in vec2  vBottomFade;
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

const int   TAPS       = 20;
const int   LARGE_TAPS = 8;
const float LARGE_AREA = 160000.0;            // logical px^2 (~400x400): Applications panel, Wallpaper picker, full Spotlight
const float GOLDEN     = 2.39996323;

vec3 back(vec2 p, float lod) {
    vec2 uv = (p - uBand.xy) / uBand.zw;
    return textureLod(uBack, clamp(uv, vec2(0.001), vec2(0.999)), lod).rgb;
}
float ign(vec2 p) { return fract(52.9829189 * fract(dot(p, vec2(0.06711056, 0.00583715)))); }
float hash12(vec2 p) { vec3 p3 = fract(vec3(p.xyx) * 0.1031); p3 += dot(p3, p3.yzx + 33.33); return fract((p3.x + p3.y) * p3.z); }

vec3 blurredDisp(vec2 p, vec2 disp, float disperse, float rad, int taps, bool allowDisp) {
    float R   = max(rad, 0.5);
    float gap = R * sqrt(3.14159265 / float(taps));
    float lod = clamp(log2(max(gap * uTexScale, 1.0)) + 0.35, 0.0, 6.0);
    float rot = ign(gl_FragCoord.xy) * 6.2831853;
    bool dispersed = allowDisp && length(disp) * disperse > 0.25;   // subtle chromatic fringes along high-contrast edges
    vec3 acc = vec3(0.0); float ws = 0.0;
    for (int i = 0; i < taps; ++i) {
        float fi = float(i) + 0.5, r = sqrt(fi / float(taps)), a = fi * GOLDEN + rot, w = exp(-2.2 * r * r);
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
    if (vBottomFade.y > 0.0)
        cov *= smoothstep(0.0, vBottomFade.y, vBottomFade.x - vFb.y);
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
    // Exact analytical derivative dh/du = om^3 / h^3, softly capped and faded at the outer lip so the
    // 1-px silhouette edge samples its own backdrop instead of folding distant bright text onto a dark rim.
    float slope   = om3 / max(h * h * h, 0.24);
    // 3D outward surface normal (z pointing toward viewer); Snell refraction of view ray I = (0, 0, -1)
    vec3  N       = normalize(vec3(g * slope, 1.0));
    float eta     = 1.0 / 1.50;                                         // air (1.0) -> optical glass (1.50)
    vec3  R       = refract(vec3(0.0, 0.0, -1.0), N, eta);
    float lipFade = smoothstep(0.0, 0.28, u);
    // R.xy points along -g (inward); physical thickness vanishes at the outer lip (h * lipFade -> 0)
    vec2  rayOff  = (R.xy / max(abs(R.z), 0.25)) * (abs(uThick[K]) * h * lipFade);
    vec2  disp    = (uThick[K] >= 0.0 ? rayOff : -rayOff);              // logical px, inward along -g

    // Keep the bevel blur consistent with the body so dark edges do not show a sharp refraction seam.
    // Large panels (Applications, Wallpaper picker, expanded Spotlight) use 8-tap mipmap sampling without
    // 3x chromatic dispersion to cut fragment texture fetches by >60% while keeping identical refraction & rim.
    bool  large = (hs.x * hs.y * 4.0) > LARGE_AREA;
    float blurR = uBlur[K] * mix(0.86, 1.0, smoothstep(0.0, 0.70, u));
    vec2  lens  = q * -uMagnify[K];
    vec3  col   = blurredDisp(vFb, (disp + lens) * uS, uDisperse[K] * 0.45 * lipFade, blurR * uS, large ? LARGE_TAPS : TAPS, !large);

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
    // natural top-left key light and restrained dark-mode bottom rim (no artificial white highlight on dark backdrops).
    vec2  lightDir = normalize(vec2(-0.50, -0.86));
    float dKey     = max(0.0, dot(g, lightDir));
    float dOpp     = max(0.0, dot(g, -lightDir));
    float topBias  = smoothstep(-0.35, 0.75, -g.y);
    float darkFade = mix(1.0, mix(0.45, 1.0, topBias), vDark);
    float specArc  = pow(dKey, 2.4) * 0.42 + pow(dOpp, 3.2) * mix(0.20, 0.08, vDark) + pow(max(0.0, -g.y), 1.6) * 0.10;
    float baseRing = mix(0.16, 0.12, vDark) + 0.10 * topBias;
    float rimLine  = exp(-pow((t - 0.50) / 0.34, 2.0));
    float rimGlow  = exp(-t / mix(2.2, 3.6, topBias)) * darkFade;
    float rimAmt   = (rimLine * (baseRing + specArc) + rimGlow * (0.018 + specArc * 0.08)) * uRim[K];
    col = col * (1.0 + rimAmt * mix(0.40, 0.25, vDark)) + vec3(rimAmt * mix(0.55, 0.28, vDark));

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

    const char* WIN_VERT = R"GLSL(
precision highp float;
layout(location = 0) in vec2 aPos;
uniform vec4 uRect;                         // window rect in framebuffer px: x, y (top), w, h
uniform vec2 uFb;                           // framebuffer size, px
out vec2 vFb;
void main() {
    vec2 p = uRect.xy + aPos * uRect.zw;
    vFb = p;
    gl_Position = vec4(p / uFb * 2.0 - 1.0, 0.0, 1.0);
}
)GLSL";

    const char* WIN_FRAG = R"GLSL(
precision highp float;
in vec2 vFb;
layout(location = 0) out vec4 fragColor;

uniform sampler2D uBack;                    // half-resolution mipmapped backdrop copy
uniform vec4  uBand;                        // copied backdrop area in framebuffer px: x, y, w, h
uniform vec4  uRect;                        // window rect in framebuffer px: x, y, w, h
uniform float uRadius;                      // corner radius, framebuffer px
uniform float uRoundPow;                    // superellipse exponent (Hyprland rounding_power)
uniform float uBlurPx;                      // blur radius, framebuffer px
uniform float uAlpha;                       // window alpha
uniform float uSat;
uniform float uContrast;
uniform float uBrightness;

const int   W_TAPS = 8;
const float GOLDEN = 2.39996323;

float ign(vec2 p) { return fract(52.9829189 * fract(dot(p, vec2(0.06711056, 0.00583715)))); }

void main() {
    vec2  hs  = uRect.zw * 0.5;
    float rad = min(uRadius, min(hs.x, hs.y));
    vec2  q   = abs(vFb - (uRect.xy + hs)) - (hs - rad);
    float sd;
    if (q.x > 0.0 && q.y > 0.0 && rad > 0.5) {
        float p  = max(uRoundPow, 2.0);
        vec2  t  = q / rad;
        float lp = pow(pow(t.x, p) + pow(t.y, p), 1.0 / p);
        sd       = (lp - 1.0) * rad;
    } else {
        sd = max(q.x, q.y) - rad;
    }
    float cov = clamp(0.5 - sd, 0.0, 1.0) * uAlpha;
    if (cov <= 0.0) discard;

    float R   = max(uBlurPx, 1.0);
    float gap = R * sqrt(3.14159265 / float(W_TAPS));
    float lod = clamp(log2(max(gap * 0.5, 1.0)) + 0.35, 0.0, 6.0);
    float rot = ign(gl_FragCoord.xy) * 6.2831853;
    vec3  acc = vec3(0.0);
    float ws  = 0.0;
    for (int i = 0; i < W_TAPS; ++i) {
        float fi = float(i) + 0.5;
        float r  = sqrt(fi / float(W_TAPS));
        float a  = fi * GOLDEN + rot;
        float w  = exp(-2.2 * r * r);
        vec2  sp = vFb + vec2(cos(a), sin(a)) * (r * R);
        vec2  uv = (sp - uBand.xy) / uBand.zw;
        acc += textureLod(uBack, clamp(uv, vec2(0.002), vec2(0.998)), lod).rgb * w;
        ws  += w;
    }
    vec3 col = acc / ws;
    float lum = dot(col, vec3(0.2126, 0.7152, 0.0722));
    col = mix(vec3(lum), col, uSat);
    col = (col - 0.5) * uContrast + 0.5;
    col = clamp(col * uBrightness, 0.0, 1.0);
    col += (ign(gl_FragCoord.xy + 13.7) - 0.5) / 255.0;
    col = clamp(col, 0.0, 1.0);
    fragColor = vec4(col * cov, cov);
}
)GLSL";

    GLuint linkWinBlur() {
        GLuint vs = compile(GL_VERTEX_SHADER, std::string("#version 320 es\n") + WIN_VERT);
        GLuint fs = compile(GL_FRAGMENT_SHADER, std::string("#version 320 es\n") + WIN_FRAG);
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
            Log::logger->log(Log::ERR, std::string("[silky-dock-glass] window blur link failed: ") + log);
            glDeleteProgram(p);
            return 0;
        }
        return p;
    }

    struct SGlassUniforms {
        GLint uSurf = -1, uSurfPx = -1, uBufScale = -1, uLayerFb = -1, uMonScale = -1, uFb = -1, uLayerHLogical = -1;
        GLint uBack = -1, uBand = -1, uS = -1, uTexScale = -1, uValid = -1;
        GLint uTint = -1, uTintDark = -1, uBlur = -1, uBezel = -1, uThick = -1, uDisperse = -1, uMagnify = -1;
        GLint uSat = -1, uLift = -1, uRim = -1;

        void init(GLuint prog) {
            if (!prog)
                return;
            uSurf          = glGetUniformLocation(prog, "uSurf");
            uSurfPx        = glGetUniformLocation(prog, "uSurfPx");
            uBufScale      = glGetUniformLocation(prog, "uBufScale");
            uLayerFb       = glGetUniformLocation(prog, "uLayerFb");
            uMonScale      = glGetUniformLocation(prog, "uMonScale");
            uFb            = glGetUniformLocation(prog, "uFb");
            uLayerHLogical = glGetUniformLocation(prog, "uLayerHLogical");
            uBack          = glGetUniformLocation(prog, "uBack");
            uBand          = glGetUniformLocation(prog, "uBand");
            uS             = glGetUniformLocation(prog, "uS");
            uTexScale      = glGetUniformLocation(prog, "uTexScale");
            uValid         = glGetUniformLocation(prog, "uValid");
            uTint          = glGetUniformLocation(prog, "uTint");
            uTintDark      = glGetUniformLocation(prog, "uTintDark");
            uBlur          = glGetUniformLocation(prog, "uBlur");
            uBezel         = glGetUniformLocation(prog, "uBezel");
            uThick         = glGetUniformLocation(prog, "uThick");
            uDisperse      = glGetUniformLocation(prog, "uDisperse");
            uMagnify       = glGetUniformLocation(prog, "uMagnify");
            uSat           = glGetUniformLocation(prog, "uSat");
            uLift          = glGetUniformLocation(prog, "uLift");
            uRim           = glGetUniformLocation(prog, "uRim");
        }
    };

    struct SWinUniforms {
        GLint uBack = -1, uBand = -1, uRect = -1, uFb = -1, uRadius = -1, uRoundPow = -1;
        GLint uBlurPx = -1, uAlpha = -1, uSat = -1, uContrast = -1, uBrightness = -1;

        void init(GLuint prog) {
            if (!prog)
                return;
            uBack       = glGetUniformLocation(prog, "uBack");
            uBand       = glGetUniformLocation(prog, "uBand");
            uRect       = glGetUniformLocation(prog, "uRect");
            uFb         = glGetUniformLocation(prog, "uFb");
            uRadius     = glGetUniformLocation(prog, "uRadius");
            uRoundPow   = glGetUniformLocation(prog, "uRoundPow");
            uBlurPx     = glGetUniformLocation(prog, "uBlurPx");
            uAlpha      = glGetUniformLocation(prog, "uAlpha");
            uSat        = glGetUniformLocation(prog, "uSat");
            uContrast   = glGetUniformLocation(prog, "uContrast");
            uBrightness = glGetUniformLocation(prog, "uBrightness");
        }
    };

    struct SGL {
        bool           ready = false, failed = false;
        GLuint         prog[2] = {0, 0}; // [0] sampler2D surface, [1] samplerExternalOES surface
        GLuint         winProg = 0;      // half-res mipmap backdrop blur for floating glass windows
        SGlassUniforms glassU[2];
        SWinUniforms   winU;
        GLuint         vao = 0, vbo = 0, fbo = 0, readFbo = 0;
    } g_gl;

    bool ensureGL() {
        if (g_gl.ready || g_gl.failed)
            return g_gl.ready;
        g_gl.prog[0] = link(false);
        g_gl.prog[1] = link(true);
        g_gl.winProg = linkWinBlur();
        if (!g_gl.prog[0]) {
            g_gl.failed = true;
            return false;
        }
        g_gl.glassU[0].init(g_gl.prog[0]);
        g_gl.glassU[1].init(g_gl.prog[1]);
        g_gl.winU.init(g_gl.winProg);
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
        bool                     dirtyMarker = true;
        void*                    boundRes = nullptr;
        GLuint                   lastTexId = 0;
        CBox                     lastGeo;
        CHyprSignalListener      commitListener;
        std::vector<CBox>        rects;     // CPU copy (logical, layer-local), one frame old
        std::vector<CBox>        rectAreas; // per-rect (rect + reach + margin) clipped to layer, logical
        CBox                     area;      // union of rectAreas, logical layer-local (empty: no glass)
        uint64_t                 lastSeen = 0;
    };
    std::unordered_map<void*, SLayer> g_layers;

    void freeLayer(SLayer& L) {
        L.commitListener.reset();
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
        const int  clip = HEADER + count * PER_RECT;
        const int  clipTop = number(clip, 8), clipBottom = number(clip + 8, 8);
        const CBox bounds{0, 0, layerBox.width, layerBox.height};
        CRegion    u;
        for (int i = 0; i < count; ++i) {
            const int b = HEADER + i * PER_RECT;
            const int x = number(b, 8), y = number(b + 8, 8), w = number(b + 16, 8), h = number(b + 24, 8);
            if (x < 0 || y < 0 || w <= 0 || h <= 0)
                continue;
            const bool clipped = digit(b + 45) == 3;
            CBox r{x * 0.5, (y - (clipped ? 32768 : 0)) * 0.5, w * 0.5, h * 0.5};
            if (clipped) {
                if (clipTop < 0 || clipBottom <= clipTop)
                    continue;
                r = r.intersection(CBox{0, clipTop * 0.5, layerBox.width, (clipBottom - clipTop) * 0.5});
                if (r.width <= 0 || r.height <= 0)
                    continue;
            }
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

    // Track surface commits, texture swaps, and geometry changes so we only run PBO marker readbacks when
    // the layer's surface could actually have updated (instead of every compositor frame at 90/110 Hz).
    void trackLayerCommit(const PHLLS& ls, SLayer& L) {
        auto res = ls->resource();
        if (res.get() != L.boundRes) {
            L.commitListener.reset();
            L.boundRes = res.get();
            if (res) {
                void* key = ls.get();
                L.commitListener = res->m_events.commit.listen([key]() {
                    auto it = g_layers.find(key);
                    if (it != g_layers.end())
                        it->second.dirtyMarker = true;
                });
            }
            L.dirtyMarker = true;
        }
        auto         tex   = layerTexture(ls);
        const GLuint texId = tex ? tex->m_texID : 0;
        if (texId != L.lastTexId) {
            L.lastTexId   = texId;
            L.dirtyMarker = true;
        }
        const auto& g = ls->m_geometry;
        if (g.x != L.lastGeo.x || g.y != L.lastGeo.y || g.width != L.lastGeo.width || g.height != L.lastGeo.height) {
            L.lastGeo     = g;
            L.dirtyMarker = true;
        }
    }

    // queue an async read of the marker row of the layer's buffer (only when the surface actually changed)
    void requestReadback(const PHLLS& ls, SLayer& L) {
        if (L.pending || !L.dirtyMarker)
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
            L.fence       = glFenceSync(GL_SYNC_GPU_COMMANDS_COMPLETE, 0);
            L.pending     = true;
            L.dirtyMarker = false;
            g_stats.readbacks++;
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

    bool layerTouchesDamage(PHLMONITOR mon, const PHLLS& ls, const SLayer& L, const CRegion& damage) {
        if (L.rectAreas.empty())
            return false;
        for (const auto& ra : L.rectAreas) {
            const CBox a = boxFb(mon, ls, ra);
            if (a.width > 0 && a.height > 0 && !damage.copy().intersect(a).empty())
                return true;
        }
        return false;
    }

    void drawLayer(PHLMONITOR mon, const PHLLS& ls, SLayer& L, const Vector2D& fb, GLint drawFb) {
        auto tex = layerTexture(ls);
        if (!tex)
            return;
        const bool external = tex->m_type == Render::TEXTURE_EXTERNAL;
        const int  pi       = external ? 1 : 0;
        GLuint     prog     = g_gl.prog[pi];
        if (!prog)
            return;
        const double s  = mon->m_scale;
        const CBox   lb = layerFbBox(mon, ls);
        const CBox   ar = areaFb(mon, ls, L);
        if (ar.width <= 0 || ar.height <= 0)
            return;

        // Compute the tight framebuffer bounding box of active glass rects (aligned to even px) so fullscreen layers
        // like macbar/macspot only allocate & mipmap the glass region instead of the entire 3K/4K output.
        const int fbW = (int)fb.x, fbH = (int)fb.y;
        int       vx0 = fbW, vy0 = fbH, vx1 = 0, vy1 = 0;
        for (const auto& ra : L.rectAreas) {
            const CBox rfb = boxFb(mon, ls, ra);
            const int  bx0 = std::clamp((int)rfb.x, 0, fbW) & ~1;
            const int  bx1 = std::min(fbW, (std::clamp((int)(rfb.x + rfb.width), 0, fbW) + 1) & ~1);
            const int  by0 = std::clamp((int)rfb.y, 0, fbH) & ~1;
            const int  by1 = std::min(fbH, (std::clamp((int)(rfb.y + rfb.height), 0, fbH) + 1) & ~1);
            if (bx1 <= bx0 || by1 <= by0)
                continue;
            vx0 = std::min(vx0, bx0);
            vy0 = std::min(vy0, by0);
            vx1 = std::max(vx1, bx1);
            vy1 = std::max(vy1, by1);
        }
        if (vx1 <= vx0 || vy1 <= vy0)
            return;

        // 1. half-resolution copy of what is under the glass (bucketed to 64 px to avoid reallocating during animations)
        const int needW  = std::max(1, (vx1 - vx0) / 2);
        const int needH  = std::max(1, (vy1 - vy0) / 2);
        const int bucketW = (needW + 63) & ~63;
        const int bucketH = (needH + 63) & ~63;
        const bool needRealloc = !L.backdrop || L.tw < needW || L.th < needH
                                 || ((int64_t)L.tw * L.th > (int64_t)bucketW * bucketH * 4);
        glActiveTexture(GL_TEXTURE0);
        if (needRealloc) {
            if (L.backdrop)
                glDeleteTextures(1, &L.backdrop);
            glGenTextures(1, &L.backdrop);
            glBindTexture(GL_TEXTURE_2D, L.backdrop);
            int levels = 1;
            for (int m = std::max(bucketW, bucketH); m > 1 && levels < 7; m >>= 1)
                levels++;
            glTexStorage2D(GL_TEXTURE_2D, levels, GL_RGBA8, bucketW, bucketH);
            glTexParameteri(GL_TEXTURE_2D, GL_TEXTURE_MIN_FILTER, GL_LINEAR_MIPMAP_LINEAR);
            glTexParameteri(GL_TEXTURE_2D, GL_TEXTURE_MAG_FILTER, GL_LINEAR);
            glTexParameteri(GL_TEXTURE_2D, GL_TEXTURE_WRAP_S, GL_CLAMP_TO_EDGE);
            glTexParameteri(GL_TEXTURE_2D, GL_TEXTURE_WRAP_T, GL_CLAMP_TO_EDGE);
            glTexParameteri(GL_TEXTURE_2D, GL_TEXTURE_MAX_LEVEL, levels - 1);
            L.tw = bucketW;
            L.th = bucketH;
        }
        GLint readFb = 0;
        glGetIntegerv(GL_READ_FRAMEBUFFER_BINDING, &readFb);
        // Hyprland binds only the DRAW framebuffer: read from it, or the copy comes from a stale buffer
        glBindFramebuffer(GL_READ_FRAMEBUFFER, drawFb);
        glBindFramebuffer(GL_DRAW_FRAMEBUFFER, g_gl.fbo);
        glFramebufferTexture2D(GL_DRAW_FRAMEBUFFER, GL_COLOR_ATTACHMENT0, GL_TEXTURE_2D, L.backdrop, 0);
        for (const auto& ra : L.rectAreas) {
            const CBox rfb = boxFb(mon, ls, ra);
            const int  bx0 = std::clamp((int)rfb.x, 0, fbW) & ~1;
            const int  bx1 = std::min(fbW, (std::clamp((int)(rfb.x + rfb.width), 0, fbW) + 1) & ~1);
            const int  by0 = std::clamp((int)rfb.y, 0, fbH) & ~1;
            const int  by1 = std::min(fbH, (std::clamp((int)(rfb.y + rfb.height), 0, fbH) + 1) & ~1);
            if (bx1 <= bx0 || by1 <= by0)
                continue;
            const int dx0 = (bx0 - vx0) / 2, dy0 = (by0 - vy0) / 2;
            const int dx1 = (bx1 - vx0) / 2, dy1 = (by1 - vy0) / 2;
            glBlitFramebuffer(bx0, by0, bx1, by1, std::clamp(dx0, 0, L.tw), std::clamp(dy0, 0, L.th), std::clamp(dx1, 0, L.tw), std::clamp(dy1, 0, L.th), GL_COLOR_BUFFER_BIT,
                              GL_LINEAR);
        }
        glFramebufferTexture2D(GL_DRAW_FRAMEBUFFER, GL_COLOR_ATTACHMENT0, GL_TEXTURE_2D, 0, 0);
        glBindFramebuffer(GL_DRAW_FRAMEBUFFER, drawFb);
        glBindFramebuffer(GL_READ_FRAMEBUFFER, readFb);
        glBindTexture(GL_TEXTURE_2D, L.backdrop);
        glGenerateMipmap(GL_TEXTURE_2D);

        // 2. the glass, one instance per rectangle
        glActiveTexture(GL_TEXTURE1);
        glBindTexture(external ? GL_TEXTURE_EXTERNAL_OES : GL_TEXTURE_2D, tex->m_texID);
        glUseProgram(prog);
        const auto& g = ls->m_geometry;
        const auto& U = g_gl.glassU[pi];
        glUniform1i(U.uSurf, 1);
        glUniform2f(U.uSurfPx, tex->m_size.x, tex->m_size.y);
        glUniform1f(U.uBufScale, g.width > 0 ? tex->m_size.x / g.width : 1.0);
        glUniform2f(U.uLayerFb, lb.x, lb.y);
        glUniform1f(U.uMonScale, s);
        glUniform2f(U.uFb, fb.x, fb.y);
        glUniform1f(U.uLayerHLogical, g.height);
        glUniform1i(U.uBack, 0);
        glUniform4f(U.uBand, (float)vx0, (float)vy0, L.tw * 2.0f, L.th * 2.0f);
        glUniform1f(U.uS, s);
        glUniform1f(U.uTexScale, 0.5f);
        glUniform4f(U.uValid, (float)vx0, (float)vy0, (float)vx1, (float)vy1);
        const auto& P = params();
        auto        set3 = [&](GLint loc, float a, float b, float c) {
            const float v[3] = {a, b, c};
            glUniform1fv(loc, 3, v);
        };
        set3(U.uTint, P.k[0].tint, P.k[1].tint, P.k[2].tint);
        set3(U.uTintDark, P.k[0].tintDark, P.k[1].tintDark, P.k[2].tintDark);
        set3(U.uBlur, P.k[0].blur, P.k[1].blur, P.k[2].blur);
        set3(U.uBezel, P.k[0].bezel, P.k[1].bezel, P.k[2].bezel);
        set3(U.uThick, P.k[0].thickness, P.k[1].thickness, P.k[2].thickness);
        set3(U.uDisperse, P.k[0].dispersion, P.k[1].dispersion, P.k[2].dispersion);
        set3(U.uMagnify, P.k[0].magnify, P.k[1].magnify, P.k[2].magnify);
        set3(U.uSat, P.k[0].saturation, P.k[1].saturation, P.k[2].saturation);
        set3(U.uLift, P.k[0].lift, P.k[1].lift, P.k[2].lift);
        set3(U.uRim, P.k[0].rim, P.k[1].rim, P.k[2].rim);
        glBindVertexArray(g_gl.vao);
        // every slot: the marker (decoded on the GPU) is newer than the CPU copy; unused slots collapse to nothing
        glDrawArraysInstanced(GL_TRIANGLE_STRIP, 0, 4, MAX_RECTS);
    }

    // one id per frame and monitor: only the newest element draws (a queued but unrendered one can never match)
    uint64_t                            g_nextId = 1;
    std::unordered_map<void*, uint64_t> g_lastId;

    bool propagateWindowDamage(PHLMONITOR mon, Render::CRenderContext& ctx);

    class CGlassElement : public IPassElement {
      public:
        CGlassElement(PHLMONITOR mon, uint64_t id) : m_mon(mon), m_id(id) {}

        std::vector<UP<IPassElement>> draw(Render::CRenderContext& ctx) override {
            auto mon = m_mon.lock();
            if (!mon || g_lastId[mon.get()] != m_id || !ensureGL())
                return {};
            auto layers = glassLayers(mon);
            if (layers.empty())
                return {};

            struct SLayerWork {
                PHLLS   ls;
                SLayer* L;
                bool    draw;
                bool    readback;
            };
            std::vector<SLayerWork> work;
            work.reserve(layers.size());
            bool anyDraw = false, anyReadback = false;
            for (auto& ls : layers) {
                auto& L = g_layers[ls.get()];
                L.lastSeen = g_stats.frames;
                trackLayerCommit(ls, L);
                const bool wantDraw = !L.rectAreas.empty()
                                      && (L.dirtyMarker || layerTouchesDamage(mon, ls, L, ctx.m_data.damage));
                const bool wantRead = L.dirtyMarker && !L.pending;
                anyDraw |= wantDraw;
                anyReadback |= wantRead;
                work.push_back({ls, &L, wantDraw, wantRead});
            }
            g_stats.frames++;
            if (!anyDraw && !anyReadback) {
                g_stats.skipped++;
                return {};
            }

            if (anyDraw) {
                GLint vp[4] = {0, 0, 0, 0};
                glGetIntegerv(GL_VIEWPORT, vp); // ctx.m_data.fbSize is not filled in here
                const Vector2D fb = {(double)vp[2], (double)vp[3]};
                if (fb.x > 0 && fb.y > 0) {
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

                    for (auto& w : work) {
                        if (!w.draw)
                            continue;
                        drawLayer(mon, w.ls, *w.L, fb, drawFb);
                        glBlendFuncSeparate(GL_ONE, GL_ONE_MINUS_SRC_ALPHA, GL_ONE, GL_ONE_MINUS_SRC_ALPHA);
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
                }
            }

            if (anyReadback) {
                for (auto& w : work) {
                    if (w.readback)
                        requestReadback(w.ls, *w.L);
                }
            }
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
            auto expandGlass = [&]() {
                bool added = false;
                for (auto& ls : glassLayers(mon)) {
                    auto it = g_layers.find(ls.get());
                    if (it == g_layers.end())
                        continue;
                    for (const auto& ra : it->second.rectAreas) {
                        const CBox a = boxFb(mon, ls, ra);
                        if (a.width <= 0 || ctx.m_data.damage.copy().intersect(a).empty())
                            continue;
                        CRegion missing{a};
                        missing.subtract(ctx.m_data.damage);
                        if (!missing.empty()) {
                            ctx.m_data.damage.add(a);
                            g_stats.damaged++;
                            added = true;
                        }
                    }
                }
                return added;
            };
            // Propagate damage between glass layers (e.g. Dock) and floating blur windows in both directions so
            // neither ever reads stale pixels from a previous frame when they overlap.
            for (int pass = 0; pass < 3; ++pass) {
                const bool g = expandGlass();
                const bool w = propagateWindowDamage(mon, ctx);
                if (!g && !w)
                    break;
            }
            return false;
        }

      private:
        PHLMONITORREF m_mon;
        uint64_t      m_id = 0;
    };

    // ── half-resolution mipmap backdrop blur for floating glass windows (RENDER_PRE_WINDOW) ───────────────────────
    struct SWinKey {
        void* mon = nullptr;
        void* win = nullptr;
        bool  operator==(const SWinKey&) const = default;
    };
    struct SWinKeyHash {
        size_t operator()(const SWinKey& k) const noexcept {
            return std::hash<void*>{}(k.mon) ^ (std::hash<void*>{}(k.win) * 0x9e3779b97f4a7c15ULL);
        }
    };
    struct SWinBlur {
        GLuint   backdrop = 0;
        int      tw = 0, th = 0;
        uint64_t lastSeen = 0;
    };
    std::unordered_map<SWinKey, SWinBlur, SWinKeyHash> g_winBlurs;
    std::unordered_map<void*, uint64_t>                g_winMonTick;
    struct SQueuedWindowBlur {
        PHLWINDOWREF window;
        CBox         box;  // animated window bounds in monitor framebuffer pixels
        CBox         band; // pixel-aligned backdrop copy and damage bounds
        float        alpha;
    };
    std::unordered_map<void*, std::vector<SQueuedWindowBlur>> g_winQueued;

    void freeWinBlur(SWinBlur& W) {
        if (W.backdrop)
            glDeleteTextures(1, &W.backdrop);
        W = {};
    }

    bool isMipmapBlurWindow(const PHLWINDOW& win) {
        if (!win || win->isHidden())
            return false;
        const auto& meta = win->metadata();
        return meta.appID() == "org.quickshell" && meta.initialTitle() == "About Omarchy Linux";
    }

    CBox windowBackdropBand(const CBox& box, const Vector2D& outputSize, double pad) {
        // Keep the copy size stable as the window moves across an output edge so the
        // half-resolution texture can be reused throughout the slide.
        const auto extent = [pad](double length, double limit) {
            return std::min(limit, 2.0 * std::ceil((length + 2.0 * pad + 2.0) / 2.0));
        };
        const double width  = extent(box.width, outputSize.x);
        const double height = extent(box.height, outputSize.y);
        const double x = std::clamp(2.0 * std::floor((box.x - pad) / 2.0), 0.0, outputSize.x - width);
        const double y = std::clamp(2.0 * std::floor((box.y - pad) / 2.0), 0.0, outputSize.y - height);
        return CBox{x, y, width, height};
    }

    bool expandWindowDamage(Render::CRenderContext& ctx, const CBox& band) {
        if (ctx.m_data.damage.copy().intersect(band).empty() || CRegion{band}.subtract(ctx.m_data.damage).empty())
            return false;
        ctx.m_data.damage.add(band);
        g_stats.winDamaged++;
        return true;
    }

    // Propagate damage across overlapping floating blur windows and glass layers so neither ever reads stale pixels.
    bool propagateWindowDamage(PHLMONITOR mon, Render::CRenderContext& ctx) {
        auto it = g_winQueued.find(mon.get());
        if (it == g_winQueued.end())
            return false;
        bool added = false;
        for (const auto& blur : it->second)
            added |= expandWindowDamage(ctx, blur.band);
        return added;
    }

    class CWindowBlurElement : public IPassElement {
      public:
        CWindowBlurElement(PHLMONITOR mon, const SQueuedWindowBlur& blur) : m_mon(mon), m_blur(blur) {}

        std::vector<UP<IPassElement>> draw(Render::CRenderContext& ctx) override {
            auto mon = m_mon.lock();
            auto win = m_blur.window.lock();
            const auto& wb = m_blur.box;
            // Skip the GPU work on frames whose damage misses the window.
            if (!mon || !win || ctx.m_data.damage.copy().intersect(wb.copy().round()).empty() || !ensureGL() || !g_gl.winProg)
                return {};
            const Vector2D fb = mon->m_transformedSize;
            const auto&  WP  = params().win;
            const double s   = mon->m_scale;
            const float  bPx = std::max(WP.blur * (float)s, 1.0f);
            const auto& band = m_blur.band;
            const int    bx0 = (int)band.x;
            const int    by0 = (int)band.y;
            const int    bx1 = bx0 + (int)band.width;
            const int    by1 = by0 + (int)band.height;
            const int    tw  = (int)band.width / 2;
            const int    th  = (int)band.height / 2;
            if (tw == 0 || th == 0)
                return {};

            GLint     prevProg, prevVao, prevActive, prevTex0, prevSrc, prevDst, prevSrcA, prevDstA, drawFb, readFb;
            GLboolean prevBlend = glIsEnabled(GL_BLEND), prevScissor = glIsEnabled(GL_SCISSOR_TEST);
            glGetIntegerv(GL_CURRENT_PROGRAM, &prevProg);
            glGetIntegerv(GL_VERTEX_ARRAY_BINDING, &prevVao);
            glGetIntegerv(GL_ACTIVE_TEXTURE, &prevActive);
            glActiveTexture(GL_TEXTURE0);
            glGetIntegerv(GL_TEXTURE_BINDING_2D, &prevTex0);
            glGetIntegerv(GL_BLEND_SRC_RGB, &prevSrc);
            glGetIntegerv(GL_BLEND_DST_RGB, &prevDst);
            glGetIntegerv(GL_BLEND_SRC_ALPHA, &prevSrcA);
            glGetIntegerv(GL_BLEND_DST_ALPHA, &prevDstA);
            glGetIntegerv(GL_DRAW_FRAMEBUFFER_BINDING, &drawFb);
            glGetIntegerv(GL_READ_FRAMEBUFFER_BINDING, &readFb);

            auto& W = g_winBlurs[SWinKey{mon.get(), win.get()}];
            W.lastSeen = g_stats.winFrames;
            if (!W.backdrop || W.tw != tw || W.th != th) {
                if (W.backdrop)
                    glDeleteTextures(1, &W.backdrop);
                glGenTextures(1, &W.backdrop);
                glBindTexture(GL_TEXTURE_2D, W.backdrop);
                int levels = 1;
                for (int m = std::max(tw, th); m > 1 && levels < 7; m >>= 1)
                    levels++;
                glTexStorage2D(GL_TEXTURE_2D, levels, GL_RGBA8, tw, th);
                glTexParameteri(GL_TEXTURE_2D, GL_TEXTURE_MIN_FILTER, GL_LINEAR_MIPMAP_LINEAR);
                glTexParameteri(GL_TEXTURE_2D, GL_TEXTURE_MAG_FILTER, GL_LINEAR);
                glTexParameteri(GL_TEXTURE_2D, GL_TEXTURE_WRAP_S, GL_CLAMP_TO_EDGE);
                glTexParameteri(GL_TEXTURE_2D, GL_TEXTURE_WRAP_T, GL_CLAMP_TO_EDGE);
                glTexParameteri(GL_TEXTURE_2D, GL_TEXTURE_MAX_LEVEL, levels - 1);
                W.tw = tw;
                W.th = th;
            }

            glDisable(GL_SCISSOR_TEST);
            glBindFramebuffer(GL_READ_FRAMEBUFFER, drawFb);
            glBindFramebuffer(GL_DRAW_FRAMEBUFFER, g_gl.fbo);
            glFramebufferTexture2D(GL_DRAW_FRAMEBUFFER, GL_COLOR_ATTACHMENT0, GL_TEXTURE_2D, W.backdrop, 0);
            glBlitFramebuffer(bx0, by0, bx1, by1, 0, 0, tw, th, GL_COLOR_BUFFER_BIT, GL_LINEAR);
            glBindFramebuffer(GL_DRAW_FRAMEBUFFER, drawFb);
            glBindFramebuffer(GL_READ_FRAMEBUFFER, readFb);

            glBindTexture(GL_TEXTURE_2D, W.backdrop);
            glGenerateMipmap(GL_TEXTURE_2D);

            glEnable(GL_BLEND);
            glBlendFuncSeparate(GL_ONE, GL_ONE_MINUS_SRC_ALPHA, GL_ONE, GL_ONE_MINUS_SRC_ALPHA);
            glUseProgram(g_gl.winProg);
            auto&       pres  = win->presentation();
            const float rPx   = pres.rounding() * (float)s;
            const float rPow  = pres.roundingPower();
            glUniform1i(g_gl.winU.uBack, 0);
            glUniform4f(g_gl.winU.uBand, (float)bx0, (float)by0, (float)(bx1 - bx0), (float)(by1 - by0));
            glUniform4f(g_gl.winU.uRect, (float)wb.x, (float)wb.y, (float)wb.width, (float)wb.height);
            glUniform2f(g_gl.winU.uFb, (float)fb.x, (float)fb.y);
            glUniform1f(g_gl.winU.uRadius, rPx);
            glUniform1f(g_gl.winU.uRoundPow, rPow);
            glUniform1f(g_gl.winU.uBlurPx, bPx);
            glUniform1f(g_gl.winU.uAlpha, m_blur.alpha);
            glUniform1f(g_gl.winU.uSat, WP.saturation);
            glUniform1f(g_gl.winU.uContrast, WP.contrast);
            glUniform1f(g_gl.winU.uBrightness, WP.brightness);
            glBindVertexArray(g_gl.vao);
            glDrawArrays(GL_TRIANGLE_STRIP, 0, 4);

            glBindVertexArray(prevVao);
            glUseProgram(prevProg);
            glActiveTexture(GL_TEXTURE0);
            glBindTexture(GL_TEXTURE_2D, prevTex0);
            glActiveTexture(prevActive);
            glBlendFuncSeparate(prevSrc, prevDst, prevSrcA, prevDstA);
            if (!prevBlend)
                glDisable(GL_BLEND);
            if (prevScissor)
                glEnable(GL_SCISSOR_TEST);
            g_stats.winFrames++;
            return {};
        }

        bool                needsLiveBlur(Render::CRenderContext&) override { return false; }
        bool                needsPrecomputeBlur(Render::CRenderContext&) override { return false; }
        const char*         passName() override { return "CSilkyWindowBlurElement"; }
        ePassElementType    type() override { return EK_CUSTOM; }
        bool                undiscardable(Render::CRenderContext&) override { return true; }
        bool                disableSimplification(Render::CRenderContext&) override { return true; }
        std::optional<CBox> boundingBox(Render::CRenderContext&) override {
            auto mon = m_mon.lock();
            if (!mon)
                return std::nullopt;
            return m_blur.band.copy().scale(1.0 / mon->m_scale);
        }
        CRegion opaqueRegion(Render::CRenderContext&) override { return {}; }
        bool    requiresFullDamage(Render::CRenderContext& ctx) override {
            expandWindowDamage(ctx, m_blur.band);
            return false;
        }

      private:
        PHLMONITORREF     m_mon;
        SQueuedWindowBlur m_blur;
    };

    void onStage(const Event::SRenderStageEvent& e) {
        if (!e.context || !e.monitor)
            return;
        auto& ctx = e.context->get();
        if (ctx.m_renderingCapture || ctx.m_renderingSnapshot)
            return;
        if (e.stage == RENDER_BEGIN) {
            g_winQueued[e.monitor.get()].clear();
            g_winMonTick[e.monitor.get()]++;
            return;
        }
        if (e.stage == RENDER_PRE_WINDOW) {
            auto win = ctx.m_data.currentWindow.lock();
            if (!isMipmapBlurWindow(win))
                return;
            auto& q = g_winQueued[e.monitor.get()];
            for (const auto& blur : q)
                if (blur.window.lock() == win)
                    return;

            // Match the compositor's window presentation, including interactive swipe
            // offsets, floating offsets, workspace fades and pinned-window behavior.
            const auto presentation = win->presentation().renderPresentation();
            const float alpha = presentation.fadeAlpha * presentation.alpha;
            const double scale = e.monitor->m_scale;
            const CBox box = win->getWindowMainSurfaceBox()
                                 .translate(presentation.workspaceOffset + presentation.floatingOffset - e.monitor->m_position)
                                 .scale(scale);
            const auto& outputSize = e.monitor->m_transformedSize;
            if (alpha <= 0.F || box.width <= 1.0 || box.height <= 1.0 || box.intersection(CBox{{}, outputSize}).empty())
                return;

            const double pad = std::ceil(std::max(params().win.blur, 1.0f) * scale) + 4.0;
            q.push_back({win, box, windowBackdropBand(box, outputSize, pad), alpha});
            for (auto it = g_winBlurs.begin(); it != g_winBlurs.end();) {
                if (g_stats.winFrames > it->second.lastSeen + 600) {
                    freeWinBlur(it->second);
                    it = g_winBlurs.erase(it);
                } else
                    ++it;
            }
            Render::IHyprRenderer::addPassElement(ctx, makeUnique<CWindowBlurElement>(e.monitor, q.back()));
            return;
        }
        if (e.stage != RENDER_POST_WINDOWS)
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
    g_statsCmd = HyprlandAPI::registerHyprCtlCommand(PHANDLE, IPC::Socket1::SCommand{"silkyglass", IPC::Socket1::COMMAND_MATCH_EXACT, [](const IPC::Socket1::SRequest&) -> IPC::Socket1::SResponse {
        std::string out = std::format("frames={} skipped={} readbacks={} damaged={} winFrames={} winDamaged={} layers={}\n",
                                      g_stats.frames, g_stats.skipped, g_stats.readbacks, g_stats.damaged,
                                      g_stats.winFrames, g_stats.winDamaged, g_layers.size());
        for (const auto& [k, L] : g_layers) {
            out += std::format("  layer={} rects={} tex={}x{} pending={} dirty={} lastSeen={}\n",
                               k, L.rects.size(), L.tw, L.th, (int)L.pending, (int)L.dirtyMarker, L.lastSeen);
        }
        return IPC::Socket1::SResponse{out};
    }});
    for (auto& m : State::monitorState()->monitors())
        g_pHyprRenderer->damageMonitor(m);
    return {"silky-dock-glass", "Zero-latency Liquid Glass for MacShell Dock, menus, Control Center, overlays and half-res mipmap window blur", "sqlsec", "0.5.6"};
}

APICALL EXPORT void PLUGIN_EXIT() {
    if (g_statsCmd) {
        HyprlandAPI::unregisterHyprCtlCommand(PHANDLE, g_statsCmd);
        g_statsCmd.reset();
    }
    g_listeners.clear();
    Log::logger->log(Log::INFO, std::format("[silky-dock-glass] frames: {} (skipped: {}, readbacks: {}), glass-area damage additions: {}, window blur frames: {}, window damage: {}",
                                            g_stats.frames, g_stats.skipped, g_stats.readbacks, g_stats.damaged, g_stats.winFrames, g_stats.winDamaged));
    if (g_gl.ready) {
        for (auto& [k, L] : g_layers)
            freeLayer(L);
        for (auto& [k, W] : g_winBlurs)
            freeWinBlur(W);
        for (auto p : g_gl.prog)
            if (p)
                glDeleteProgram(p);
        if (g_gl.winProg)
            glDeleteProgram(g_gl.winProg);
        glDeleteVertexArrays(1, &g_gl.vao);
        glDeleteBuffers(1, &g_gl.vbo);
        glDeleteFramebuffers(1, &g_gl.fbo);
        glDeleteFramebuffers(1, &g_gl.readFbo);
    }
    g_layers.clear();
    g_winBlurs.clear();
    g_winQueued.clear();
    g_gl = {};
    for (auto& m : State::monitorState()->monitors())
        g_pHyprRenderer->damageMonitor(m);
}
