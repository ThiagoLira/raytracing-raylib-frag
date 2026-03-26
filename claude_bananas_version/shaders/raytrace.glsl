// NOTE: #version directive is prepended by C code at load time
// Desktop: #version 330 | Web: #version 300 es

#ifdef GL_ES
precision highp float;
precision highp int;
#endif

#define MAX_DEPTH 8
#define MAX_PRIMS 64
#define MAX_LIGHTS 8
#define AO_SAMPLES 4
#define SOFT_SHADOW_SAMPLES 4
#define PI 3.14159265359
#define EPSILON 0.001

// Primitive types
#define PRIM_SPHERE   0
#define PRIM_QUAD     1
#define PRIM_TRIANGLE 2

// Scene data texture layout (8 pixels wide, RGBA32F):
// Each primitive = 1 ROW, 8 columns:
//   Col 0: [primType, 0, 0, 0]
//   Col 1: [color.rgb, materialType]
//   Col 2: [emission.rgb, emissionStrength]
//   Col 3: [ior, roughness, specular, shininess]
//   Col 4: [geom0] — type-specific
//   Col 5: [geom1]
//   Col 6: [geom2]
//   Col 7: [boundingSphere: center.xyz, radius]
//
// Sphere geom:  col4 = [center.xyz, radius]
// Quad geom:    col4 = [Q.xyz, 0], col5 = [u.xyz, 0], col6 = [v.xyz, 0]
// Triangle geom: col4 = [A.xyz, 0], col5 = [B.xyz, 0], col6 = [C.xyz, 0]
//
// Light j at row (LIGHT_ROW_BASE + j):
//   Col 0: [type, direction.xyz]
//   Col 1: [position.xyz, intensity]
//   Col 2: [color.rgb, radius]

#define LIGHT_ROW_BASE MAX_PRIMS

in vec2 fragTexCoord;
out vec4 finalColor;

uniform sampler2D texture0;
uniform sampler2D sceneData;
uniform sampler2D accumTexture;

uniform vec3 cameraPosition;
uniform mat4 invViewProj;
uniform int primCount;
uniform int lightCount;
uniform int emissiveCount;
uniform int emissiveIndices[16]; // indices of emissive primitives (max 16)
uniform float k_linear;
uniform float k_quadratic;
uniform float aoRadius;
uniform float aoStrength;
uniform float time;
uniform int frameCount;
uniform vec2 resolution;
uniform int samplesPerFrame; // SPP per frame (1-16)
uniform sampler2D envMap;
uniform int useEnvMap;       // 0=sky gradient, 1=HDR env map, 2=procedural sky
uniform float envIntensity;
uniform float envRotation;

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
// Scene data access via texelFetch (8-wide horizontal layout)
// ============================================================
vec4 sceneTexel(int row, int col) {
    return texelFetch(sceneData, ivec2(col, row), 0);
}

void getPrimMat(int idx,
                out vec3 color, out int material,
                out vec3 emission, out float emissionStrength,
                out float ior, out float roughness,
                out float specular, out float shininess) {
    vec4 d1 = sceneTexel(idx, 1);
    vec4 d2 = sceneTexel(idx, 2);
    vec4 d3 = sceneTexel(idx, 3);
    color = d1.xyz;
    material = int(d1.w + 0.5);
    emission = d2.xyz;
    emissionStrength = d2.w;
    ior = d3.x;
    roughness = d3.y;
    specular = d3.z;
    shininess = d3.w;
}

void getLight(int idx,
              out int type, out vec3 direction, out vec3 position,
              out vec3 color, out float intensity, out float radius) {
    int row = LIGHT_ROW_BASE + idx;
    vec4 d0 = sceneTexel(row, 0);
    vec4 d1 = sceneTexel(row, 1);
    vec4 d2 = sceneTexel(row, 2);
    type = int(d0.x + 0.5);
    direction = d0.yzw;
    position = d1.xyz;
    intensity = d1.w;
    color = d2.xyz;
    radius = d2.w;
}

// ============================================================
// RNG — PCG hash
// ============================================================
uint rngState;

