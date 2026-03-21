// GLSL ES 1.00 (WebGL 1.0) — Full Lighting Reference Implementation
// Implements all 8 features from LIGHTING_THEORY.md:
//   1. Shadow rays
//   2. Point lights with attenuation
//   3. Ambient occlusion (Monte Carlo)
//   4. Emissive materials
//   5. Soft shadows / area lights
//   6. Blinn-Phong specular highlights
//   7. Refraction (Snell's Law + Schlick Fresnel)
//   8. Tone mapping + gamma correction

precision highp float;
precision highp int;

#define MAX_DEPTH 10
#define MAX_SPHERES 10
#define MAX_LIGHTS 4
#define AO_SAMPLES 4
#define SOFT_SHADOW_SAMPLES 4
#define PI 3.14159265359

varying vec2 fragTexCoord;
uniform sampler2D texture0;

uniform vec3 cameraPosition;
uniform mat4 invViewProj;

uniform int sphereCount;
uniform int lightCount;

// ============================================================
// Sphere uniforms (flat — WebGL 1.0 has no arrays with variable index)
// ============================================================
// Geometry
uniform vec3  u_s0_center; uniform float u_s0_radius;
uniform vec3  u_s1_center; uniform float u_s1_radius;
uniform vec3  u_s2_center; uniform float u_s2_radius;
uniform vec3  u_s3_center; uniform float u_s3_radius;
uniform vec3  u_s4_center; uniform float u_s4_radius;
uniform vec3  u_s5_center; uniform float u_s5_radius;
uniform vec3  u_s6_center; uniform float u_s6_radius;
uniform vec3  u_s7_center; uniform float u_s7_radius;
uniform vec3  u_s8_center; uniform float u_s8_radius;
uniform vec3  u_s9_center; uniform float u_s9_radius;

// Base material
uniform vec3  u_s0_color; uniform int u_s0_material;
uniform vec3  u_s1_color; uniform int u_s1_material;
uniform vec3  u_s2_color; uniform int u_s2_material;
uniform vec3  u_s3_color; uniform int u_s3_material;
uniform vec3  u_s4_color; uniform int u_s4_material;
uniform vec3  u_s5_color; uniform int u_s5_material;
uniform vec3  u_s6_color; uniform int u_s6_material;
uniform vec3  u_s7_color; uniform int u_s7_material;
uniform vec3  u_s8_color; uniform int u_s8_material;
uniform vec3  u_s9_color; uniform int u_s9_material;

// Emission (material == 2)
uniform vec3  u_s0_emission; uniform float u_s0_emissionStrength;
uniform vec3  u_s1_emission; uniform float u_s1_emissionStrength;
uniform vec3  u_s2_emission; uniform float u_s2_emissionStrength;
uniform vec3  u_s3_emission; uniform float u_s3_emissionStrength;
uniform vec3  u_s4_emission; uniform float u_s4_emissionStrength;
uniform vec3  u_s5_emission; uniform float u_s5_emissionStrength;
uniform vec3  u_s6_emission; uniform float u_s6_emissionStrength;
uniform vec3  u_s7_emission; uniform float u_s7_emissionStrength;
uniform vec3  u_s8_emission; uniform float u_s8_emissionStrength;
uniform vec3  u_s9_emission; uniform float u_s9_emissionStrength;

// IOR (material == 3, dielectric)
uniform float u_s0_ior; uniform float u_s1_ior; uniform float u_s2_ior;
uniform float u_s3_ior; uniform float u_s4_ior; uniform float u_s5_ior;
uniform float u_s6_ior; uniform float u_s7_ior; uniform float u_s8_ior;
uniform float u_s9_ior;

// Roughness (material == 1, metal fuzz)
uniform float u_s0_roughness; uniform float u_s1_roughness; uniform float u_s2_roughness;
uniform float u_s3_roughness; uniform float u_s4_roughness; uniform float u_s5_roughness;
uniform float u_s6_roughness; uniform float u_s7_roughness; uniform float u_s8_roughness;
uniform float u_s9_roughness;

// Specular coefficient k_s and shininess n_s (Blinn-Phong)
uniform float u_s0_specular; uniform float u_s0_shininess;
uniform float u_s1_specular; uniform float u_s1_shininess;
uniform float u_s2_specular; uniform float u_s2_shininess;
uniform float u_s3_specular; uniform float u_s3_shininess;
uniform float u_s4_specular; uniform float u_s4_shininess;
uniform float u_s5_specular; uniform float u_s5_shininess;
uniform float u_s6_specular; uniform float u_s6_shininess;
uniform float u_s7_specular; uniform float u_s7_shininess;
uniform float u_s8_specular; uniform float u_s8_shininess;
uniform float u_s9_specular; uniform float u_s9_shininess;

