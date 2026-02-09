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

    // Sharp threshold (step function) — matches inox2d's "discard when alpha <= threshold"
    float mask = step(threshold + 0.0001, alpha);

    fragColor = vec4(1.0, 1.0, 1.0, mask);
}
