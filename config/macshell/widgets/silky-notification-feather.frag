// Bake with qsb --qt6 --qsbversion 64.
#version 440
layout(location = 0) in vec2 qt_TexCoord0;
layout(location = 0) out vec4 fragColor;
layout(std140, binding = 0) uniform buf {
    mat4 qt_Matrix;
    float qt_Opacity;
    float progress;
};
layout(binding = 1) uniform sampler2D source;

void main() {
    vec2 uv = qt_TexCoord0;
    float wisps = 0.040 * sin(uv.x * 27.0 + uv.y * 7.0)
                + 0.018 * sin(uv.x * 73.0 - uv.y * 11.0);
    float position = dot(uv, vec2(0.24, 0.76)) + wisps;
    float edge = 1.06 - 1.45 * progress;
    float feather = 1.0 - smoothstep(edge, edge + 0.30, position);
    fragColor = texture(source, uv) * (feather * qt_Opacity);
}