// ============================================================
// Light uniforms — type: 0 = directional, 1 = point
// ============================================================
uniform int   u_l0_type; uniform vec3 u_l0_direction; uniform vec3 u_l0_position;
uniform vec3  u_l0_color; uniform float u_l0_intensity; uniform float u_l0_radius;
uniform int   u_l1_type; uniform vec3 u_l1_direction; uniform vec3 u_l1_position;
uniform vec3  u_l1_color; uniform float u_l1_intensity; uniform float u_l1_radius;
uniform int   u_l2_type; uniform vec3 u_l2_direction; uniform vec3 u_l2_position;
uniform vec3  u_l2_color; uniform float u_l2_intensity; uniform float u_l2_radius;
uniform int   u_l3_type; uniform vec3 u_l3_direction; uniform vec3 u_l3_position;
uniform vec3  u_l3_color; uniform float u_l3_intensity; uniform float u_l3_radius;

// ============================================================
// Global uniforms
// ============================================================
uniform float k_linear;
uniform float k_quadratic;
uniform float aoRadius;
uniform float aoStrength;
uniform int   toneMapMode; // 0 = none, 1 = Reinhard, 2 = ACES
uniform float time;

// ============================================================
// Structs
// ============================================================
struct Ray {
    vec3 origin;
    vec3 direction;
};

struct HitRecord {
    float t;
    vec3 hitPoint;
    vec3 normal;
    bool isHit;
};

// ============================================================
// RNG
// ============================================================
float randomDouble(inout float currentSeed) {
    currentSeed = fract(sin(currentSeed * 12.9898) * 43758.5453);
    return currentSeed;
}

vec3 randomVec3(inout float currentSeed) {
    return vec3(randomDouble(currentSeed), randomDouble(currentSeed), randomDouble(currentSeed));
}

vec3 randomVec3(in float minVal, in float maxVal, inout float currentSeed) {
    return mix(vec3(minVal), vec3(maxVal), randomVec3(currentSeed));
}

vec3 randomUnitVec3(inout float currentSeed) {
    vec3 v = vec3(
        randomDouble(currentSeed) * 2.0 - 1.0,
        randomDouble(currentSeed) * 2.0 - 1.0,
        randomDouble(currentSeed) * 2.0 - 1.0
    );
    float lenSq = dot(v, v);
    if (lenSq == 0.0) return vec3(1.0, 0.0, 0.0);
    return v / sqrt(lenSq);
}

vec3 randomOnHemisphere(in vec3 normal, inout float currentSeed) {
    vec3 v = randomUnitVec3(currentSeed);
    return dot(v, normal) < 0.0 ? -v : v;
}

// Cosine-weighted hemisphere sampling (better for Lambertian + AO)
vec3 cosineWeightedHemisphere(in vec3 normal, inout float seed) {
    float u1 = randomDouble(seed);
    float u2 = randomDouble(seed);
    float r = sqrt(u2);
    float theta = 2.0 * PI * u1;
    float x = r * cos(theta);
    float y = r * sin(theta);
    float z = sqrt(1.0 - u2);
    // Build tangent frame from normal
    vec3 up = abs(normal.y) < 0.999 ? vec3(0.0, 1.0, 0.0) : vec3(1.0, 0.0, 0.0);
    vec3 tangent = normalize(cross(up, normal));
    vec3 bitangent = cross(normal, tangent);
    return normalize(tangent * x + bitangent * y + normal * z);
}

// ============================================================
// Intersection
// ============================================================
void intersectSphere(in Ray r, in vec3 sphereCenter, in float sphereRadius, inout HitRecord hitRecord) {
    if (hitRecord.isHit) return;
    vec3 oc = r.origin - sphereCenter;
    float a = dot(r.direction, r.direction);
    float b = dot(r.direction, oc);
    float c = dot(oc, oc) - sphereRadius * sphereRadius;
    float discriminant = b * b - c;
    if (discriminant < 0.0) return;
    float t = -b - sqrt(discriminant);
    if (t > 0.0) {
        hitRecord.isHit = true;
        hitRecord.t = t;
        hitRecord.hitPoint = r.origin + t * r.direction;
        hitRecord.normal = normalize(hitRecord.hitPoint - sphereCenter);
    }
}