uint pcgHash(uint v) {
    uint state = v * 747796405u + 2891336453u;
    uint word = ((state >> ((state >> 28u) + 4u)) ^ state) * 277803737u;
    return (word >> 22u) ^ word;
}

float randomDouble() {
    rngState = pcgHash(rngState);
    return float(rngState) / 4294967295.0;
}

vec3 randomVec3() {
    return vec3(randomDouble(), randomDouble(), randomDouble());
}

vec3 randomUnitVec3() {
    vec3 rv = vec3(
        randomDouble() * 2.0 - 1.0,
        randomDouble() * 2.0 - 1.0,
        randomDouble() * 2.0 - 1.0
    );
    float lenSq = dot(rv, rv);
    if (lenSq < 0.0001) return vec3(1.0, 0.0, 0.0);
    return rv / sqrt(lenSq);
}

vec3 cosineWeightedHemisphere(vec3 normal) {
    float u1 = randomDouble();
    float u2 = randomDouble();
    float r = sqrt(u2);
    float theta = 2.0 * PI * u1;
    float x = r * cos(theta);
    float y = r * sin(theta);
    float z = sqrt(1.0 - u2);
    vec3 up = abs(normal.y) < 0.999 ? vec3(0.0, 1.0, 0.0) : vec3(1.0, 0.0, 0.0);
    vec3 tangent = normalize(cross(up, normal));
    vec3 bitangent = cross(normal, tangent);
    return normalize(tangent * x + bitangent * y + normal * z);
}

// ============================================================
// Intersection routines
// ============================================================

// Sphere: analytic ray-sphere (half_b optimization, single sqrt)
bool intersectSphere(in Ray r, in vec3 center, in float radius,
                     float tMax, out float tHit, out vec3 hitNormal) {
    vec3 oc = r.origin - center;
    float b = dot(r.direction, oc);
    float c = dot(oc, oc) - radius * radius;
    float disc = b * b - c;
    if (disc < 0.0) return false;
    float sqrtDisc = sqrt(disc);
    float t = -b - sqrtDisc;
    if (t < EPSILON || t > tMax) {
        t = -b + sqrtDisc;
        if (t < EPSILON || t > tMax) return false;
    }
    tHit = t;
    hitNormal = (oc + t * r.direction) / radius; // cheaper than normalize
    return true;
}

// Quad: point Q, edge vectors u, v (from Shirley Book 2)
bool intersectQuad(in Ray r, in vec3 Q, in vec3 u, in vec3 v,
                   float tMax, out float tHit, out vec3 hitNormal) {
    vec3 n = cross(u, v);
    float nLen = length(n);
    if (nLen < 1e-8) return false;
    vec3 normal = n / nLen;
    float denom = dot(normal, r.direction);
    if (abs(denom) < 1e-8) return false; // parallel

    float t = dot(Q - r.origin, normal) / denom;
    if (t < EPSILON || t > tMax) return false;

    vec3 hitPt = r.origin + t * r.direction;
    vec3 p = hitPt - Q;
    vec3 w = n / dot(n, n);
    float alpha = dot(cross(p, v), w);
    float beta = dot(cross(u, p), w);

    if (alpha < 0.0 || alpha > 1.0 || beta < 0.0 || beta > 1.0) return false;

    tHit = t;
    // Normal faces against the ray
    hitNormal = (denom < 0.0) ? normal : -normal;
    return true;
}

// Triangle: Moller-Trumbore
bool intersectTriangle(in Ray r, in vec3 A, in vec3 B, in vec3 C,
                       float tMax, out float tHit, out vec3 hitNormal) {
    vec3 E1 = B - A;
    vec3 E2 = C - A;
    vec3 P = cross(r.direction, E2);
    float det = dot(E1, P);
    if (abs(det) < 1e-8) return false;

    float invDet = 1.0 / det;
    vec3 T = r.origin - A;
    float u = dot(T, P) * invDet;
    if (u < 0.0 || u > 1.0) return false;

    vec3 QV = cross(T, E1);
    float vv = dot(r.direction, QV) * invDet;
    if (vv < 0.0 || u + vv > 1.0) return false;

    float t = dot(E2, QV) * invDet;
    if (t < EPSILON || t > tMax) return false;

    tHit = t;
    vec3 normal = normalize(cross(E1, E2));
    hitNormal = (det > 0.0) ? normal : -normal; // face against ray
    return true;
}

