// Display pass: reads linear HDR accumulation buffer,
// applies exposure + tone mapping + sRGB gamma.
// Shared by lessons 9 and 10.

#ifdef GL_ES
precision highp float;
#endif

in vec2 fragTexCoord;
out vec4 finalColor;

uniform sampler2D texture0;  // accumulated linear HDR buffer
uniform int   toneMapMode;   // 0=clamp, 1=Reinhard, 2=ACES, 3=AgX
uniform float exposure;      // EV adjustment (default 0.0)

vec3 tonemapReinhard(vec3 c) { return c / (1.0 + c); }

vec3 tonemapACES(vec3 c) {
    return clamp((c*(2.51*c+0.03))/(c*(2.43*c+0.59)+0.14), 0.0, 1.0);
}

vec3 agxContrastApprox(vec3 x) {
    vec3 x2=x*x, x4=x2*x2;
    return 15.5*x4*x2 - 40.14*x4*x + 31.96*x4
         - 6.868*x2*x + 0.4298*x2 + 0.1191*x - 0.00232;
}

vec3 tonemapAgX(vec3 color) {
    const float minEv=-12.47393, maxEv=4.026069;
    const mat3 agxIn = mat3(
        0.842479062253094, 0.0423282422610123, 0.0423756549057051,
        0.0784335999999992, 0.878468636469772, 0.0784336,
        0.0792237451477643, 0.0791661274605434, 0.879142973793104);
    color = max(agxIn*color, vec3(1e-10));
    color = clamp((log2(color)-minEv)/(maxEv-minEv), 0.0, 1.0);
    color = agxContrastApprox(color);
    const mat3 agxOut = mat3(
         1.19687900512017, -0.0528968517574562, -0.0529716355144438,
        -0.0980208811401368, 1.15190312990417, -0.0980434066391996,
        -0.0990297440797205, -0.0989611768448433, 1.15107367264116);
    return clamp(agxOut*color, 0.0, 1.0);
}

vec3 linearToSRGB(vec3 c) {
    vec3 lo = c * 12.92;
    vec3 hi = 1.055 * pow(max(c,0.0), vec3(1.0/2.4)) - 0.055;
    return mix(lo, hi, step(vec3(0.0031308), c));
}

void main() {
    vec3 color = max(texture(texture0, fragTexCoord).rgb, 0.0);
    color *= pow(2.0, exposure);

    if      (toneMapMode == 1) color = tonemapReinhard(color);
    else if (toneMapMode == 2) color = tonemapACES(color);
    else if (toneMapMode == 3) color = tonemapAgX(color);
    else                       color = clamp(color, 0.0, 1.0);

    finalColor = vec4(linearToSRGB(color), 1.0);
}
