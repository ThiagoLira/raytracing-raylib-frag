// GLSL ES 1.00 (WebGL 1.0)
precision highp float;
precision highp int;
#define MAX_DEPTH 32
#define MAX_SPHERES 10
#define MAX_LIGHTS 4
varying vec2 fragTexCoord;
uniform sampler2D texture0;

uniform vec3 cameraPosition;
uniform mat4 invViewProj;

uniform int sphereCount;
uniform int lightCount;

// === Sphere uniforms (flat, WebGL 1.0) ===
uniform vec3  u_s0_center; uniform float u_s0_radius; uniform vec3  u_s0_color; uniform int u_s0_material;
uniform vec3  u_s1_center; uniform float u_s1_radius; uniform vec3  u_s1_color; uniform int u_s1_material;
uniform vec3  u_s2_center; uniform float u_s2_radius; uniform vec3  u_s2_color; uniform int u_s2_material;
uniform vec3  u_s3_center; uniform float u_s3_radius; uniform vec3  u_s3_color; uniform int u_s3_material;
uniform vec3  u_s4_center; uniform float u_s4_radius; uniform vec3  u_s4_color; uniform int u_s4_material;
uniform vec3  u_s5_center; uniform float u_s5_radius; uniform vec3  u_s5_color; uniform int u_s5_material;
uniform vec3  u_s6_center; uniform float u_s6_radius; uniform vec3  u_s6_color; uniform int u_s6_material;
uniform vec3  u_s7_center; uniform float u_s7_radius; uniform vec3  u_s7_color; uniform int u_s7_material;
uniform vec3  u_s8_center; uniform float u_s8_radius; uniform vec3  u_s8_color; uniform int u_s8_material;
uniform vec3  u_s9_center; uniform float u_s9_radius; uniform vec3  u_s9_color; uniform int u_s9_material;

// === Light uniforms (flat, WebGL 1.0) ===
uniform vec3  u_l0_direction; uniform vec3  u_l0_color; uniform float u_l0_intensity;
uniform vec3  u_l1_direction; uniform vec3  u_l1_color; uniform float u_l1_intensity;
uniform vec3  u_l2_direction; uniform vec3  u_l2_color; uniform float u_l2_intensity;
uniform vec3  u_l3_direction; uniform vec3  u_l3_color; uniform float u_l3_intensity;

uniform float time;

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

// === RNG ===

float randomDouble(inout float currentSeed) {
    currentSeed = fract(sin(currentSeed * 12.9898) * 43758.5453);
    return currentSeed;
}

vec3 randomVec3(inout float currentSeed) {
    float rX = randomDouble(currentSeed);
    float rY = randomDouble(currentSeed);
    float rZ = randomDouble(currentSeed);
    return vec3(rX, rY, rZ);
}

vec3 randomVec3(in float minVal, in float maxVal, inout float currentSeed) {
    float rX = randomDouble(currentSeed);
    float rY = randomDouble(currentSeed);
    float rZ = randomDouble(currentSeed);
    return mix(vec3(minVal), vec3(maxVal), vec3(rX, rY, rZ));
}

vec3 randomUnitVec3(inout float currentSeed) {
    float rX = randomDouble(currentSeed) * 2.0 - 1.0;
    float rY = randomDouble(currentSeed) * 2.0 - 1.0;
    float rZ = randomDouble(currentSeed) * 2.0 - 1.0;
    vec3 v = vec3(rX, rY, rZ);
    float lenSq = dot(v, v);
    if (lenSq == 0.0) return vec3(1.0, 0.0, 0.0);
    return v / sqrt(lenSq);
}

vec3 randomOnHemisphere(in vec3 normal, inout float currentSeed) {
    vec3 unitVec = randomUnitVec3(currentSeed);
    if (dot(unitVec, normal) < 0.0) unitVec = -unitVec;
    return unitVec;
}

// === Intersection ===

void intersectSphere(in Ray r, in vec3 sphereCenter, in float sphereRadius, inout HitRecord hitRecord) {
    if (hitRecord.isHit) return;
    vec3 O = r.origin;
    vec3 D = r.direction;
    vec3 oc = O - sphereCenter;
    float a = dot(D, D);
    float b = dot(D, oc);
    float c = dot(oc, oc) - sphereRadius * sphereRadius;
    float discriminant = b * b - c;
    if (discriminant < 0.0) return;
    float t = (-b - sqrt(discriminant));
    if (t > 0.0) {
        hitRecord.isHit = true;
        hitRecord.t = t;
        hitRecord.hitPoint = r.origin + t * D;
        hitRecord.normal = normalize(hitRecord.hitPoint - sphereCenter);
    }
}

void getSphere(const int idx, out vec3 center, out float radius, out vec3 color, out int material) {
    if (idx == 0) { center = u_s0_center; radius = u_s0_radius; color = u_s0_color; material = u_s0_material; return; }
    if (idx == 1) { center = u_s1_center; radius = u_s1_radius; color = u_s1_color; material = u_s1_material; return; }
    if (idx == 2) { center = u_s2_center; radius = u_s2_radius; color = u_s2_color; material = u_s2_material; return; }
    if (idx == 3) { center = u_s3_center; radius = u_s3_radius; color = u_s3_color; material = u_s3_material; return; }
    if (idx == 4) { center = u_s4_center; radius = u_s4_radius; color = u_s4_color; material = u_s4_material; return; }
    if (idx == 5) { center = u_s5_center; radius = u_s5_radius; color = u_s5_color; material = u_s5_material; return; }
    if (idx == 6) { center = u_s6_center; radius = u_s6_radius; color = u_s6_color; material = u_s6_material; return; }
    if (idx == 7) { center = u_s7_center; radius = u_s7_radius; color = u_s7_color; material = u_s7_material; return; }
    if (idx == 8) { center = u_s8_center; radius = u_s8_radius; color = u_s8_color; material = u_s8_material; return; }
    /* idx == 9 */ center = u_s9_center; radius = u_s9_radius; color = u_s9_color; material = u_s9_material; return;
}