// ============================================================
// Unified scene trace (closest-hit and any-hit in one function)
// ============================================================

// Quick bounding sphere rejection (no sqrt — uses discriminant sign only)
bool rayMissesBounds(in Ray r, vec3 center, float radius, float maxDist) {
    vec3 oc = r.origin - center;
    float b = dot(r.direction, oc);
    float c = dot(oc, oc) - radius * radius;
    // If discriminant < 0, ray misses entirely
    if (b * b - c < 0.0) return true;
    // If sphere is entirely behind ray origin (closest point is behind us)
    if (b > 0.0 && c > 0.0) return true;
    return false;
}

// Closest-hit: finds nearest intersection (for primary/scatter rays)
void findClosestHit(in Ray r, out HitRecord closestHit, out int hitIndex) {
    closestHit = HitRecord(1e38, vec3(0.0), vec3(0.0), false);
    hitIndex = -1;
    float tBest = 1e38;
    int count = min(primCount, MAX_PRIMS);

    for (int i = 0; i < count; i++) {
        int ptype = int(sceneTexel(i, 0).x + 0.5);
        vec4 g0 = sceneTexel(i, 4);
        float tHit;
        vec3 hitN;
        bool hit = false;

        if (ptype == PRIM_SPHERE) {
            hit = intersectSphere(r, g0.xyz, g0.w, tBest, tHit, hitN);
        } else {
            vec4 g1 = sceneTexel(i, 5);
            vec4 g2 = sceneTexel(i, 6);
            if (ptype == PRIM_QUAD) {
                hit = intersectQuad(r, g0.xyz, g1.xyz, g2.xyz, tBest, tHit, hitN);
            } else {
                hit = intersectTriangle(r, g0.xyz, g1.xyz, g2.xyz, tBest, tHit, hitN);
            }
        }

        if (hit && tHit < tBest) {
            tBest = tHit;
            closestHit.t = tHit;
            closestHit.hitPoint = r.origin + tHit * r.direction;
            closestHit.normal = hitN;
            closestHit.isHit = true;
            hitIndex = i;
        }
    }
}

// Any-hit: returns immediately on first intersection (for shadow/AO)
bool anyHitWithin(in Ray r, float maxDist) {
    int count = min(primCount, MAX_PRIMS);
    for (int i = 0; i < count; i++) {
        int ptype = int(sceneTexel(i, 0).x + 0.5);
        vec4 g0 = sceneTexel(i, 4);
        float tHit;
        vec3 hitN;

        if (ptype == PRIM_SPHERE) {
            if (intersectSphere(r, g0.xyz, g0.w, maxDist, tHit, hitN)) return true;
        } else {
            vec4 bs = sceneTexel(i, 7);
            if (rayMissesBounds(r, bs.xyz, bs.w, maxDist)) continue;
            vec4 g1 = sceneTexel(i, 5);
            vec4 g2 = sceneTexel(i, 6);
            if (ptype == PRIM_QUAD) {
                if (intersectQuad(r, g0.xyz, g1.xyz, g2.xyz, maxDist, tHit, hitN)) return true;
            } else {
                if (intersectTriangle(r, g0.xyz, g1.xyz, g2.xyz, maxDist, tHit, hitN)) return true;
            }
        }
    }
    return false;
}

// ============================================================
// Ambient Occlusion
// ============================================================
float computeAO(in vec3 hitPoint, in vec3 normal) {
    if (aoStrength <= 0.0) return 1.0;
    float occlusion = 0.0;
    float effectiveRadius = max(aoRadius, 0.01);
    for (int i = 0; i < AO_SAMPLES; i++) {
        vec3 dir = cosineWeightedHemisphere(normal);
        Ray aoRay = Ray(hitPoint + normal * EPSILON, dir);
        if (anyHitWithin(aoRay, effectiveRadius)) {
            occlusion += 1.0;
        }
    }
    return 1.0 - (occlusion / float(AO_SAMPLES)) * aoStrength;
}