// ============================================================
// Sphere getters (if-chain for WebGL 1.0 compatibility)
// ============================================================

// Geometry only — used in intersection loops
void getSphereGeom(const int idx, out vec3 center, out float radius) {
    if (idx == 0) { center = u_s0_center; radius = u_s0_radius; return; }
    if (idx == 1) { center = u_s1_center; radius = u_s1_radius; return; }
    if (idx == 2) { center = u_s2_center; radius = u_s2_radius; return; }
    if (idx == 3) { center = u_s3_center; radius = u_s3_radius; return; }
    if (idx == 4) { center = u_s4_center; radius = u_s4_radius; return; }
    if (idx == 5) { center = u_s5_center; radius = u_s5_radius; return; }
    if (idx == 6) { center = u_s6_center; radius = u_s6_radius; return; }
    if (idx == 7) { center = u_s7_center; radius = u_s7_radius; return; }
    if (idx == 8) { center = u_s8_center; radius = u_s8_radius; return; }
    center = u_s9_center; radius = u_s9_radius;
}

// Full material properties — called once after finding closest hit
void getSphereMat(const int idx,
                  out vec3 color, out int material,
                  out vec3 emission, out float emissionStrength,
                  out float ior, out float roughness,
                  out float specular, out float shininess) {
    if (idx == 0) { color=u_s0_color; material=u_s0_material; emission=u_s0_emission; emissionStrength=u_s0_emissionStrength; ior=u_s0_ior; roughness=u_s0_roughness; specular=u_s0_specular; shininess=u_s0_shininess; return; }
    if (idx == 1) { color=u_s1_color; material=u_s1_material; emission=u_s1_emission; emissionStrength=u_s1_emissionStrength; ior=u_s1_ior; roughness=u_s1_roughness; specular=u_s1_specular; shininess=u_s1_shininess; return; }
    if (idx == 2) { color=u_s2_color; material=u_s2_material; emission=u_s2_emission; emissionStrength=u_s2_emissionStrength; ior=u_s2_ior; roughness=u_s2_roughness; specular=u_s2_specular; shininess=u_s2_shininess; return; }
    if (idx == 3) { color=u_s3_color; material=u_s3_material; emission=u_s3_emission; emissionStrength=u_s3_emissionStrength; ior=u_s3_ior; roughness=u_s3_roughness; specular=u_s3_specular; shininess=u_s3_shininess; return; }
    if (idx == 4) { color=u_s4_color; material=u_s4_material; emission=u_s4_emission; emissionStrength=u_s4_emissionStrength; ior=u_s4_ior; roughness=u_s4_roughness; specular=u_s4_specular; shininess=u_s4_shininess; return; }
    if (idx == 5) { color=u_s5_color; material=u_s5_material; emission=u_s5_emission; emissionStrength=u_s5_emissionStrength; ior=u_s5_ior; roughness=u_s5_roughness; specular=u_s5_specular; shininess=u_s5_shininess; return; }
    if (idx == 6) { color=u_s6_color; material=u_s6_material; emission=u_s6_emission; emissionStrength=u_s6_emissionStrength; ior=u_s6_ior; roughness=u_s6_roughness; specular=u_s6_specular; shininess=u_s6_shininess; return; }
    if (idx == 7) { color=u_s7_color; material=u_s7_material; emission=u_s7_emission; emissionStrength=u_s7_emissionStrength; ior=u_s7_ior; roughness=u_s7_roughness; specular=u_s7_specular; shininess=u_s7_shininess; return; }
    if (idx == 8) { color=u_s8_color; material=u_s8_material; emission=u_s8_emission; emissionStrength=u_s8_emissionStrength; ior=u_s8_ior; roughness=u_s8_roughness; specular=u_s8_specular; shininess=u_s8_shininess; return; }
    color=u_s9_color; material=u_s9_material; emission=u_s9_emission; emissionStrength=u_s9_emissionStrength; ior=u_s9_ior; roughness=u_s9_roughness; specular=u_s9_specular; shininess=u_s9_shininess;
}

