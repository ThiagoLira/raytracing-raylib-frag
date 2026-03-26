// ============================================================
// Lesson 5: Shadow Rays
// ============================================================
//
// How do we know if a point is in shadow?
//
// Shoot a "shadow ray" from the hit point toward the light.
// If it hits any object before reaching the light → shadow.
// If it reaches the light unobstructed → lit.
//
// HARD shadows: one ray, binary result (lit or not).
// SOFT shadows: multiple rays aimed at random points on
//   the light's surface → partially lit = soft edge.
//
// Controls:
//   1 — no shadows (direct lighting only)
//   2 — hard shadows (single shadow ray)
//   3 — soft shadows (jittered rays to area light)
//   +/- — adjust light radius (affects soft shadow width)

#ifdef GL_ES
precision highp float;
#endif

#define EPSILON 0.001
#define PI 3.14159265359
#define SHADOW_SAMPLES 8

in vec2 fragTexCoord;
out vec4 finalColor;

uniform sampler2D texture0;
uniform vec3  cameraPosition;
uniform mat4  invViewProj;
uniform mat4  viewProj;
uniform vec2  resolution;
uniform int   mode;        // 0=no shadow, 1=hard, 2=soft
uniform int   frameCount;
uniform float lightRadius; // for soft shadows

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
vec3 rndVec3() { return vec3(rnd(), rnd(), rnd()); }

// ============================================================
// Scene
// ============================================================
struct Ray { vec3 origin, direction; };

bool intersectSphere(Ray r, vec3 center, float radius,
                     float tMax, out float tHit, out vec3 normal) {
    vec3 oc = r.origin - center;
    float b = dot(r.direction, oc);
    float c = dot(oc, oc) - radius*radius;
    float disc = b*b - c;
    if (disc < 0.0) return false;
    float sq = sqrt(disc);
    float t = -b - sq;
    if (t < EPSILON || t > tMax) { t = -b + sq; if (t < EPSILON || t > tMax) return false; }
    tHit = t;
    normal = normalize(oc + t * r.direction);
    return true;
}

// Scene objects
const vec3 groundCenter = vec3(0, -100.5, -2);
const float groundR = 100.0;
const vec3 groundColor = vec3(0.55, 0.52, 0.48);

const vec3 sph1C = vec3(0, 0.5, -2.5);
const float sph1R = 0.85;
const vec3 sph1Col = vec3(0.85, 0.35, 0.3);

const vec3 sph2C = vec3(-1.5, 0.25, -1.8);
const float sph2R = 0.55;
const vec3 sph2Col = vec3(0.3, 0.5, 0.8);

const vec3 sph3C = vec3(1.3, 0.2, -1.5);
const float sph3R = 0.45;
const vec3 sph3Col = vec3(0.4, 0.75, 0.35);

// Light position (point light)
const vec3 lightPos = vec3(2.0, 4.0, 0.0);
const vec3 lightColor = vec3(1.0, 0.95, 0.85);

vec3 skyColor(vec3 dir) {
    float t = 0.5 * (dir.y + 1.0);
    return mix(vec3(0.7, 0.6, 0.55), vec3(0.25, 0.45, 0.75), t);
}

// Closest hit across all scene objects
bool closestHit(Ray r, out float bestT, out vec3 bestN, out vec3 bestCol) {
    bestT = 1e38;
    bool hit = false;
    float t; vec3 n;
    if (intersectSphere(r, groundCenter, groundR, bestT, t, n))
        { bestT=t; bestN=n; bestCol=groundColor; hit=true; }
    if (intersectSphere(r, sph1C, sph1R, bestT, t, n))
        { bestT=t; bestN=n; bestCol=sph1Col; hit=true; }
    if (intersectSphere(r, sph2C, sph2R, bestT, t, n))
        { bestT=t; bestN=n; bestCol=sph2Col; hit=true; }
    if (intersectSphere(r, sph3C, sph3R, bestT, t, n))
        { bestT=t; bestN=n; bestCol=sph3Col; hit=true; }
    return hit;
}

// ============================================================
// Shadow test: does anything block the path from P to the light?
// ============================================================
//
// "Any-hit" query — we don't need to find the CLOSEST hit,
// just whether ANYTHING is in the way. This lets us exit
// early on the first intersection (faster than closest-hit).

bool anyHit(Ray r, float maxDist) {
    float t; vec3 n;
    if (intersectSphere(r, groundCenter, groundR, maxDist, t, n)) return true;
    if (intersectSphere(r, sph1C, sph1R, maxDist, t, n)) return true;
    if (intersectSphere(r, sph2C, sph2R, maxDist, t, n)) return true;
    if (intersectSphere(r, sph3C, sph3R, maxDist, t, n)) return true;
    return false;
}

// ============================================================
// Shadow computation
// ============================================================