// ============================================================
// Soft shadow factor
// ============================================================
float computeShadowFactor(in vec3 hitPoint, in vec3 normal,
                          in vec3 toLight, in float maxDist,
                          in vec3 lightPos, in float lightRadius,
                          in int lightType) {
    if (lightRadius > 0.001) {
        float visible = 0.0;
        for (int s = 0; s < SOFT_SHADOW_SAMPLES; s++) {
            vec3 jitter = (randomVec3() * 2.0 - 1.0) * lightRadius;
            vec3 jitteredDir;
            float jitteredDist;
            if (lightType == 1) {
                vec3 jTarget = lightPos + jitter;
                vec3 jVec = jTarget - hitPoint;
                jitteredDist = length(jVec);
                jitteredDir = jVec / jitteredDist;
            } else {
                jitteredDir = normalize(toLight + jitter * 0.1);
                jitteredDist = 1e38;
            }
            Ray shadowRay = Ray(hitPoint + normal * EPSILON, jitteredDir);
            if (!anyHitWithin(shadowRay, jitteredDist)) {
                visible += 1.0;
            }
        }
        return visible / float(SOFT_SHADOW_SAMPLES);
    } else {
        Ray shadowRay = Ray(hitPoint + normal * EPSILON, toLight);
        return anyHitWithin(shadowRay, maxDist) ? 0.0 : 1.0;
    }
}

// ============================================================
// GGX / Cook-Torrance PBR
// ============================================================

// GGX Normal Distribution Function
float D_GGX(float NdotH, float alpha) {
    float a2 = alpha * alpha;
    float d = NdotH * NdotH * (a2 - 1.0) + 1.0;
    return a2 / (PI * d * d + 1e-7);
}

// Smith height-correlated masking-shadowing (visibility form: G/(4*NdotV*NdotL))
float V_SmithGGX(float NdotV, float NdotL, float alpha) {
    float a2 = alpha * alpha;
    float ggxV = NdotL * sqrt(NdotV * NdotV * (1.0 - a2) + a2);
    float ggxL = NdotV * sqrt(NdotL * NdotL * (1.0 - a2) + a2);
    return 0.5 / (ggxV + ggxL + 1e-7);
}

// Fresnel-Schlick (multiply chain instead of pow for speed)
vec3 F_Schlick(float cosTheta, vec3 F0) {
    float x = clamp(1.0 - cosTheta, 0.0, 1.0);
    float x2 = x * x;
    float x5 = x2 * x2 * x;
    return F0 + (1.0 - F0) * x5;
}

// GGX importance sampling: sample half-vector H from the NDF
vec3 sampleGGX(vec3 N, float alpha) {
    float u1 = randomDouble();
    float u2 = randomDouble();

    // Sample spherical coords for H in tangent space
    float a2 = alpha * alpha;
    float cosTheta = sqrt((1.0 - u1) / (1.0 + (a2 - 1.0) * u1));
    float sinTheta = sqrt(1.0 - cosTheta * cosTheta);
    float phi = 2.0 * PI * u2;

    // Tangent space H
    vec3 H_tan = vec3(sinTheta * cos(phi), sinTheta * sin(phi), cosTheta);

    // Build TBN from N
    vec3 up = abs(N.y) < 0.999 ? vec3(0.0, 1.0, 0.0) : vec3(1.0, 0.0, 0.0);
    vec3 tangent = normalize(cross(up, N));
    vec3 bitangent = cross(N, tangent);

    return normalize(tangent * H_tan.x + bitangent * H_tan.y + N * H_tan.z);
}

// ============================================================
// Emissive primitive sampling (Next Event Estimation)
// ============================================================

// Sample a random point on a quad surface, return direction and PDF
bool sampleQuadLight(int idx, vec3 hitPoint, out vec3 lightDir, out float lightDist, out float pdf) {
    vec3 Q = sceneTexel(idx, 4).xyz;
    vec3 u = sceneTexel(idx, 5).xyz;
    vec3 v = sceneTexel(idx, 6).xyz;

    // Random point on quad
    float s = randomDouble();
    float t = randomDouble();
    vec3 pointOnLight = Q + u * s + v * t;

    vec3 toLight = pointOnLight - hitPoint;
    float dist2 = dot(toLight, toLight);
    lightDist = sqrt(dist2);
    lightDir = toLight / lightDist;

    // Quad normal and area
    vec3 n = cross(u, v);
    float area = length(n);
    if (area < 1e-8) return false;
    n /= area;

    // cos(theta') at the light surface
    float cosAtLight = abs(dot(n, -lightDir));
    if (cosAtLight < 1e-8) return false;

    // Area-to-solid-angle conversion: pdf = dist^2 / (area * cos_theta')
    pdf = dist2 / (area * cosAtLight);
    return true;
}

