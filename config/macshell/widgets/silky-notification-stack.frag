// Bake with /usr/lib/qt6/bin/qsb --qt6 --qsbversion 64.
#version 440
layout(location = 0) in vec2 qt_TexCoord0;
layout(location = 0) out vec4 fragColor;
layout(std140, binding = 0) uniform buf {
    mat4 qt_Matrix;
    float qt_Opacity;
    float w;
    float h;
    float topOverlap;
    float stackH;
    float cardR;
    float layers;
    float dark;
    float hovered;
};

float sdRoundRect(vec2 p, vec2 center, vec2 halfSize, float r) {
    vec2 q = abs(p - center) - halfSize + r;
    return length(max(q, 0.0)) + min(max(q.x, q.y), 0.0) - r;
}

void main() {
    vec2 p = qt_TexCoord0 * vec2(w, h);
    float topY = -64.0;
    float halfW = w * 0.5;

    // Layer 0: main card silhouette (strictly subtracted so nothing bleeds through translucent glass)
    float bot0 = topOverlap;
    float d0 = sdRoundRect(p, vec2(halfW, (topY + bot0) * 0.5), vec2(halfW, (bot0 - topY) * 0.5), cardR);
    float outside0 = smoothstep(-0.35, 0.55, d0);

    // Layer 1: first perspective-recessed card lip (5.5 px peek, 10.5 px horizontal inset)
    float off1 = clamp(stackH, 0.0, 5.5) + hovered * 0.75 * smoothstep(0.0, 2.0, stackH);
    float inset1 = 10.5;
    float r1 = max(8.0, cardR - 3.0);
    float hw1 = max(1.0, halfW - inset1);
    float bot1 = topOverlap + off1;
    float d1 = sdRoundRect(p, vec2(halfW, (topY + bot1) * 0.5), vec2(hw1, (bot1 - topY) * 0.5), r1);
    float cov1 = (1.0 - smoothstep(-0.48, 0.48, d1)) * outside0 * smoothstep(0.0, 1.3, off1);
    float outside1 = smoothstep(-0.35, 0.55, d1);

    // Layer 2: second perspective-recessed card lip (+5.0 px tighter step -> 10.5 px total, 20.0 px inset)
    float off2 = max(0.0, stackH) + hovered * 1.4 * smoothstep(5.5, 7.5, stackH);
    float inset2 = 20.0;
    float r2 = max(6.0, cardR - 5.5);
    float hw2 = max(1.0, halfW - inset2);
    float bot2 = topOverlap + off2;
    float d2 = sdRoundRect(p, vec2(halfW, (topY + bot2) * 0.5), vec2(hw2, (bot2 - topY) * 0.5), r2);
    float cov2 = step(1.5, layers) * (1.0 - smoothstep(-0.48, 0.48, d2)) * outside0 * outside1 * smoothstep(5.5, 7.0, stackH);

    // Keep the rounded bottom arc continuous, tapering cleanly where the side curves into the upper card
    float qx1 = max(abs(p.x - halfW) - (hw1 - r1), 0.0);
    float sideFade1 = 1.0 - smoothstep(0.58, 0.96, qx1 / max(r1, 1.0));
    float qx2 = max(abs(p.x - halfW) - (hw2 - r2), 0.0);
    float sideFade2 = 1.0 - smoothstep(0.58, 0.96, qx2 / max(r2, 1.0));

    // Delicate contact ambient occlusion right along the upper seam
    float ao0 = exp(-max(d0, 0.0) * 1.65) * (dark > 0.5 ? 0.36 : 0.14);
    float ao1 = exp(-max(d1, 0.0) * 1.75) * (dark > 0.5 ? 0.30 : 0.11);

    // Translucent glass body matched to the main card's effective opacity so brightness tracks both dark and white backdrops
    float bevel1 = exp(-max(-d1 - 0.5, 0.0) * 0.70) * sideFade1 * smoothstep(0.5, 2.2, d0);
    float bevel2 = exp(-max(-d2 - 0.5, 0.0) * 0.75) * sideFade2 * smoothstep(0.5, 2.0, d1);

    vec3 base1 = dark > 0.5
        ? mix(vec3(0.072, 0.076, 0.094), vec3(0.138, 0.144, 0.170), bevel1)
        : mix(vec3(0.935, 0.942, 0.965), vec3(0.992, 0.994, 1.000), bevel1);
    vec3 base2 = dark > 0.5
        ? mix(vec3(0.060, 0.064, 0.080), vec3(0.112, 0.118, 0.140), bevel2)
        : mix(vec3(0.905, 0.914, 0.942), vec3(0.968, 0.972, 0.990), bevel2);

    float alpha1 = dark > 0.5 ? 0.62 : 0.74;
    float alpha2 = dark > 0.5 ? 0.48 : 0.58;

    base1 += vec3(hovered * (dark > 0.5 ? 0.026 : 0.018));
    base2 += vec3(hovered * (dark > 0.5 ? 0.018 : 0.012));

    vec3 col1 = base1 * (1.0 - ao0);
    vec3 col2 = base2 * (1.0 - ao1);

    // Subtle outer keyline (defines silhouette on pure-white backdrops) + inner 1px specular rim (shines on dark backdrops)
    float innerRim1 = smoothstep(-1.35, -0.45, d1) * (1.0 - smoothstep(-0.35, 0.22, d1)) * sideFade1 * smoothstep(0.8, 2.4, d0);
    float innerRim2 = smoothstep(-1.35, -0.45, d2) * (1.0 - smoothstep(-0.35, 0.22, d2)) * sideFade2 * smoothstep(0.8, 2.2, d1) * smoothstep(1.6, 4.0, d0);
    float outerKey1 = smoothstep(-0.45, 0.05, d1) * (1.0 - smoothstep(0.05, 0.65, d1)) * outside0 * smoothstep(0.4, 1.6, d0);
    float outerKey2 = step(1.5, layers) * smoothstep(-0.45, 0.05, d2) * (1.0 - smoothstep(0.05, 0.65, d2)) * outside0 * outside1 * smoothstep(0.4, 1.6, d1);

    vec3 rimCol = dark > 0.5 ? vec3(0.95, 0.97, 1.0) : vec3(1.0);
    float rimStr1 = (dark > 0.5 ? 0.30 : 0.72) + hovered * 0.07;
    float rimStr2 = (dark > 0.5 ? 0.22 : 0.54) + hovered * 0.05;

    col1 = mix(col1, rimCol, innerRim1 * rimStr1);
    alpha1 = max(alpha1, innerRim1 * (dark > 0.5 ? 0.46 : 0.78));
    col1 = mix(col1, vec3(0.0), outerKey1 * (dark > 0.5 ? 0.24 : 0.14));
    alpha1 = max(alpha1, outerKey1 * (dark > 0.5 ? 0.28 : 0.14));

    col2 = mix(col2, rimCol, innerRim2 * rimStr2);
    alpha2 = max(alpha2, innerRim2 * (dark > 0.5 ? 0.34 : 0.60));
    col2 = mix(col2, vec3(0.0), outerKey2 * (dark > 0.5 ? 0.18 : 0.10));
    alpha2 = max(alpha2, outerKey2 * (dark > 0.5 ? 0.22 : 0.10));

    // Composite layer 1 and layer 2 (mutually exclusive regions)
    float a = cov1 * alpha1 + cov2 * alpha2;
    vec3 rgb = (cov1 * alpha1 * col1 + cov2 * alpha2 * col2) / max(a, 0.0001);

    float fade = smoothstep(0.0, 2.0, stackH) * qt_Opacity;
    float outA = clamp(a * fade, 0.0, 1.0);
    fragColor = vec4(rgb * outA, outA);
}