// ============================================================
// Light getter
// ============================================================
void getLight(const int idx,
              out int type, out vec3 direction, out vec3 position,
              out vec3 color, out float intensity, out float radius) {
    if (idx == 0) { type=u_l0_type; direction=u_l0_direction; position=u_l0_position; color=u_l0_color; intensity=u_l0_intensity; radius=u_l0_radius; return; }
    if (idx == 1) { type=u_l1_type; direction=u_l1_direction; position=u_l1_position; color=u_l1_color; intensity=u_l1_intensity; radius=u_l1_radius; return; }
    if (idx == 2) { type=u_l2_type; direction=u_l2_direction; position=u_l2_position; color=u_l2_color; intensity=u_l2_intensity; radius=u_l2_radius; return; }
    type=u_l3_type; direction=u_l3_direction; position=u_l3_position; color=u_l3_color; intensity=u_l3_intensity; radius=u_l3_radius;
}

// ============================================================
// Scene queries
// ============================================================

// Find closest hit (returns hitIndex == -1 if no hit)
void findClosestHit(in Ray r, out HitRecord closestHit, out int hitIndex) {
    closestHit = HitRecord(1e38, vec3(0.0), vec3(0.0), false);
    hitIndex = -1;
    for (int s = 0; s < MAX_SPHERES; s++) {
        if (s >= sphereCount) break;
        vec3 sc; float sr;
        getSphereGeom(s, sc, sr);
        HitRecord currentHit = HitRecord(0.0, vec3(0.0), vec3(0.0), false);
        intersectSphere(r, sc, sr, currentHit);
        if (currentHit.isHit && currentHit.t < closestHit.t) {
            closestHit = currentHit;
            hitIndex = s;
        }
    }
}

// Check if any geometry blocks within maxDist (early-exit for shadow/AO)
bool anyHitWithin(in Ray r, float maxDist) {
    for (int s = 0; s < MAX_SPHERES; s++) {
        if (s >= sphereCount) break;
        vec3 sc; float sr;
        getSphereGeom(s, sc, sr);
        HitRecord hit = HitRecord(0.0, vec3(0.0), vec3(0.0), false);
        intersectSphere(r, sc, sr, hit);
        if (hit.isHit && hit.t > 0.0 && hit.t < maxDist) return true;
    }
    return false;
}

// ============================================================
// Feature 3: Ambient Occlusion (Monte Carlo hemisphere visibility)
// ============================================================
float computeAO(in vec3 hitPoint, in vec3 normal, inout float seed) {
    if (aoStrength <= 0.0) return 1.0;
    float occlusion = 0.0;
    float effectiveRadius = max(aoRadius, 0.01);
    for (int i = 0; i < AO_SAMPLES; i++) {
        vec3 dir = cosineWeightedHemisphere(normal, seed);
        Ray aoRay = Ray(hitPoint + normal * 0.001, dir);
        if (anyHitWithin(aoRay, effectiveRadius)) {
            occlusion += 1.0;
        }
    }
    return 1.0 - (occlusion / float(AO_SAMPLES)) * aoStrength;
}

// ============================================================
// Feature 5: Soft shadow factor (jittered shadow rays)
// ============================================================
float computeShadowFactor(in vec3 hitPoint, in vec3 normal,
                          in vec3 toLight, in float maxDist,
                          in vec3 lightPos, in float lightRadius,
                          in int lightType, inout float seed) {
    if (lightRadius > 0.001) {
        // Soft shadows: multiple jittered rays toward the light area
        float visible = 0.0;
        for (int s = 0; s < SOFT_SHADOW_SAMPLES; s++) {
            vec3 jitter = (randomVec3(seed) * 2.0 - 1.0) * lightRadius;
            vec3 jitteredDir;
            float jitteredDist;
            if (lightType == 1) {
                // Point light: jitter the position
                vec3 jTarget = lightPos + jitter;
                vec3 jVec = jTarget - hitPoint;
                jitteredDist = length(jVec);
                jitteredDir = jVec / jitteredDist;
            } else {
                // Directional: jitter the direction slightly
                jitteredDir = normalize(toLight + jitter * 0.1);
                jitteredDist = 1e38;
            }
            Ray shadowRay = Ray(hitPoint + normal * 0.001, jitteredDir);
            if (!anyHitWithin(shadowRay, jitteredDist)) {
                visible += 1.0;
            }
        }
        return visible / float(SOFT_SHADOW_SAMPLES);
    } else {
        // Hard shadow: single ray
        Ray shadowRay = Ray(hitPoint + normal * 0.001, toLight);
        return anyHitWithin(shadowRay, maxDist) ? 0.0 : 1.0;
    }
}

