// ============================================================
// Lesson 10: Tone Mapping & Color
// ============================================================
//
// The renderer outputs LINEAR HDR values — numbers from 0 to
// infinity. Your monitor can only display 0 to 1 (SDR).
//
// TONE MAPPING compresses the infinite range into [0,1]
// while trying to preserve contrast and visual intent.
//
// Without tone mapping: bright areas are clamped to white,
// destroying detail and making everything look washed out.
//
// Three popular approaches, from simple to sophisticated:
//
// REINHARD (2002):
//   color = color / (1 + color)
//   Simple, preserves dark tones well, but bright areas can
//   look dull. The OG tone mapper.
//
// ACES (Academy Color Encoding System):
//   A film-industry standard that adds contrast and slight
//   color shifts for a cinematic look. Designed to emulate
//   how film stock responds to light.
//
// AgX (Troy Sobotka, used in Blender 3.6+):
//   Modern approach: perceptually uniform, minimal hue shifts,
//   graceful highlight rolloff. Currently the gold standard
//   for real-time rendering.
//
// After tone mapping, we apply GAMMA CORRECTION:
//   Monitors have a non-linear response curve (they darken
//   everything). sRGB gamma compensates by brightening.
//
// Controls:
//   1 — no tone mapping (raw clamp)
//   2 — Reinhard
//   3 — ACES
//   4 — AgX
//   +/- — adjust exposure (EV stops)

#ifdef GL_ES
precision highp float;
#endif

#define EPSILON 0.001
#define PI 3.14159265359

in vec2 fragTexCoord;
out vec4 finalColor;

uniform sampler2D texture0;
uniform sampler2D accumTexture;

uniform vec3  cameraPosition;
uniform mat4  invViewProj;
uniform vec2  resolution;
uniform int   frameCount;
uniform int   toneMapMode;  // 0=none, 1=reinhard, 2=aces, 3=agx
uniform float exposure;     // EV adjustment

// ============================================================
// RNG + scene (reuse from lesson 9)
// ============================================================
uint rngState;
uint pcgHash(uint v) {
    uint state = v * 747796405u + 2891336453u;
    uint word = ((state >> ((state >> 28u) + 4u)) ^ state) * 277803737u;
    return (word >> 22u) ^ word;
}
float rnd() { rngState = pcgHash(rngState); return float(rngState)/4294967295.0; }

vec3 cosineHemisphere(vec3 N) {
    float u1 = rnd(), u2 = rnd();
    float r = sqrt(u2), theta = 2.0*PI*u1;
    vec3 up = abs(N.y)<0.999 ? vec3(0,1,0) : vec3(1,0,0);
    vec3 T = normalize(cross(up,N));
    vec3 B = cross(N,T);
    return normalize(T*r*cos(theta) + B*r*sin(theta) + N*sqrt(1.0-u2));
}

struct Ray { vec3 origin, direction; };

bool iSphere(Ray r, vec3 c, float rad, float tMax, out float t, out vec3 n) {
    vec3 oc = r.origin-c;
    float b = dot(r.direction,oc), cc = dot(oc,oc)-rad*rad;
    float disc = b*b-cc; if (disc<0.0) return false;
    float sq = sqrt(disc);
    t = -b-sq; if (t<EPSILON||t>tMax) { t=-b+sq; if (t<EPSILON||t>tMax) return false; }
    n = normalize(oc+t*r.direction);
    return true;
}

bool iQuad(Ray r, vec3 Q, vec3 u, vec3 v, float tMax, out float t, out vec3 n) {
    vec3 nn = cross(u,v); float nl = length(nn); if (nl<1e-8) return false;
    vec3 un = nn/nl;
    float d = dot(un, r.direction); if (abs(d)<1e-8) return false;
    t = dot(Q-r.origin, un)/d; if (t<EPSILON||t>tMax) return false;
    vec3 p = r.origin+t*r.direction-Q;
    vec3 w = nn/dot(nn,nn);
    float a = dot(cross(p,v),w), b2 = dot(cross(u,p),w);
    if (a<0.0||a>1.0||b2<0.0||b2>1.0) return false;
    n = d<0.0 ? un : -un;
    return true;
}

// Scene: high dynamic range setup (bright + dark areas)
struct HitResult { float t; vec3 normal, color; bool emissive; vec3 emission; };

void findHit(Ray r, out HitResult h) {
    h.t = 1e38; h.emissive = false;
    float t; vec3 n;

    // Ground
    if (iSphere(r, vec3(0,-100.5,-2), 100.0, h.t, t, n))
        { h.t=t; h.normal=n; h.color=vec3(0.5,0.5,0.47); }
    // White sphere
    if (iSphere(r, vec3(-1.0,0.5,-3.0), 0.8, h.t, t, n))
        { h.t=t; h.normal=n; h.color=vec3(0.9,0.9,0.88); }
    // Blue sphere
    if (iSphere(r, vec3(0.8,0.4,-2.5), 0.6, h.t, t, n))
        { h.t=t; h.normal=n; h.color=vec3(0.2,0.35,0.8); }
    // Red sphere
    if (iSphere(r, vec3(-0.2,0.25,-1.5), 0.4, h.t, t, n))
        { h.t=t; h.normal=n; h.color=vec3(0.85,0.15,0.1); }
    // VERY bright emissive — this is what stresses the tone mapper
    if (iSphere(r, vec3(2.0,1.5,-4.0), 0.4, h.t, t, n))
        { h.t=t; h.normal=n; h.color=vec3(1); h.emissive=true; h.emission=vec3(1,0.85,0.6)*25.0; }
    // Second emissive (cool)
    if (iSphere(r, vec3(-2.0,1.0,-2.5), 0.25, h.t, t, n))
        { h.t=t; h.normal=n; h.color=vec3(1); h.emissive=true; h.emission=vec3(0.3,0.5,1.0)*20.0; }
}

