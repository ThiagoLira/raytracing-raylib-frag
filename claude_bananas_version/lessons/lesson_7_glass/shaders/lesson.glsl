// ============================================================
// Lesson 7: Glass & Refraction
// ============================================================
//
// When light hits a transparent material (glass, water, diamond),
// two things happen:
//
//   1. REFLECTION — some light bounces off the surface
//   2. REFRACTION — some light passes through, bending direction
//
// Snell's Law: n1 * sin(theta1) = n2 * sin(theta2)
//   n1, n2 are "indices of refraction" (IOR)
//   Air ≈ 1.0,  Glass ≈ 1.5,  Water ≈ 1.33,  Diamond ≈ 2.42
//
// TOTAL INTERNAL REFLECTION:
//   When going from glass→air at a steep angle, refraction
//   becomes impossible (sin(theta2) > 1). All light reflects.
//   This is why diamonds sparkle!
//
// FRESNEL EFFECT:
//   Even when refraction IS possible, the reflection/refraction
//   ratio depends on the angle. At grazing angles, reflection
//   dominates. Schlick's approximation models this cheaply.
//
// Controls:
//   1 — reflection only
//   2 — refraction only
//   3 — full Fresnel (realistic)
//   +/- — adjust IOR (1.0 to 2.5)

#ifdef GL_ES
precision highp float;
#endif

#define EPSILON 0.001
#define PI 3.14159265359
#define MAX_DEPTH 6

in vec2 fragTexCoord;
out vec4 finalColor;

uniform sampler2D texture0;
uniform vec3  cameraPosition;
uniform mat4  invViewProj;
uniform mat4  viewProj;
uniform vec2  resolution;
uniform int   mode;       // 0=reflect, 1=refract, 2=fresnel
uniform int   frameCount;
uniform float ior;        // index of refraction

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

// Checkered ground
const vec3 groundC = vec3(0, -100.5, -2);
const float groundR = 100.0;

// Glass sphere
const vec3 glassC = vec3(0, 0.7, -2.5);
const float glassR = 0.9;

// Small colored spheres behind/beside glass (to see refraction distortion)
const vec3 redC   = vec3(-1.2, 0.25, -3.5);
const vec3 greenC = vec3(0.8, 0.2, -4.0);
const vec3 blueC  = vec3(-0.3, 0.15, -4.5);
const float smallR = 0.35;

vec3 skyColor(vec3 dir) {
    float t = 0.5 * (dir.y + 1.0);
    vec3 bottom = vec3(0.85, 0.75, 0.65);
    vec3 top = vec3(0.2, 0.4, 0.75);
    vec3 sky = mix(bottom, top, t);
    // Sun
    vec3 sunDir = normalize(vec3(0.4, 0.2, 0.9));
    float sunDot = max(dot(dir, sunDir), 0.0);
    sky += vec3(1.0, 0.9, 0.7) * pow(sunDot, 256.0) * 5.0;
    sky += vec3(1.0, 0.8, 0.5) * pow(sunDot, 6.0) * 0.4;
    return sky;
}

// Scene hit (non-glass objects)
bool hitScene(Ray r, out float bestT, out vec3 bestN, out vec3 bestCol) {
    bestT = 1e38;
    bool hit = false;
    float t; vec3 n;

    if (intersectSphere(r, groundC, groundR, bestT, t, n)) {
        bestT = t; bestN = n; hit = true;
        vec3 hp = r.origin + r.direction * t;
        float check = step(0.0, sin(hp.x*PI*2.0)*sin(hp.z*PI*2.0));
        bestCol = mix(vec3(0.35,0.35,0.3), vec3(0.6,0.58,0.55), check);
    }
    if (intersectSphere(r, redC, smallR, bestT, t, n))
        { bestT=t; bestN=n; bestCol=vec3(0.85,0.2,0.2); hit=true; }
    if (intersectSphere(r, greenC, smallR, bestT, t, n))
        { bestT=t; bestN=n; bestCol=vec3(0.2,0.75,0.3); hit=true; }
    if (intersectSphere(r, blueC, smallR, bestT, t, n))
        { bestT=t; bestN=n; bestCol=vec3(0.25,0.35,0.85); hit=true; }
    return hit;
}

// Simple shade for non-glass surfaces
vec3 shadeSurface(vec3 hitPt, vec3 normal, vec3 color) {
    vec3 lightDir = normalize(vec3(0.5, 1.0, 0.3));
    float diff = max(dot(normal, lightDir), 0.0);
    return color * (0.15 + diff * 0.85);
}

// ============================================================
// Dielectric (glass) scattering
// ============================================================
//
// This is the core of glass rendering:
//
// 1. Determine if we're entering or exiting the glass
//    (dot(ray, normal) tells us which side we're on)
//
// 2. Compute the Fresnel reflectance using Schlick's approx:
//    R(theta) = R0 + (1-R0)*(1-cos(theta))^5
//    where R0 = ((n1-n2)/(n1+n2))^2
//
// 3. Check for total internal reflection:
//    If n1*sin(theta1) > n2, refraction is impossible → reflect
//
// 4. Randomly choose reflect or refract based on Fresnel probability
//

