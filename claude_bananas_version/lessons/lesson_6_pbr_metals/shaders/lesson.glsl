// ============================================================
// Lesson 6: PBR Metals — Microfacet Theory
// ============================================================
//
// Real metal surfaces aren't perfectly smooth — they have
// microscopic bumps called "microfacets." Each microfacet is
// a tiny perfect mirror, but their orientations vary randomly.
//
// The GGX model describes HOW these facets are distributed:
//   - Low roughness → facets all point the same way → sharp reflection
//   - High roughness → facets point everywhere → blurry reflection
//
// Three ingredients of the Cook-Torrance BRDF:
//
//   D (Distribution) — how many microfacets face the "halfway" direction?
//     Uses the GGX/Trowbridge-Reitz formula.
//
//   F (Fresnel) — how much light reflects vs. absorbs?
//     Metals reflect more at grazing angles (Schlick approximation).
//
//   G (Geometry/Visibility) — do microfacets shadow each other?
//     Tall facets can block light from reaching neighboring facets.
//     Uses Smith's height-correlated masking function.
//
// Scene: row of metal spheres with roughness from 0.0 to 1.0
//
// Controls:
//   Left/Right arrows — select sphere
//   Up/Down arrows — adjust roughness of selected sphere

#ifdef GL_ES
precision highp float;
#endif

#define EPSILON 0.001
#define PI 3.14159265359
#define NUM_SPHERES 7

in vec2 fragTexCoord;
out vec4 finalColor;

uniform sampler2D texture0;
uniform vec3  cameraPosition;
uniform mat4  invViewProj;
uniform mat4  viewProj;
uniform vec2  resolution;
uniform int   frameCount;
uniform int   selectedSphere;

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
// PBR Building Blocks
// ============================================================

// GGX Normal Distribution Function (D term)
//
// "What fraction of microfacets are oriented so their normal
//  aligns with the half-vector H?"
//
// NdotH: cos angle between surface normal and half-vector
// alpha: roughness squared (rougher = wider distribution)
//
//           alpha^2
// D = ─────────────────────────────
//     pi * (NdotH^2 * (alpha^2 - 1) + 1)^2
//
float D_GGX(float NdotH, float alpha) {
    float a2 = alpha * alpha;
    float denom = NdotH * NdotH * (a2 - 1.0) + 1.0;
    return a2 / (PI * denom * denom + 1e-7);
}

// Fresnel-Schlick approximation (F term)
//
// "How much light is reflected (vs absorbed) at this angle?"
//
// At normal incidence: reflectance = F0 (the base color for metals)
// At grazing angles: reflectance → 1.0 (everything becomes a mirror!)
//
// F = F0 + (1 - F0) * (1 - cosTheta)^5
//
vec3 F_Schlick(float cosTheta, vec3 F0) {
    float x = clamp(1.0 - cosTheta, 0.0, 1.0);
    float x2 = x * x;
    float x5 = x2 * x2 * x;  // x^5 via multiply chain (faster than pow)
    return F0 + (1.0 - F0) * x5;
}

// Smith GGX Visibility function (G term, combined form)
//
// "How much light is blocked by neighboring microfacets?"
//
// This uses the height-correlated Smith model, which accounts
// for the fact that a facet visible to the camera may still be
// shadowed from the light source (and vice versa).
//
// Returns G/(4*NdotV*NdotL) — the combined masking-shadowing
// divided by the BRDF denominator, for efficiency.
//
float V_SmithGGX(float NdotV, float NdotL, float alpha) {
    float a2 = alpha * alpha;
    float ggxV = NdotL * sqrt(NdotV * NdotV * (1.0 - a2) + a2);
    float ggxL = NdotV * sqrt(NdotL * NdotL * (1.0 - a2) + a2);
    return 0.5 / (ggxV + ggxL + 1e-7);
}