// Sample a random point on a sphere light, return direction and PDF (solid angle)
bool sampleSphereLight(int idx, vec3 hitPoint, out vec3 lightDir, out float lightDist, out float pdf) {
    vec4 g0 = sceneTexel(idx, 4);
    vec3 center = g0.xyz;
    float radius = g0.w;

    vec3 toCenter = center - hitPoint;
    float dist = length(toCenter);
    if (dist < radius + EPSILON) return false; // inside sphere

    // Solid angle subtended by sphere
    float sinThetaMax2 = radius * radius / (dist * dist);
    float cosThetaMax = sqrt(max(0.0, 1.0 - sinThetaMax2));

    // Sample uniform cone
    float u1 = randomDouble();
    float u2 = randomDouble();
    float cosTheta = 1.0 + u1 * (cosThetaMax - 1.0);
    float sinTheta = sqrt(max(0.0, 1.0 - cosTheta * cosTheta));
    float phi = 2.0 * PI * u2;

    // Build frame from direction to sphere center
    vec3 w = toCenter / dist;
    vec3 upV = abs(w.y) < 0.999 ? vec3(0.0, 1.0, 0.0) : vec3(1.0, 0.0, 0.0);
    vec3 uV = normalize(cross(upV, w));
    vec3 vV = cross(w, uV);

    lightDir = normalize(uV * sinTheta * cos(phi) + vV * sinTheta * sin(phi) + w * cosTheta);

    // PDF = 1 / solid_angle = 1 / (2*PI*(1-cosThetaMax))
    pdf = 1.0 / (2.0 * PI * (1.0 - cosThetaMax) + 1e-10);

    // Find actual distance by intersecting ray with sphere
    float tHit;
    vec3 hitN;
    if (!intersectSphere(Ray(hitPoint, lightDir), center, radius, 1e38, tHit, hitN)) return false;
    lightDist = tHit;
    return true;
}

// Power heuristic (beta=2)
float powerHeuristic(float pdfA, float pdfB) {
    float a2 = pdfA * pdfA;
    return a2 / (a2 + pdfB * pdfB + 1e-10);
}

// PDF for cosine-weighted hemisphere sampling
float cosinePdf(float NdotL) {
    return max(NdotL, 0.0) / PI;
}

// ============================================================
// Dielectric scattering (Snell + Schlick)
// ============================================================
void scatterDielectric(in Ray currentRay, in HitRecord hit, in float ior,
                       out Ray scattered, out vec3 attenuation) {
    vec3 unitDir = normalize(currentRay.direction);
    vec3 normal;
    float etaRatio;

    if (dot(unitDir, hit.normal) > 0.0) {
        normal = -hit.normal;
        etaRatio = ior;
    } else {
        normal = hit.normal;
        etaRatio = 1.0 / ior;
    }

    float cosTheta = min(dot(-unitDir, normal), 1.0);
    float sinTheta2 = etaRatio * etaRatio * (1.0 - cosTheta * cosTheta);
    bool cannotRefract = sinTheta2 > 1.0;

    float r0 = (1.0 - etaRatio) / (1.0 + etaRatio);
    r0 = r0 * r0;
    float reflectance = r0 + (1.0 - r0) * pow(1.0 - cosTheta, 5.0);

    vec3 direction;
    if (cannotRefract || reflectance > randomDouble()) {
        direction = reflect(unitDir, normal);
        scattered = Ray(hit.hitPoint + normal * EPSILON, direction);
    } else {
        direction = refract(unitDir, normal, etaRatio);
        scattered = Ray(hit.hitPoint - normal * EPSILON, direction);
    }

    attenuation = vec3(1.0);
}