// ============================================================
// Feature 7: Dielectric scattering (Snell + Schlick)
// ============================================================
void scatterDielectric(in Ray currentRay, in HitRecord hit, in float ior,
                       inout float seed, out Ray scattered, out vec3 attenuation) {
    vec3 unitDir = normalize(currentRay.direction);
    vec3 normal;
    float etaRatio;

    if (dot(unitDir, hit.normal) > 0.0) {
        // Exiting the medium
        normal = -hit.normal;
        etaRatio = ior; // glass -> air
    } else {
        // Entering the medium
        normal = hit.normal;
        etaRatio = 1.0 / ior; // air -> glass
    }

    float cosTheta = min(dot(-unitDir, normal), 1.0);
    float sinTheta2 = etaRatio * etaRatio * (1.0 - cosTheta * cosTheta);
    bool cannotRefract = sinTheta2 > 1.0;

    // Schlick's approximation for Fresnel reflectance
    float r0 = (1.0 - etaRatio) / (1.0 + etaRatio);
    r0 = r0 * r0;
    float reflectance = r0 + (1.0 - r0) * pow(1.0 - cosTheta, 5.0);

    vec3 direction;
    if (cannotRefract || reflectance > randomDouble(seed)) {
        // Total internal reflection or Fresnel reflection
        direction = reflect(unitDir, normal);
        scattered = Ray(hit.hitPoint + normal * 0.001, direction);
    } else {
        // Refract (Snell's law)
        direction = refract(unitDir, normal, etaRatio);
        scattered = Ray(hit.hitPoint - normal * 0.001, direction);
    }

    attenuation = vec3(1.0); // clear glass; tinted glass would use a color here
}

// ============================================================
// Main ray tracing loop — all features integrated
// ============================================================
vec3 colorRayIterative(in Ray initialRay, inout float rngSeed) {
    vec3 outColor = vec3(0.0);
    vec3 throughput = vec3(1.0);
    Ray currentRay = initialRay;

    for (int depth = 0; depth < MAX_DEPTH; depth++) {
        HitRecord closestHit;
        int hitIndex;
        findClosestHit(currentRay, closestHit, hitIndex);

        if (hitIndex == -1) {
            // Sky gradient
            vec3 unitDir = normalize(currentRay.direction);
            float a = 0.5 * (unitDir.y + 1.0);
            outColor += throughput * mix(vec3(0.3, 0.5, 0.8), vec3(1.0), a);
            break;
        }

        // Fetch full material properties for the hit sphere
        vec3 hitColor; int hitMat;
        vec3 hitEmission; float hitEmStr;
        float hitIOR; float hitRough;
        float hitSpec; float hitShine;
        getSphereMat(hitIndex, hitColor, hitMat, hitEmission, hitEmStr,
                     hitIOR, hitRough, hitSpec, hitShine);

        // === Feature 4: Emissive contribution ===
        // Add emission regardless of material type (non-emissive have strength 0)
        outColor += throughput * hitEmission * hitEmStr;

        // Pure emissive (material == 2): terminate after adding emission
        if (hitMat == 2) {
            break;
        }

        // === Feature 3: Ambient Occlusion (first 3 bounces only for perf) ===
        float ao = 1.0;
        if (depth < 3) {
            ao = computeAO(closestHit.hitPoint, closestHit.normal, rngSeed);
        }

        // Ambient term (small indirect light approximation)
        outColor += throughput * hitColor * 0.03 * ao;

        // View direction for specular
        vec3 V = normalize(cameraPosition - closestHit.hitPoint);

        // === Direct lighting with Features 1, 2, 5, 6 ===
        for (int li = 0; li < MAX_LIGHTS; li++) {
            if (li >= lightCount) break;

            int lType; vec3 lDir; vec3 lPos; vec3 lCol; float lInt; float lRad;
            getLight(li, lType, lDir, lPos, lCol, lInt, lRad);

            // Compute light direction, attenuation, shadow distance
            vec3 toLight;
            float attIntensity;
            float maxShadowDist;

            if (lType == 1) {
                // Feature 2: Point light
                vec3 dirToLight = lPos - closestHit.hitPoint;
                float dLight = length(dirToLight);
                toLight = dirToLight / dLight;
                attIntensity = lInt / (1.0 + k_linear * dLight + k_quadratic * dLight * dLight);
                maxShadowDist = dLight;
            } else {
                // Directional light
                toLight = normalize(-lDir);
                attIntensity = lInt;
                maxShadowDist = 1e38;
            }

            float NdotL = max(dot(closestHit.normal, toLight), 0.0);
            if (NdotL <= 0.0) continue;

            // Feature 1 + 5: Shadow rays (hard or soft)
            float shadow = computeShadowFactor(
                closestHit.hitPoint, closestHit.normal,
                toLight, maxShadowDist,
                lPos, lRad, lType, rngSeed
            );

            if (shadow > 0.0) {
                // Diffuse (Lambertian)
                vec3 diffuse = hitColor * lCol * attIntensity * NdotL;

                // Feature 6: Blinn-Phong specular highlights
                vec3 specular = vec3(0.0);
                if (hitSpec > 0.0 && hitShine > 0.0) {
                    vec3 H = normalize(toLight + V);
                    float NdotH = max(dot(closestHit.normal, H), 0.0);
                    // Energy-conserving normalization factor
                    float normFactor = (hitShine + 2.0) / (2.0 * PI);
                    specular = lCol * attIntensity * hitSpec * normFactor * pow(NdotH, hitShine);
                }

                outColor += throughput * (diffuse + specular) * shadow * ao;
            }
        }

        // === Scatter ray for next bounce ===
        Ray scattered;
        vec3 attenuation;

        if (hitMat == 3) {
            // Feature 7: Dielectric (glass) — refraction / reflection
            scatterDielectric(currentRay, closestHit, hitIOR, rngSeed, scattered, attenuation);
            throughput *= attenuation * hitColor;
        } else if (hitMat == 1) {
            // Metal — specular reflection with optional roughness (fuzz)
            vec3 reflected = reflect(normalize(currentRay.direction), closestHit.normal);
            if (hitRough > 0.0) {
                reflected = normalize(reflected + randomUnitVec3(rngSeed) * hitRough);
            }
            scattered = Ray(closestHit.hitPoint + closestHit.normal * 0.001, reflected);
            attenuation = hitColor;
            throughput *= attenuation;
        } else {
            // Lambertian — cosine-weighted hemisphere scatter
            vec3 scatterDir = cosineWeightedHemisphere(closestHit.normal, rngSeed);
            scattered = Ray(closestHit.hitPoint + closestHit.normal * 0.001, scatterDir);
            attenuation = hitColor;
            throughput *= attenuation;
        }

        currentRay = scattered;

        // Russian roulette termination for deep bounces
        if (depth > 4) {
            float p = max(throughput.x, max(throughput.y, throughput.z));
            if (randomDouble(rngSeed) > p) break;
            throughput /= p;
        }
    }

    return outColor;
}