// ============================================================
// GGX Importance Sampling
// ============================================================
//
// Instead of randomly picking a reflection direction, we
// IMPORTANCE SAMPLE: pick directions that are more likely
// to contribute light (i.e., where D(H) is large).
//
// We sample the half-vector H from the GGX distribution,
// then compute the reflected direction L = reflect(-V, H).
//
vec3 sampleGGX(vec3 N, float alpha) {
    float u1 = rnd();
    float u2 = rnd();

    // Sample spherical coords for H in tangent space
    float a2 = alpha * alpha;
    float cosTheta = sqrt((1.0 - u1) / (1.0 + (a2 - 1.0) * u1));
    float sinTheta = sqrt(1.0 - cosTheta * cosTheta);
    float phi = 2.0 * PI * u2;

    // Tangent space H
    vec3 H_local = vec3(sinTheta * cos(phi), sinTheta * sin(phi), cosTheta);

    // Build TBN basis from N
    vec3 up = abs(N.y) < 0.999 ? vec3(0,1,0) : vec3(1,0,0);
    vec3 tangent = normalize(cross(up, N));
    vec3 bitangent = cross(N, tangent);

    return normalize(tangent * H_local.x + bitangent * H_local.y + N * H_local.z);
}

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

// Sphere positions, colors, roughness
vec3 spherePos(int i) {
    float x = -3.0 + float(i) * 1.0;
    return vec3(x, 0.4, -2.5);
}
const float sphereR = 0.4;

vec3 sphereColor(int i) {
    // Gold → copper → silver gradient
    vec3 colors[7] = vec3[7](
        vec3(1.0, 0.78, 0.34),   // gold
        vec3(0.95, 0.64, 0.37),  // copper
        vec3(0.91, 0.55, 0.48),  // rose gold
        vec3(0.77, 0.78, 0.78),  // silver
        vec3(0.66, 0.66, 0.68),  // pewter
        vec3(0.56, 0.57, 0.58),  // dark silver
        vec3(0.45, 0.46, 0.48)   // gunmetal
    );
    return colors[i];
}

float sphereRoughness(int i) {
    return 0.02 + float(i) * 0.15; // 0.02 to ~0.92
}

vec3 skyColor(vec3 dir) {
    float t = 0.5 * (dir.y + 1.0);
    vec3 bottom = vec3(0.8, 0.7, 0.6);
    vec3 top = vec3(0.25, 0.45, 0.8);
    vec3 sky = mix(bottom, top, t);
    // Add a "sun" for nice reflections
    vec3 sunDir = normalize(vec3(0.5, 0.3, 0.8));
    float sunDot = max(dot(dir, sunDir), 0.0);
    sky += vec3(1.0, 0.9, 0.7) * pow(sunDot, 128.0) * 3.0;
    sky += vec3(1.0, 0.85, 0.6) * pow(sunDot, 8.0) * 0.3;
    return sky;
}