// === Lighting ===

void getLight(const int idx, out vec3 direction, out vec3 color, out float intensity) {
    if (idx == 0) { direction = u_l0_direction; color = u_l0_color; intensity = u_l0_intensity; return; }
    if (idx == 1) { direction = u_l1_direction; color = u_l1_color; intensity = u_l1_intensity; return; }
    if (idx == 2) { direction = u_l2_direction; color = u_l2_color; intensity = u_l2_intensity; return; }
    /* idx == 3 */ direction = u_l3_direction; color = u_l3_color; intensity = u_l3_intensity; return;
}

// === Materials ===

void scatterRay(in int material, in Ray currentRay, in HitRecord hit, inout float rngSeed, out Ray scattered) {
    if (material == 1) {
        // Metal: reflect
        vec3 reflectedDir = reflect(currentRay.direction, hit.normal);
        scattered = Ray(hit.hitPoint + hit.normal * 0.0001, reflectedDir);
    } else {
        // Lambertian: random hemisphere scatter
        vec3 randomDir = randomOnHemisphere(hit.normal, rngSeed);
        scattered = Ray(hit.hitPoint + hit.normal * 0.0001, randomDir);
    }
}

// === Tracing ===

void findClosestHit(in Ray r, out HitRecord closestHit, out int hitIndex, out vec3 hitColor, out int hitMaterial) {
    closestHit = HitRecord(1e38, vec3(0.0), vec3(0.0), false);
    hitIndex = -1;
    hitColor = vec3(1.0);
    hitMaterial = 0;

    for (int s = 0; s < MAX_SPHERES; s++) {
        if (s >= sphereCount) break;
        vec3 sc; float sr; vec3 scol; int smat;
        getSphere(s, sc, sr, scol, smat);
        HitRecord currentHit = HitRecord(0.0, vec3(0.0), vec3(0.0), false);
        intersectSphere(r, sc, sr, currentHit);
        if (currentHit.isHit && currentHit.t < closestHit.t) {
            closestHit = currentHit;
            hitIndex = s;
            hitColor = scol;
            hitMaterial = smat;
        }
    }
}

vec3 colorRayIterative(in Ray initialRay, out vec3 outColor, inout float rngSeed) {
    outColor = vec3(0.0);
    vec3 accumulatedColor = vec3(1.0);
    Ray currentRay = initialRay;

    for (int depth = 0; depth < MAX_DEPTH; depth++) {
        HitRecord closestHit;
        int hitIndex;
        vec3 hitColor;
        int hitMaterial;
        findClosestHit(currentRay, closestHit, hitIndex, hitColor, hitMaterial);

        if (hitIndex != -1) {
            outColor += accumulatedColor * hitColor;
            accumulatedColor *= hitColor;

            // Apply directional lights at this hit
            for (int li = 0; li < MAX_LIGHTS; li++) {
                if (li >= lightCount) break;
                vec3 lDir; vec3 lCol; float lInt;
                getLight(li, lDir, lCol, lInt);
                vec3 lightDir = normalize(lDir);
                float NdotL = max(dot(closestHit.normal, -lightDir), 0.0);
                // Shadow test
                Ray shadowRay = Ray(closestHit.hitPoint + closestHit.normal * 0.0001, -lightDir);
                HitRecord shadowHit;
                int si; vec3 sc; int sm;
                findClosestHit(shadowRay, shadowHit, si, sc, sm);
                if (si == -1) {
                    outColor += accumulatedColor * lCol * lInt * NdotL;
                }
            }

            // Scatter for next bounce
            Ray scattered;
            scatterRay(hitMaterial, currentRay, closestHit, rngSeed, scattered);
            currentRay = scattered;
        } else {
            // Sky
            vec3 unitDir = normalize(currentRay.direction);
            float a = 0.5 * (unitDir.y + 1.0);
            outColor += accumulatedColor * mix(vec3(0.3, 0.5, 0.8), vec3(1.0), a);
            break;
        }
    }

    return outColor;
}

void main() {
    float seed = gl_FragCoord.x * 0.123 + gl_FragCoord.y * 0.456 + time;
    vec2 ndc = fragTexCoord * 2.0 - 1.0;
    vec4 clipPos = vec4(ndc, -1.0, 1.0);
    vec4 worldPos4 = invViewProj * clipPos;
    vec3 worldPos = worldPos4.xyz / worldPos4.w;

    const int samples_per_pixel = 8;
    vec3 outputColor = vec3(0.0);
    for (int i = 0; i < samples_per_pixel; i++) {
        Ray sampleRay = Ray(cameraPosition, normalize(worldPos - cameraPosition + randomVec3(-0.000000001, 0.0000000001, seed)));
        vec3 sampleColor = vec3(0.0);
        colorRayIterative(sampleRay, sampleColor, seed);
        outputColor += sampleColor;
    }
    outputColor /= float(samples_per_pixel);
    gl_FragColor = vec4(outputColor, 1.0);
}