// ============================================================
// Environment sampling
// ============================================================

// Equirectangular UV from direction
vec2 dirToEquirect(vec3 dir) {
    float phi = atan(dir.z, dir.x) + envRotation;
    float theta = asin(clamp(dir.y, -1.0, 1.0));
    return vec2(phi / (2.0 * PI) + 0.5, theta / PI + 0.5);
}

// Procedural HDR sky: golden hour cinematic
vec3 proceduralSky(vec3 dir) {
    // Low sun for golden hour drama
    vec3 sunDir = normalize(vec3(0.6, 0.12, -0.7));
    float sunDot = max(dot(dir, sunDir), 0.0);

    // Deep twilight gradient
    float t = max(dir.y, 0.0);
    vec3 zenith  = vec3(0.04, 0.06, 0.18);  // deep navy
    vec3 mid     = vec3(0.12, 0.08, 0.22);  // dusky purple
    vec3 horizon = vec3(0.5, 0.25, 0.12);   // burnt orange horizon

    vec3 sky = mix(horizon, mid, pow(t, 0.3));
    sky = mix(sky, zenith, pow(t, 0.8));

    // Sun: large warm glow near horizon
    float sunDisk = pow(sunDot, 512.0) * 8.0;
    float sunHalo = pow(sunDot, 4.0) * 0.6;
    float sunBloom = pow(sunDot, 16.0) * 1.5;
    vec3 sunColor = vec3(1.0, 0.65, 0.3);
    sky += sunColor * (sunDisk + sunBloom) + vec3(1.0, 0.8, 0.5) * sunHalo;

    // Ground: dark warm
    if (dir.y < 0.0) {
        vec3 ground = vec3(0.08, 0.06, 0.04);
        sky = mix(ground, horizon, exp(dir.y * 6.0));
    }

    return sky;
}

// Get environment radiance for a ray direction
vec3 sampleEnvironment(vec3 dir) {
    vec3 color;
    if (useEnvMap == 1) {
        vec2 uv = dirToEquirect(dir);
        color = texture(envMap, uv).rgb;
    } else if (useEnvMap == 2) {
        color = proceduralSky(dir);
    } else {
        // Simple gradient (original)
        float a = 0.5 * (dir.y + 1.0);
        color = mix(vec3(0.3, 0.5, 0.8), vec3(1.0), a);
    }
    return color * envIntensity;
}

// ============================================================
// Evaluate BRDF for a given (N, V, L) — returns BRDF * NdotL
// ============================================================
vec3 evalBRDF(vec3 N, vec3 V, vec3 L, vec3 hitColor, int hitMat, float hitRough) {
    float NdotL = max(dot(N, L), 0.0);
    if (NdotL <= 0.0) return vec3(0.0);
    vec3 H = normalize(L + V);
    float NdotV = max(dot(N, V), 0.001);
    float NdotH = max(dot(N, H), 0.0);
    float VdotH = max(dot(V, H), 0.0);
    float alpha = max(hitRough * hitRough, 0.002);

    if (hitMat == 1) {
        vec3 F = F_Schlick(VdotH, hitColor);
        return F * D_GGX(NdotH, alpha) * V_SmithGGX(NdotV, NdotL, alpha) * NdotL;
    } else {
        vec3 F0 = vec3(0.04);
        vec3 F = F_Schlick(VdotH, F0);
        vec3 spec = F * D_GGX(NdotH, alpha) * V_SmithGGX(NdotV, NdotL, alpha);
        vec3 diff = (1.0 - F) * hitColor / PI;
        return (diff + spec) * NdotL;
    }
}

