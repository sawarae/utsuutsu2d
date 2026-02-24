#include <flutter/runtime_effect.glsl>

uniform float threshold;   // float index 0
uniform float invert;      // float index 1 (0.0 = mask, 1.0 = dodge)
uniform vec2 iSize;        // float index 2, 3

uniform sampler2D tex;     // sampler index 0

out vec4 fragColor;

void main() {
    vec2 uv = FlutterFragCoord().xy / iSize;
    vec4 color = texture(tex, uv);

    float alpha = color.a;
    alpha = mix(alpha, 1.0 - alpha, invert);  // dodge mode

    // Keep soft mask edges and only suppress values below threshold.
    // This matches the CPU/color-filter path:
    //   out = clamp((alpha - threshold) / (1 - threshold), 0, 1)
    float t = clamp(threshold, 0.0, 0.9999);
    float mask = clamp((alpha - t) / (1.0 - t), 0.0, 1.0);

    fragColor = vec4(1.0, 1.0, 1.0, mask);
}
