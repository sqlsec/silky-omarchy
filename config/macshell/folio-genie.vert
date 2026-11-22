#version 440

layout(location = 0) in vec4 qt_Vertex;
layout(location = 1) in vec2 qt_MultiTexCoord0;
layout(location = 0) out vec2 qt_TexCoord0;

layout(std140, binding = 0) uniform buf {
    mat4 qt_Matrix;
    float qt_Opacity;
    float progress;
    vec4 win;
    vec4 target;
};

void main()
{
    vec2 uv = qt_MultiTexCoord0;
    float p = clamp(progress, 0.0, 1.0);
    float bend = p * (1.0 - p);
    float neck = uv.y * uv.y * (3.0 - 2.0 * uv.y);

    // Bias each row toward an earlier or later arrival without a dead zone.
    // The bias stays between -1 and 1, so each row moves monotonically.
    float travel = p + (0.85 * uv.y - 0.35) * bend;
    float squeeze = p + (1.75 * neck - 0.82) * bend;

    float x = mix(win.x + uv.x * win.z, target.x + uv.x * target.z, squeeze);
    float y = mix(win.y + uv.y * win.w, target.y + uv.y * target.w, travel);
    qt_TexCoord0 = uv;
    gl_Position = qt_Matrix * vec4(x, y, 0.0, 1.0);
}