// ============================================================
// Main ray tracing loop with NEE + MIS
// ============================================================
vec3 colorRayIterative(in Ray initialRay) {
    vec3 outColor = vec3(0.0);
    vec3 throughput = vec3(1.0);
    Ray currentRay = initialRay;
    bool lastBounceSpecular = false;

    for (int depth = 0; depth < MAX_DEPTH; depth++) {
        HitRecord closestHit;
        int hitIndex;
        findClosestHit(currentRay, closestHit, hitIndex);

        if (hitIndex == -1) {
            outColor += throughput * sampleEnvironment(normalize(currentRay.direction));
            break;
        }

        vec3 hitColor; int hitMat;
        vec3 hitEmission; float hitEmStr;
        float hitIOR; float hitRough;
        float hitSpec; float hitShine;
        getPrimMat(hitIndex, hitColor, hitMat, hitEmission, hitEmStr,
                   hitIOR, hitRough, hitSpec, hitShine);

        // Emissive contribution — only count if we hit it via BRDF sampling
        // (on first bounce or after specular, always count; otherwise MIS handles it)
        if (hitEmStr > 0.0) {
            if (depth == 0 || lastBounceSpecular || emissiveCount == 0) {
                outColor += throughput * hitEmission * hitEmStr;
            }
            // If we hit emissive via BRDF sampling and NEE is active, MIS weight applies
            // For simplicity with one-sample MIS, we skip the BRDF-hit emissive when NEE is active
        }

        if (hitMat == 2) break;

        // AO — skip during early convergence for speed, enable once settled
        float ao = 1.0;
        if (depth < 3 && frameCount > 8) {
            ao = computeAO(closestHit.hitPoint, closestHit.normal);
        }

        vec3 N = closestHit.normal;
        vec3 V = normalize(cameraPosition - closestHit.hitPoint);
        if (depth > 0) V = normalize(-currentRay.direction);

        // === Direct lighting from explicit lights ===
        int lCount = min(lightCount, MAX_LIGHTS);
        for (int li = 0; li < lCount; li++) {
            int lType; vec3 lDir; vec3 lPos; vec3 lCol; float lInt; float lRad;
            getLight(li, lType, lDir, lPos, lCol, lInt, lRad);

            vec3 toLight;
            float attIntensity, maxShadowDist;

            if (lType == 1) {
                vec3 dirToLight = lPos - closestHit.hitPoint;
                float dLight = length(dirToLight);
                toLight = dirToLight / dLight;
                attIntensity = lInt / (1.0 + k_linear * dLight + k_quadratic * dLight * dLight);
                maxShadowDist = dLight;
            } else {
                toLight = normalize(-lDir);
                attIntensity = lInt;
                maxShadowDist = 1e38;
            }

            float NdotL = max(dot(N, toLight), 0.0);
            if (NdotL <= 0.0) continue;

            float shadow = computeShadowFactor(closestHit.hitPoint, N,
                toLight, maxShadowDist, lPos, lRad, lType);

            if (shadow > 0.0) {
                vec3 brdfVal = evalBRDF(N, V, toLight, hitColor, hitMat, hitRough);
                outColor += throughput * brdfVal * lCol * attIntensity * shadow * ao;
            }
        }

        // === NEE: Sample emissive primitives directly ===
        if (emissiveCount > 0 && hitMat != 3) {
            // Pick a random emissive primitive
            int emIdx = emissiveIndices[int(randomDouble() * float(min(emissiveCount, 16)))];
            int emType = int(sceneTexel(emIdx, 0).x + 0.5);

            vec3 lightDir;
            float lightDist, lightPdf;
            bool sampled = false;

            if (emType == PRIM_QUAD)
                sampled = sampleQuadLight(emIdx, closestHit.hitPoint, lightDir, lightDist, lightPdf);
            else if (emType == PRIM_SPHERE)
                sampled = sampleSphereLight(emIdx, closestHit.hitPoint, lightDir, lightDist, lightPdf);

            if (sampled) {
                float NdotL = dot(N, lightDir);
                if (NdotL > 0.0) {
                    // Shadow test
                    Ray shadowRay = Ray(closestHit.hitPoint + N * EPSILON, lightDir);
                    if (!anyHitWithin(shadowRay, lightDist - 2.0 * EPSILON)) {
                        // Fetch only emission (col 2) — skip full material read
                        vec4 emData = sceneTexel(emIdx, 2);
                        vec3 Le = emData.xyz * emData.w;
                        vec3 brdfVal = evalBRDF(N, V, lightDir, hitColor, hitMat, hitRough);

                        // MIS weight (power heuristic): light PDF vs BRDF PDF
                        float brdfPdf = (hitMat == 1) ? 0.0 : cosinePdf(NdotL); // approximate
                        float misWeight = powerHeuristic(lightPdf / float(emissiveCount), brdfPdf);

                        if (lightPdf > 1e-10) {
                            outColor += throughput * Le * brdfVal * misWeight
                                      * float(emissiveCount) / lightPdf * ao;
                        }
                    }
                }
            }
        }

        // === Scatter ray for next bounce ===
        Ray scattered;
        vec3 attenuation;
        lastBounceSpecular = false;

        if (hitMat == 3) {
            scatterDielectric(currentRay, closestHit, hitIOR, scattered, attenuation);
            throughput *= attenuation * hitColor;
            lastBounceSpecular = true;
        } else if (hitMat == 1) {
            // Metal: GGX importance sampling
            float alpha = max(hitRough * hitRough, 0.002);
            vec3 Vm = normalize(-currentRay.direction);
            vec3 H = sampleGGX(N, alpha);
            vec3 L = reflect(-Vm, H);

            float NdotL = dot(N, L);
            if (NdotL <= 0.0) break;

            float NdotV = max(dot(N, Vm), 0.001);
            float NdotH = max(dot(N, H), 0.0);
            float VdotH = max(dot(Vm, H), 0.0);

            vec3 F = F_Schlick(VdotH, hitColor);
            float G = V_SmithGGX(NdotV, NdotL, alpha) * 4.0 * NdotV * NdotL;
            float weight = G * VdotH / (NdotH * NdotV + 1e-7);

            scattered = Ray(closestHit.hitPoint + N * EPSILON, L);
            throughput *= F * weight;
            lastBounceSpecular = (hitRough < 0.1);
        } else {
            // Lambertian: cosine-weighted hemisphere
            vec3 scatterDir = cosineWeightedHemisphere(N);
            scattered = Ray(closestHit.hitPoint + N * EPSILON, scatterDir);
            throughput *= hitColor;
        }

        currentRay = scattered;

        // Russian roulette after depth 2 (more aggressive with MIS)
        if (depth > 2) {
            float p = clamp(max(throughput.x, max(throughput.y, throughput.z)), 0.05, 0.95);
            if (randomDouble() > p) break;
            throughput /= p;
        }
    }

    return outColor;
}