// ============================================================
// Main — trace one bounce for metal spheres
// ============================================================
void main() {
    uvec2 px = uvec2(gl_FragCoord.xy);
    vec2 pixelSize = 2.0 / resolution;

    // Average over a few samples for smoother result
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

        // Find closest sphere hit
        float bestT = 1e38;
        vec3 bestN;
        int hitIdx = -1;

        // Ground
        float gt; vec3 gn;
        if (intersectSphere(ray, vec3(0,-100.5,-2), 100.0, bestT, gt, gn)) {
            bestT = gt; bestN = gn; hitIdx = -2; // ground marker
        }

        for (int i = 0; i < NUM_SPHERES; i++) {
            float t; vec3 n;
            if (intersectSphere(ray, spherePos(i), sphereR, bestT, t, n)) {
                bestT = t; bestN = n; hitIdx = i;
            }
        }

        if (hitIdx == -1) {
            accumColor += skyColor(ray.direction);
            continue;
        }

        if (hitIdx == -2) {
            // Ground: simple checkerboard
            vec3 hitPt = ray.origin + ray.direction * bestT;
            float check = step(0.0, sin(hitPt.x * PI) * sin(hitPt.z * PI));
            vec3 groundCol = mix(vec3(0.3, 0.3, 0.28), vec3(0.5, 0.5, 0.47), check);
            // Simple lighting on ground
            vec3 lightDir = normalize(vec3(0.5, 1.0, 0.3));
            float diff = max(dot(bestN, lightDir), 0.0);
            accumColor += groundCol * (0.15 + diff * 0.6);
            continue;
        }

        // Metal sphere: GGX importance sampling
        vec3 hitPt = ray.origin + ray.direction * bestT;
        vec3 N = bestN;
        vec3 V = normalize(cameraPosition - hitPt);
        vec3 F0 = sphereColor(hitIdx);
        float roughness = sphereRoughness(hitIdx);
        float alpha = max(roughness * roughness, 0.002);

        // Sample a reflection direction via GGX
        vec3 H = sampleGGX(N, alpha);
        vec3 L = reflect(-V, H);

        float NdotL = dot(N, L);
        if (NdotL <= 0.0) { accumColor += vec3(0.0); continue; }

        float NdotV = max(dot(N, V), 0.001);
        float NdotH = max(dot(N, H), 0.0);
        float VdotH = max(dot(V, H), 0.0);

        // Evaluate BRDF terms
        vec3 F = F_Schlick(VdotH, F0);
        float G = V_SmithGGX(NdotV, NdotL, alpha) * 4.0 * NdotV * NdotL;
        float weight = G * VdotH / (NdotH * NdotV + 1e-7);

        // Trace reflected ray
        Ray reflected = Ray(hitPt + N * EPSILON, L);

        // Check if reflected ray hits another sphere
        float rBestT = 1e38; vec3 rBestN; int rHitIdx = -1;
        if (intersectSphere(reflected, vec3(0,-100.5,-2), 100.0, rBestT, gt, gn)) {
            rBestT = gt; rBestN = gn; rHitIdx = -2;
        }
        for (int j = 0; j < NUM_SPHERES; j++) {
            float rt; vec3 rn;
            if (intersectSphere(reflected, spherePos(j), sphereR, rBestT, rt, rn)) {
                rBestT = rt; rBestN = rn; rHitIdx = j;
            }
        }

        vec3 incomingLight;
        if (rHitIdx == -1) {
            incomingLight = skyColor(L);
        } else if (rHitIdx == -2) {
            vec3 rHitPt = reflected.origin + L * rBestT;
            float check = step(0.0, sin(rHitPt.x*PI)*sin(rHitPt.z*PI));
            incomingLight = mix(vec3(0.3,0.3,0.28), vec3(0.5,0.5,0.47), check) * 0.5;
        } else {
            incomingLight = sphereColor(rHitIdx) * 0.3;
        }

        accumColor += F * weight * incomingLight;
    }

    vec3 color = accumColor / float(spp);

    // --- Viz overlays ---
    vec2 pxCoord = gl_FragCoord.xy;

    // Highlight selected sphere with a ring
    if (selectedSphere >= 0 && selectedSphere < NUM_SPHERES) {
        vec3 selPos = spherePos(selectedSphere);
        // Ring around selected sphere
        vec3 sp = projectToScreen(selPos, viewProj, resolution);
        if (sp.z > 0.0) {
            vec2 screenPx = sp.xy * resolution;
            float dist = abs(length(pxCoord - screenPx) - 30.0);
            float ringAlpha = edgeAlpha(dist, 1.5);
            color = mix(color, vec3(1.0, 1.0, 0.3), ringAlpha);
        }

        // Show roughness label (dot size proportional to roughness)
        float r = sphereRoughness(selectedSphere);
        vec4 rDot = vizPoint(pxCoord, selPos + vec3(0, 0.7, 0),
                             viewProj, resolution,
                             vec3(1.0, 0.8, 0.2), 3.0 + r * 15.0);
        color = vizComposite(color, rDot);
    }

    // Axes
    vec4 axes = vizAxes(pxCoord, vec3(0.0), viewProj, resolution, 0.5, 1.0);
    color = vizComposite(color, axes);

    color = pow(max(color, 0.0), vec3(1.0 / 2.2));
    finalColor = vec4(color, 1.0);
}
