// ============================================================
// Lesson 9: Temporal Accumulation — From Noise to Clean Image
// ============================================================
//
// Each frame, we shoot random rays. One frame = very noisy.
// But randomness has a beautiful property:
//
//   AVERAGE OF N RANDOM SAMPLES → TRUE VALUE
//   (Law of Large Numbers)
//
// Noise decreases as 1/sqrt(N). So:
//   4 frames   → half the noise of 1 frame
//   100 frames → 1/10 the noise
//   10000 frames → 1/100 the noise
//
// We accumulate by blending each new frame with the running
// average. When the camera moves, we reset (old samples are
// from the wrong viewpoint).
//
// Blend formula:
//   output = mix(previous, current, 1/frameCount)
//
// This gives equal weight to every frame:
//   Frame 1: output = current (blend = 1.0)
//   Frame 2: output = (prev + current) / 2 (blend = 0.5)
//   Frame N: output = average of all N frames (blend = 1/N)
//
// Controls:
//   R — reset accumulation
//   P — pause accumulation (freeze image)
//   Right-click drag — orbit (auto-resets)

#ifdef GL_ES
precision highp float;
#endif

#define EPSILON 0.001
#define PI 3.14159265359

in vec2 fragTexCoord;
out vec4 finalColor;

uniform sampler2D texture0;
uniform sampler2D accumTexture;  // previous accumulated frame

uniform vec3  cameraPosition;
uniform mat4  invViewProj;
uniform vec2  resolution;
uniform int   frameCount;

// ============================================================
// RNG
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

// ============================================================
// Scene — colorful spheres on a ground plane
// ============================================================
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

vec3 skyColor(vec3 dir) {
    float t = 0.5*(dir.y+1.0);
    vec3 sky = mix(vec3(0.8,0.7,0.6), vec3(0.25,0.45,0.8), t);
    vec3 sunDir = normalize(vec3(0.5,0.2,0.8));
    sky += vec3(1,0.9,0.7) * pow(max(dot(dir,sunDir),0.0), 128.0) * 3.0;
    return sky;
}

struct HitResult { float t; vec3 normal, color; bool emissive; vec3 emission; };

void findHit(Ray r, out HitResult h) {
    h.t = 1e38; h.emissive = false;
    float t; vec3 n;

    // Ground
    if (iSphere(r, vec3(0,-100.5,-2), 100.0, h.t, t, n))
        { h.t=t; h.normal=n; h.color=vec3(0.5,0.5,0.47); h.emissive=false; }
    // Colored spheres
    if (iSphere(r, vec3(-1.2,0.5,-3.0), 0.8, h.t, t, n))
        { h.t=t; h.normal=n; h.color=vec3(0.85,0.3,0.3); h.emissive=false; }
    if (iSphere(r, vec3(0.8,0.4,-2.5), 0.6, h.t, t, n))
        { h.t=t; h.normal=n; h.color=vec3(0.3,0.65,0.4); h.emissive=false; }
    if (iSphere(r, vec3(0.0,0.25,-1.5), 0.4, h.t, t, n))
        { h.t=t; h.normal=n; h.color=vec3(0.35,0.45,0.85); h.emissive=false; }
    // Emissive sphere
    if (iSphere(r, vec3(1.5,2.0,-3.0), 0.3, h.t, t, n))
        { h.t=t; h.normal=n; h.color=vec3(1); h.emissive=true; h.emission=vec3(1,0.9,0.7)*6.0; }
}

// Single-sample path trace (3 bounces)
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
// Main — single sample + temporal accumulation blend
// ============================================================
void main() {
    uvec2 px = uvec2(gl_FragCoord.xy);
    rngState = px.x*1973u + px.y*9277u + uint(frameCount)*26699u;
    rnd();

    // Generate ray (single sample — the noise is the point!)
    vec2 pixelSize = 2.0 / resolution;
    vec2 jitter = (vec2(rnd(), rnd()) - 0.5) * pixelSize;
    vec2 ndc = fragTexCoord * 2.0 - 1.0 + jitter;
    vec4 wp4 = invViewProj * vec4(ndc, -1.0, 1.0);
    vec3 wp = wp4.xyz / wp4.w;
    Ray ray = Ray(cameraPosition, normalize(wp - cameraPosition));

    vec3 newSample = pathTrace(ray);

    // ── Temporal accumulation ──
    // Read previous accumulated color
    vec3 prev = texture(accumTexture, fragTexCoord).rgb;

    // Blend: equal weight to each frame
    // blendFactor = 1/N → running average
    vec3 output_color;
    if (frameCount <= 1) {
        output_color = newSample;
    } else {
        float blend = 1.0 / float(frameCount);
        output_color = mix(prev, newSample, blend);
    }

    // Output LINEAR HDR — tone mapping happens in the display pass.
    // If we tone-mapped here, the accumulated result would get
    // tone-mapped again next frame → image darkens to black!
    finalColor = vec4(output_color, 1.0);
}