// ============================================================
// Main — outputs LINEAR HDR, multi-sample per frame
// ============================================================
void main() {
    uvec2 pixelCoord = uvec2(gl_FragCoord.xy);
    int spp = clamp(samplesPerFrame, 1, 64);
    vec2 pixelSize = 2.0 / resolution;

    vec3 accumColor = vec3(0.0);

    for (int s = 0; s < spp; s++) {
        // Unique RNG seed per sample: pixel + frame + sample index
        rngState = pixelCoord.x * 1973u + pixelCoord.y * 9277u
                 + uint(frameCount) * 26699u + uint(s) * 39293u;
        randomDouble();

        vec2 jitter = (vec2(randomDouble(), randomDouble()) - 0.5) * pixelSize;
        vec2 ndc = fragTexCoord * 2.0 - 1.0 + jitter;
        vec4 clipPos = vec4(ndc, -1.0, 1.0);
        vec4 worldPos4 = invViewProj * clipPos;
        vec3 worldPos = worldPos4.xyz / worldPos4.w;

        Ray sampleRay = Ray(cameraPosition, normalize(worldPos - cameraPosition));
        accumColor += colorRayIterative(sampleRay);
    }

    vec3 outputColor = accumColor / float(spp);

    // Temporal accumulation — always blend, never flash black
    vec3 prev = texture(accumTexture, fragTexCoord).rgb;
    if (frameCount <= 1) {
        // First frame after camera move: aggressively replace but keep old as fallback
        // Avoids black flash — stale pixels from old angle are better than nothing
        float prevLum = dot(prev, vec3(0.299, 0.587, 0.114));
        float blend = (prevLum > 0.001) ? 0.7 : 1.0; // if prev has data, keep 30%
        outputColor = mix(prev, outputColor, blend);
    } else {
        float blendFactor = 1.0 / min(float(frameCount), 4096.0);
        outputColor = mix(prev, outputColor, blendFactor);
    }

    finalColor = vec4(outputColor, 1.0);
}