// ============================================================
// Feature 8: Tone Mapping + Gamma Correction
// ============================================================

// Reinhard: C / (1 + C)
vec3 tonemapReinhard(vec3 c) {
    return c / (1.0 + c);
}

// ACES filmic: widely used in games and film
vec3 tonemapACES(vec3 c) {
    return (c * (2.51 * c + 0.03)) / (c * (2.43 * c + 0.59) + 0.14);
}

// Gamma correction: compensate for monitor nonlinearity
vec3 gammaCorrect(vec3 c) {
    return pow(max(c, 0.0), vec3(1.0 / 2.2));
}

// ============================================================
// Main
// ============================================================
void main() {
    float seed = gl_FragCoord.x * 0.123 + gl_FragCoord.y * 0.456 + time;

    // Reconstruct world-space ray from screen coordinates
    vec2 ndc = fragTexCoord * 2.0 - 1.0;
    vec4 clipPos = vec4(ndc, -1.0, 1.0);
    vec4 worldPos4 = invViewProj * clipPos;
    vec3 worldPos = worldPos4.xyz / worldPos4.w;

    // Multi-sample anti-aliasing
    const int samples_per_pixel = 4;
    vec3 outputColor = vec3(0.0);
    for (int i = 0; i < samples_per_pixel; i++) {
        vec3 jitter = randomVec3(-0.000000001, 0.0000000001, seed);
        Ray sampleRay = Ray(cameraPosition, normalize(worldPos - cameraPosition + jitter));
        outputColor += colorRayIterative(sampleRay, seed);
    }
    outputColor /= float(samples_per_pixel);

    // Feature 8: Tone mapping pipeline
    //   1. Raw HDR from ray tracing → outputColor
    //   2. Tone map (Reinhard or ACES)
    //   3. Clamp to [0, 1]
    //   4. Gamma correct
    if (toneMapMode == 1) {
        outputColor = tonemapReinhard(outputColor);
    } else if (toneMapMode == 2) {
        outputColor = tonemapACES(outputColor);
    }
    outputColor = clamp(outputColor, 0.0, 1.0);
    outputColor = gammaCorrect(outputColor);

    gl_FragColor = vec4(outputColor, 1.0);
}
