// ============================================================
// Lesson 4: Diffuse Reflection & Hemisphere Sampling
// ============================================================
//
// A matte (Lambertian) surface scatters light equally in all
// directions above the surface. When a ray hits it, we pick
// a RANDOM direction in the hemisphere above the hit point
// and keep tracing.
//
// Two sampling strategies:
//
//   UNIFORM hemisphere: every direction equally likely.
//     Simple, but wastes samples on grazing angles that
//     contribute little light.
//
//   COSINE-WEIGHTED hemisphere: more likely to sample near
//     the normal. Matches the cos(theta) falloff of Lambert's
//     law, giving lower noise for the same sample count.
//
// Controls:
//   1 — uniform hemisphere sampling
//   2 — cosine-weighted hemisphere sampling
//   +/- — adjust samples per pixel (1, 4, 16, 64)
//
// Watch how cosine-weighted is cleaner at the same SPP!

#ifdef GL_ES
precision highp float;
#endif

#define EPSILON 0.001
#define PI 3.14159265359

in vec2 fragTexCoord;
out vec4 finalColor;

uniform sampler2D texture0;
uniform vec3  cameraPosition;
uniform mat4  invViewProj;
uniform mat4  viewProj;
uniform vec2  resolution;
uniform int   mode;       // 0=uniform, 1=cosine
uniform int   frameCount;
uniform int   spp;        // samples per pixel

// ============================================================
// RNG (same as Lesson 3)
// ============================================================
uint rngState;

uint pcgHash(uint v) {
    uint state = v * 747796405u + 2891336453u;
    uint word = ((state >> ((state >> 28u) + 4u)) ^ state) * 277803737u;
    return (word >> 22u) ^ word;
}

float rnd() {
    rngState = pcgHash(rngState);
    return float(rngState) / 4294967295.0;
}

// ============================================================
// Hemisphere sampling — the two strategies
// ============================================================

// UNIFORM: equal probability in all hemisphere directions.
// PDF = 1/(2*pi) — flat distribution over the dome.
vec3 uniformHemisphere(vec3 normal) {
    // Generate a random direction on the full sphere
    vec3 v = vec3(rnd()*2.0-1.0, rnd()*2.0-1.0, rnd()*2.0-1.0);
    float lenSq = dot(v, v);
    if (lenSq < 0.0001) return normal;
    v = v / sqrt(lenSq);
    // Flip to the hemisphere above the normal
    return dot(v, normal) > 0.0 ? v : -v;
}

// COSINE-WEIGHTED: samples more densely near the normal.
// PDF = cos(theta)/pi — matches Lambert's cosine law perfectly.
//
// Method: generate a random point on the unit disk (r, theta),
// then project it up onto the hemisphere.
//
//   r = sqrt(u2)          — concentrates samples near center
//   x = r * cos(2*pi*u1)  — disk x
//   y = r * sin(2*pi*u1)  — disk y
//   z = sqrt(1 - u2)      — hemisphere height
//
// Then rotate from local coordinates to world using a
// tangent frame built from the surface normal.
vec3 cosineHemisphere(vec3 normal) {
    float u1 = rnd();
    float u2 = rnd();
    float r = sqrt(u2);
    float theta = 2.0 * PI * u1;
    float x = r * cos(theta);
    float y = r * sin(theta);
    float z = sqrt(1.0 - u2);  // always positive → upper hemisphere

    // Build tangent frame (tangent, bitangent, normal)
    vec3 up = abs(normal.y) < 0.999 ? vec3(0,1,0) : vec3(1,0,0);
    vec3 tangent = normalize(cross(up, normal));
    vec3 bitangent = cross(normal, tangent);

    return normalize(tangent * x + bitangent * y + normal * z);
}

// ============================================================
// Scene
// ============================================================
struct Ray { vec3 origin, direction; };

bool intersectSphere(Ray r, vec3 center, float radius,
                     out float tHit, out vec3 normal) {
    vec3 oc = r.origin - center;
    float b = dot(r.direction, oc);
    float c = dot(oc, oc) - radius*radius;
    float disc = b*b - c;
    if (disc < 0.0) return false;
    float sq = sqrt(disc);
    float t = -b - sq;
    if (t < EPSILON) { t = -b + sq; if (t < EPSILON) return false; }
    tHit = t;
    normal = normalize(oc + t * r.direction);
    return true;
}

// Scene objects
const vec3  groundCenter = vec3(0, -100.5, -2);
const float groundRadius = 100.0;
const vec3  groundColor  = vec3(0.45, 0.45, 0.42);

const vec3  sph1Center   = vec3(0, 0.5, -2.5);
const float sph1Radius   = 0.9;
const vec3  sph1Color    = vec3(0.8, 0.3, 0.35);