// HARD shadow: single ray to light center
float hardShadow(vec3 hitPt, vec3 N) {
    vec3 toLight = lightPos - hitPt;
    float dist = length(toLight);
    vec3 dir = toLight / dist;

    // Only test if light is above the surface
    if (dot(dir, N) <= 0.0) return 0.0;

    Ray shadowRay = Ray(hitPt + N * EPSILON, dir);
    return anyHit(shadowRay, dist) ? 0.0 : 1.0;
}

// SOFT shadow: multiple rays to random points on the light sphere
//
// A real light has physical size (it's not infinitely small).
// We jitter the shadow ray target across the light's surface.
// Average the results → smooth shadow boundary.
//
// More samples = smoother but slower.
// The "penumbra" (soft edge) width scales with light radius.
float softShadow(vec3 hitPt, vec3 N) {
    float visible = 0.0;
    for (int i = 0; i < SHADOW_SAMPLES; i++) {
        // Random point on light surface (jitter)
        vec3 jitter = (rndVec3() * 2.0 - 1.0) * lightRadius;
        vec3 target = lightPos + jitter;
        vec3 toTarget = target - hitPt;
        float dist = length(toTarget);
        vec3 dir = toTarget / dist;

        if (dot(dir, N) <= 0.0) continue;

        Ray shadowRay = Ray(hitPt + N * EPSILON, dir);
        if (!anyHit(shadowRay, dist)) visible += 1.0;
    }
    return visible / float(SHADOW_SAMPLES);
}

// ============================================================
// Main
// ============================================================
void main() {
    uvec2 px = uvec2(gl_FragCoord.xy);
    rngState = px.x * 1973u + px.y * 9277u + uint(frameCount) * 26699u;
    rnd();

    // Generate ray
    vec2 pixelSize = 2.0 / resolution;
    vec2 jitter = (vec2(rnd(), rnd()) - 0.5) * pixelSize;
    vec2 ndc = fragTexCoord * 2.0 - 1.0 + jitter;
    vec4 wp4 = invViewProj * vec4(ndc, -1.0, 1.0);
    vec3 wp = wp4.xyz / wp4.w;
    Ray ray = Ray(cameraPosition, normalize(wp - cameraPosition));

    // Find closest hit
    float bestT; vec3 bestN, bestCol;
    vec3 color;

    if (closestHit(ray, bestT, bestN, bestCol)) {
        vec3 hitPt = ray.origin + ray.direction * bestT;

        // Direct lighting (diffuse)
        vec3 toLight = normalize(lightPos - hitPt);
        float diff = max(dot(bestN, toLight), 0.0);

        // Distance attenuation
        float d = length(lightPos - hitPt);
        float att = 1.0 / (1.0 + 0.09*d + 0.032*d*d);

        // Shadow factor
        float shadow = 1.0;
        if (mode == 1) {
            shadow = hardShadow(hitPt, bestN);
        } else if (mode == 2) {
            shadow = softShadow(hitPt, bestN);
        }

        float ambient = 0.08;
        color = bestCol * (ambient + diff * att * shadow * lightColor);
    } else {
        color = skyColor(ray.direction);
    }

    // --- Viz overlays ---
    vec2 pxCoord = gl_FragCoord.xy;

    // Show the light position as a bright dot
    vec4 lightDot = vizPoint(pxCoord, lightPos, viewProj, resolution,
                             vec3(1.0, 0.95, 0.7), 8.0);
    color = vizComposite(color, lightDot);

    // Show light radius as a circle (4 points on the sphere surface)
    if (mode == 2) {
        vec4 lr = vizPoint(pxCoord, lightPos+vec3(lightRadius,0,0), viewProj, resolution, vec3(1,0.9,0.5), 2.5);
        vec4 ll = vizPoint(pxCoord, lightPos-vec3(lightRadius,0,0), viewProj, resolution, vec3(1,0.9,0.5), 2.5);
        vec4 lu = vizPoint(pxCoord, lightPos+vec3(0,lightRadius,0), viewProj, resolution, vec3(1,0.9,0.5), 2.5);
        vec4 ld = vizPoint(pxCoord, lightPos-vec3(0,lightRadius,0), viewProj, resolution, vec3(1,0.9,0.5), 2.5);
        color = vizComposite(color, lr);
        color = vizComposite(color, ll);
        color = vizComposite(color, lu);
        color = vizComposite(color, ld);
    }

    // Show a sample shadow ray from the center sphere to light
    vec4 shadowRayViz = vizLine(pxCoord, sph1C + vec3(0,sph1R,0), lightPos,
                                viewProj, resolution,
                                vec3(1.0, 0.8, 0.2), 1.0);
    color = vizComposite(color, shadowRayViz);

    // Axes
    vec4 axes = vizAxes(pxCoord, vec3(0.0), viewProj, resolution, 0.5, 1.0);
    color = vizComposite(color, axes);

    color = pow(max(color, 0.0), vec3(1.0 / 2.2));
    finalColor = vec4(color, 1.0);
}