void scatterGlass(Ray inRay, vec3 hitPt, vec3 hitNormal, float glassIOR,
                  out Ray outRay, out vec3 attenuation) {
    vec3 unitDir = normalize(inRay.direction);
    vec3 normal;
    float etaRatio;

    // Are we entering or exiting the glass?
    if (dot(unitDir, hitNormal) > 0.0) {
        // Exiting: normal points inward, IOR ratio = glass/air
        normal = -hitNormal;
        etaRatio = glassIOR;
    } else {
        // Entering: normal points outward, IOR ratio = air/glass
        normal = hitNormal;
        etaRatio = 1.0 / glassIOR;
    }

    float cosTheta = min(dot(-unitDir, normal), 1.0);
    float sinTheta2 = etaRatio * etaRatio * (1.0 - cosTheta * cosTheta);

    // Total internal reflection check
    bool cannotRefract = sinTheta2 > 1.0;

    // Schlick's approximation for Fresnel
    float r0 = (1.0 - etaRatio) / (1.0 + etaRatio);
    r0 = r0 * r0;
    float reflectance = r0 + (1.0 - r0) * pow(1.0 - cosTheta, 5.0);

    vec3 direction;
    if (mode == 0) {
        // Reflection only
        direction = reflect(unitDir, normal);
        outRay = Ray(hitPt + normal * EPSILON, direction);
    } else if (mode == 1) {
        // Refraction only (ignore Fresnel, force refract when possible)
        if (cannotRefract) {
            direction = reflect(unitDir, normal);
            outRay = Ray(hitPt + normal * EPSILON, direction);
        } else {
            direction = refract(unitDir, normal, etaRatio);
            outRay = Ray(hitPt - normal * EPSILON, direction);
        }
    } else {
        // Full Fresnel: randomly choose based on reflectance probability
        if (cannotRefract || reflectance > rnd()) {
            direction = reflect(unitDir, normal);
            outRay = Ray(hitPt + normal * EPSILON, direction);
        } else {
            direction = refract(unitDir, normal, etaRatio);
            outRay = Ray(hitPt - normal * EPSILON, direction);
        }
    }

    attenuation = vec3(1.0); // glass doesn't absorb (clear glass)
}

// ============================================================
// Trace ray through glass (multiple bounces)
// ============================================================
vec3 traceRay(Ray ray) {
    vec3 throughput = vec3(1.0);

    for (int depth = 0; depth < MAX_DEPTH; depth++) {
        // Check glass sphere
        float glassT; vec3 glassN;
        bool hitGlass = intersectSphere(ray, glassC, glassR, 1e38, glassT, glassN);

        // Check scene
        float sceneT; vec3 sceneN, sceneCol;
        bool hitScn = hitScene(ray, sceneT, sceneN, sceneCol);

        if (!hitGlass && !hitScn) {
            return throughput * skyColor(ray.direction);
        }

        if (hitGlass && (!hitScn || glassT < sceneT)) {
            // Hit glass → scatter
            vec3 hitPt = ray.origin + ray.direction * glassT;
            vec3 atten;
            scatterGlass(ray, hitPt, glassN, ior, ray, atten);
            throughput *= atten;
        } else {
            // Hit scene surface → shade and stop
            vec3 hitPt = ray.origin + ray.direction * sceneT;
            return throughput * shadeSurface(hitPt, sceneN, sceneCol);
        }
    }

    return throughput * skyColor(ray.direction);
}

// ============================================================
// Main
// ============================================================
void main() {
    uvec2 px = uvec2(gl_FragCoord.xy);
    vec2 pixelSize = 2.0 / resolution;

    int spp = 8;
    vec3 accumColor = vec3(0.0);

    for (int s = 0; s < spp; s++) {
        rngState = px.x*1973u + px.y*9277u + uint(frameCount)*26699u + uint(s)*39293u;
        rnd();

        vec2 jitter = (vec2(rnd(), rnd()) - 0.5) * pixelSize;
        vec2 ndc = fragTexCoord * 2.0 - 1.0 + jitter;
        vec4 wp4 = invViewProj * vec4(ndc, -1.0, 1.0);
        vec3 wp = wp4.xyz / wp4.w;
        Ray ray = Ray(cameraPosition, normalize(wp - cameraPosition));

        accumColor += traceRay(ray);
    }

    vec3 color = accumColor / float(spp);

    // --- Viz overlays ---
    vec2 pxCoord = gl_FragCoord.xy;

    // Show glass sphere center
    vec4 centerDot = vizPoint(pxCoord, glassC, viewProj, resolution,
                               vec3(0.8, 0.9, 1.0), 4.0);
    color = vizComposite(color, centerDot);

    // Axes
    vec4 axes = vizAxes(pxCoord, vec3(0.0), viewProj, resolution, 0.5, 1.0);
    color = vizComposite(color, axes);

    color = pow(max(color, 0.0), vec3(1.0 / 2.2));
    finalColor = vec4(color, 1.0);
}