const vec3  sph2Center   = vec3(-1.8, 0.3, -2.0);
const float sph2Radius   = 0.6;
const vec3  sph2Color    = vec3(0.3, 0.65, 0.4);

vec3 skyColor(vec3 dir) {
    float t = 0.5 * (dir.y + 1.0);
    return mix(vec3(0.8, 0.7, 0.6), vec3(0.3, 0.5, 0.8), t);
}

// ============================================================
// Trace one ray (single bounce)
// ============================================================
//
// The ray hits a surface → we pick a random scatter direction
// → trace THAT ray to see what color it hits → multiply by
// the surface color. This is the core of path tracing!
//
vec3 traceRay(Ray ray) {
    // First intersection
    float bestT = 1e38;
    vec3  bestN, bestCol;
    bool  hit = false;

    float t; vec3 n;
    if (intersectSphere(ray, groundCenter, groundRadius, t, n) && t < bestT) {
        bestT = t; bestN = n; bestCol = groundColor; hit = true;
    }
    if (intersectSphere(ray, sph1Center, sph1Radius, t, n) && t < bestT) {
        bestT = t; bestN = n; bestCol = sph1Color; hit = true;
    }
    if (intersectSphere(ray, sph2Center, sph2Radius, t, n) && t < bestT) {
        bestT = t; bestN = n; bestCol = sph2Color; hit = true;
    }

    if (!hit) return skyColor(ray.direction);

    // Scatter: pick a random direction above the surface
    vec3 hitPt = ray.origin + ray.direction * bestT;
    vec3 scatterDir;

    if (mode == 0) {
        scatterDir = uniformHemisphere(bestN);
    } else {
        scatterDir = cosineHemisphere(bestN);
    }

    // Trace the scattered ray → what color does it see?
    Ray scattered = Ray(hitPt + bestN * EPSILON, scatterDir);

    // Second intersection (one bounce only for this lesson)
    float t2; vec3 n2;
    vec3 incomingLight;
    bool hit2 = false;
    float bestT2 = 1e38;
    vec3 bestCol2;

    if (intersectSphere(scattered, groundCenter, groundRadius, t2, n2) && t2 < bestT2) {
        bestT2 = t2; bestCol2 = groundColor; hit2 = true;
    }
    if (intersectSphere(scattered, sph1Center, sph1Radius, t2, n2) && t2 < bestT2) {
        bestT2 = t2; bestCol2 = sph1Color; hit2 = true;
    }
    if (intersectSphere(scattered, sph2Center, sph2Radius, t2, n2) && t2 < bestT2) {
        bestT2 = t2; bestCol2 = sph2Color; hit2 = true;
    }

    if (hit2) {
        incomingLight = bestCol2 * 0.5; // dim second-bounce color
    } else {
        incomingLight = skyColor(scattered.direction);
    }

    // For uniform sampling, we must multiply by cos(theta) and
    // divide by the PDF = 1/(2*pi):
    //   color = albedo * incomingLight * cos(theta) * 2*pi
    //
    // For cosine sampling, PDF = cos(theta)/pi, so the cos(theta)
    // cancels and we get:
    //   color = albedo * incomingLight * pi * (1/pi) = albedo * incomingLight
    //
    // This cancellation is WHY cosine sampling is preferred.

    if (mode == 0) {
        float cosTheta = max(dot(bestN, scatterDir), 0.0);
        return bestCol * incomingLight * cosTheta * 2.0 * PI;
    } else {
        return bestCol * incomingLight;
    }
}

// ============================================================
// Main
// ============================================================
void main() {
    uvec2 px = uvec2(gl_FragCoord.xy);
    vec2 pixelSize = 2.0 / resolution;

    int samples = clamp(spp, 1, 64);
    vec3 accumColor = vec3(0.0);

    for (int s = 0; s < samples; s++) {
        // Unique seed per pixel + frame + sample
        rngState = px.x * 1973u + px.y * 9277u
                 + uint(frameCount) * 26699u + uint(s) * 39293u;
        rnd(); // warm up

        // Jittered sub-pixel position
        vec2 jitter = (vec2(rnd(), rnd()) - 0.5) * pixelSize;
        vec2 ndc = fragTexCoord * 2.0 - 1.0 + jitter;
        vec4 wp4 = invViewProj * vec4(ndc, -1.0, 1.0);
        vec3 wp = wp4.xyz / wp4.w;

        Ray ray = Ray(cameraPosition, normalize(wp - cameraPosition));
        accumColor += traceRay(ray);
    }

    vec3 color = accumColor / float(samples);

    // Gamma
    color = pow(max(color, 0.0), vec3(1.0 / 2.2));
    finalColor = vec4(color, 1.0);
}
