// NOTE: #version directive is prepended by C code at load time
// Display pass: reads linear HDR accumulation buffer, applies exposure + tone mapping + gamma

#ifdef GL_ES
precision highp float;
#endif

in vec2 fragTexCoord;
out vec4 finalColor;

uniform sampler2D texture0;  // accumulated linear HDR buffer
uniform int toneMapMode;     // 0 = none, 1 = Reinhard, 2 = ACES, 3 = AgX
uniform float exposure;      // EV adjustment (default 0.0)

// Reinhard: simple global operator
vec3 tonemapReinhard(vec3 c) {
    return c / (1.0 + c);
}

// ACES filmic (Narkowicz fit)
vec3 tonemapACES(vec3 c) {
    return clamp((c * (2.51 * c + 0.03)) / (c * (2.43 * c + 0.59) + 0.14), 0.0, 1.0);
}

// AgX tone mapping (Troy Sobotka — Blender 3.6+ default)
// Minimal hue shifts, perceptually uniform highlight rolloff
vec3 agxDefaultContrastApprox(vec3 x) {
    vec3 x2 = x * x;
    vec3 x4 = x2 * x2;
    return + 15.5     * x4 * x2
           - 40.14    * x4 * x
           + 31.96    * x4
           - 6.868    * x2 * x
           + 0.4298   * x2
           + 0.1191   * x
           - 0.00232;
}

vec3 tonemapAgX(vec3 color) {
    // AgX input transform: linear → log2 domain
    const float minEv = -12.47393;
    const float maxEv = 4.026069;

    // Approximate sRGB → AgX log encoding
    // Using a simplified 3x3 matrix (inset) for the AgX color space
    const mat3 agxInset = mat3(
        0.842479062253094,  0.0423282422610123, 0.0423756549057051,
        0.0784335999999992, 0.878468636469772,  0.0784336,
        0.0792237451477643, 0.0791661274605434,  0.879142973793104
    );

    color = agxInset * color;
    color = max(color, vec3(1e-10));

    // Log2 encoding + range compression
    color = log2(color);
    color = (color - minEv) / (maxEv - minEv);
    color = clamp(color, 0.0, 1.0);

    // Apply sigmoid contrast curve (polynomial approximation)
    color = agxDefaultContrastApprox(color);

    // AgX output transform (outset)
    const mat3 agxOutset = mat3(
         1.19687900512017,  -0.0528968517574562, -0.0529716355144438,
        -0.0980208811401368,  1.15190312990417,   -0.0980434066391996,
        -0.0990297440797205, -0.0989611768448433,  1.15107367264116
    );

    color = agxOutset * color;
    color = clamp(color, 0.0, 1.0);

    return color;
}

// Proper sRGB gamma (not just pow 1/2.2)
vec3 linearToSRGB(vec3 c) {
    vec3 lo = c * 12.92;
    vec3 hi = 1.055 * pow(max(c, 0.0), vec3(1.0 / 2.4)) - 0.055;
    return mix(lo, hi, step(vec3(0.0031308), c));
}

void main() {
    vec3 color = texture(texture0, fragTexCoord).rgb;
    color = max(color, 0.0);

    // Exposure adjustment (EV)
    color *= pow(2.0, exposure);

    // Tone map
    if (toneMapMode == 1) {
        color = tonemapReinhard(color);
    } else if (toneMapMode == 2) {
        color = tonemapACES(color);
    } else if (toneMapMode == 3) {
        color = tonemapAgX(color);
    } else {
        color = clamp(color, 0.0, 1.0);
    }

    // sRGB gamma
    color = linearToSRGB(color);

    finalColor = vec4(color, 1.0);
}
