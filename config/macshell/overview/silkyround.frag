// SilkyOverview: a window picture with rounded, anti-aliased corners, drawn straight into the scene (no offscreen pass).
// Compiled to silkyround.frag.qsb by scripts/install-macshell-overview.py (qsb --qt6).
#version 440
layout(location = 0) in vec2 qt_TexCoord0;
layout(location = 0) out vec4 fragColor;
layout(std140, binding = 0) uniform buf {
    mat4 qt_Matrix;
    float qt_Opacity;
    vec2 size;     // drawn size, logical px
    float radius;  // corner radius, logical px
};
layout(binding = 1) uniform sampler2D source;

void main() {
    vec2 p = qt_TexCoord0 * size;
    vec2 q = abs(p - size * 0.5) - (size * 0.5 - vec2(radius));
    float d = length(max(q, 0.0)) + min(max(q.x, q.y), 0.0) - radius;
    float a = clamp(0.5 - d, 0.0, 1.0);
    fragColor = texture(source, qt_TexCoord0) * (a * qt_Opacity);
}