vec3 skyColor(vec3 dir) {
    float t = 0.5*(dir.y+1.0);
    vec3 sky = mix(vec3(0.8,0.7,0.6), vec3(0.25,0.45,0.8), t);
    vec3 sunDir = normalize(vec3(0.5,0.15,0.8));
    sky += vec3(1,0.9,0.7) * pow(max(dot(dir,sunDir),0.0), 256.0) * 8.0;
    sky += vec3(1,0.85,0.6) * pow(max(dot(dir,sunDir),0.0), 8.0) * 0.5;
    return sky;
}

vec3 pathTrace(Ray ray) {
    vec3 color = vec3(0.0), throughput = vec3(1.0);
    for (int d = 0; d < 3; d++) {
        HitResult hit; findHit(ray, hit);
        if (hit.t > 1e37) { color += throughput * skyColor(ray.direction); break; }
        if (hit.emissive) { color += throughput * hit.emission; break; }
        vec3 hp = ray.origin + ray.direction * hit.t;
        ray = Ray(hp + hit.normal*EPSILON, cosineHemisphere(hit.normal));
        throughput *= hit.color;
    }
    return color;
}

// ============================================================
// Tone mapping operators
// ============================================================

// Reinhard: global operator, simple and safe
vec3 tonemapReinhard(vec3 c) {
    return c / (1.0 + c);
}

// ACES: filmic curve (Narkowicz approximation)
// Adds contrast + subtle warm color shift
vec3 tonemapACES(vec3 c) {
    return clamp((c*(2.51*c + 0.03)) / (c*(2.43*c + 0.59) + 0.14), 0.0, 1.0);
}

// AgX: perceptually uniform, modern gold standard
vec3 agxContrastApprox(vec3 x) {
    vec3 x2 = x*x, x4 = x2*x2;
    return 15.5*x4*x2 - 40.14*x4*x + 31.96*x4
         - 6.868*x2*x + 0.4298*x2 + 0.1191*x - 0.00232;
}

vec3 tonemapAgX(vec3 color) {
    const float minEv = -12.47393, maxEv = 4.026069;
    const mat3 agxIn = mat3(
        0.842479062253094, 0.0423282422610123, 0.0423756549057051,
        0.0784335999999992, 0.878468636469772, 0.0784336,
        0.0792237451477643, 0.0791661274605434, 0.879142973793104
    );
    color = agxIn * color;
    color = max(color, vec3(1e-10));
    color = log2(color);
    color = (color - minEv) / (maxEv - minEv);
    color = clamp(color, 0.0, 1.0);
    color = agxContrastApprox(color);
    const mat3 agxOut = mat3(
         1.19687900512017, -0.0528968517574562, -0.0529716355144438,
        -0.0980208811401368, 1.15190312990417, -0.0980434066391996,
        -0.0990297440797205, -0.0989611768448433, 1.15107367264116
    );
    color = agxOut * color;
    return clamp(color, 0.0, 1.0);
}

// Proper sRGB gamma (not just pow 1/2.2)
vec3 linearToSRGB(vec3 c) {
    vec3 lo = c * 12.92;
    vec3 hi = 1.055 * pow(max(c, 0.0), vec3(1.0/2.4)) - 0.055;
    return mix(lo, hi, step(vec3(0.0031308), c));
}

// ============================================================
// Main — accumulation + tone mapping
// ============================================================
void main() {
    uvec2 px = uvec2(gl_FragCoord.xy);
    rngState = px.x*1973u + px.y*9277u + uint(frameCount)*26699u;
    rnd();

    vec2 pixelSize = 2.0 / resolution;
    vec2 jitter = (vec2(rnd(), rnd()) - 0.5) * pixelSize;
    vec2 ndc = fragTexCoord * 2.0 - 1.0 + jitter;
    vec4 wp4 = invViewProj * vec4(ndc, -1.0, 1.0);
    vec3 wp = wp4.xyz / wp4.w;
    Ray ray = Ray(cameraPosition, normalize(wp - cameraPosition));

    vec3 newSample = pathTrace(ray);

    // Temporal accumulation (LINEAR HDR — no tone map yet!)
    vec3 prev = texture(accumTexture, fragTexCoord).rgb;
    vec3 linear_color;
    if (frameCount <= 1) {
        linear_color = newSample;
    } else {
        float blend = 1.0 / float(frameCount);
        linear_color = mix(prev, newSample, blend);
    }

    // Output LINEAR HDR to accumulation buffer.
    // Tone mapping + gamma are applied in the display shader,
    // NOT here — otherwise the accumulated result gets tone-mapped
    // again each frame and the image darkens to black.
    finalColor = vec4(linear_color, 1.0);
}
