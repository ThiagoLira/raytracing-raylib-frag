// GLSL ES 1.00 (WebGL 1.0)
precision highp float;
precision highp int;
#define MAX_DEPTH 32 // compile-time constant
#define MAX_SPHERES 4
varying vec2 fragTexCoord;
uniform sampler2D texture0; // not used, kept for compatibility

uniform vec3 cameraPosition;
uniform mat4 invViewProj;

uniform int sphereCount;

// Pass spheres as individual uniforms to avoid dynamic indexing restrictions in WebGL 1.0
uniform vec3  u_s0_center; uniform float u_s0_radius; uniform vec3  u_s0_color; uniform int u_s0_material;
uniform vec3  u_s1_center; uniform float u_s1_radius; uniform vec3  u_s1_color; uniform int u_s1_material;
uniform vec3  u_s2_center; uniform float u_s2_radius; uniform vec3  u_s2_color; uniform int u_s2_material;
uniform vec3  u_s3_center; uniform float u_s3_radius; uniform vec3  u_s3_color; uniform int u_s3_material;

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

struct DirectionalLight {
    vec3 direction;
    vec3 color;
    float intensity;
};

DirectionalLight dirlight1 = DirectionalLight(vec3(0.0, 0.0, -1.0), vec3(0.6, 0.05, 0.05), 0.9);

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

vec3 clampColor(vec3 color) {
    return clamp(color, 0.0, 1.0);
}

void getSphere(const int idx, out vec3 center, out float radius, out vec3 color, out int material) {
    if (idx == 0) { center = u_s0_center; radius = u_s0_radius; color = u_s0_color; material = u_s0_material; return; }
    if (idx == 1) { center = u_s1_center; radius = u_s1_radius; color = u_s1_color; material = u_s1_material; return; }
    if (idx == 2) { center = u_s2_center; radius = u_s2_radius; color = u_s2_color; material = u_s2_material; return; }
    /* idx == 3 or default */ center = u_s3_center; radius = u_s3_radius; color = u_s3_color; material = u_s3_material; return;
}

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

vec3 colorRayIterative(in Ray initialRay, out vec3 outColor, inout float rngSeed) {
    outColor = vec3(0.0);
    vec3 accumulatedColor = vec3(1.0);
    Ray currentRay = initialRay;
    for (int depth = 0; depth < MAX_DEPTH; depth++) {
        HitRecord closestHitRecord = HitRecord(1e38, vec3(0.0), vec3(0.0), false);
        int hitSphereIndex = -1;
        vec3 hitColor = vec3(1.0);
        int hitMaterial = 0;

        for (int s = 0; s < MAX_SPHERES; s++) {
            if (s >= sphereCount) break;
            vec3 sc; float sr; vec3 scol; int smat;
            getSphere(s, sc, sr, scol, smat);
            HitRecord currentSphereHitRecord = HitRecord(0.0, vec3(0.0), vec3(0.0), false);
            intersectSphere(currentRay, sc, sr, currentSphereHitRecord);
            if (currentSphereHitRecord.isHit && currentSphereHitRecord.t < closestHitRecord.t) {
                closestHitRecord = currentSphereHitRecord;
                hitSphereIndex = s;
                hitColor = scol;
                hitMaterial = smat;
            }
        }

        if (hitSphereIndex != -1) {
            if (hitMaterial == 1) {
                vec3 reflectedDir = reflect(currentRay.direction, closestHitRecord.normal);
                currentRay = Ray(closestHitRecord.hitPoint + closestHitRecord.normal * 0.0001, reflectedDir);
                outColor = clampColor(outColor + accumulatedColor * hitColor);
            } else {
                vec3 randomDir = randomOnHemisphere(closestHitRecord.normal, rngSeed);
                outColor = clampColor(outColor + accumulatedColor * hitColor);
                currentRay = Ray(closestHitRecord.hitPoint + closestHitRecord.normal * 0.0001, randomDir);
            }
            accumulatedColor *= hitColor;
        } else {
            vec3 unitDir = normalize(currentRay.direction);
            float a = 0.5 * (unitDir.y + 1.0);
            outColor += accumulatedColor * mix(vec3(0.3, 0.5, 0.8), vec3(1.0), a);
            break;
        }
    }

    vec3 lightDir = normalize(dirlight1.direction);
    float lightIntensity = max(dot(lightDir, normalize(currentRay.direction)), dirlight1.intensity);
    outColor += lightIntensity * dirlight1.color * accumulatedColor;
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


