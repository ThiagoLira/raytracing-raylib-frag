// ============================================================
// Lesson 8: The Path Tracing Loop
// ============================================================
//
// This is where everything comes together.
//
// A "path" is a chain of ray bounces:
//   Camera → Surface → Surface → Surface → ... → Light/Sky
//
// At each bounce:
//   1. Find the closest surface hit
//   2. If it's emissive, collect its light
//   3. Scatter the ray according to the material
//   4. Multiply throughput by the surface color
//   5. Repeat until we hit the sky or run out of bounces
//
// THROUGHPUT tracks how much light each bounce lets through.
// If a red surface absorbs 60% of light, throughput *= 0.4 * red.
// After several bounces, very little light gets through.
//
// RUSSIAN ROULETTE: instead of always doing MAX_DEPTH bounces,
// randomly terminate paths that are carrying little energy.
// This is unbiased because we divide by the survival probability.
//
// Controls:
//   1-8 — set max bounce depth (see how each bounce adds light)

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
uniform int   maxDepth;
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
    float r = sqrt(u2);
    float theta = 2.0*PI*u1;
    float x = r*cos(theta), y = r*sin(theta), z = sqrt(1.0-u2);
    vec3 up = abs(N.y)<0.999 ? vec3(0,1,0) : vec3(1,0,0);
    vec3 T = normalize(cross(up,N));
    vec3 B = cross(N,T);
    return normalize(T*x + B*y + N*z);
}

vec3 sampleGGX(vec3 N, float alpha) {
    float u1 = rnd(), u2 = rnd();
    float a2 = alpha*alpha;
    float cosT = sqrt((1.0-u1)/(1.0+(a2-1.0)*u1));
    float sinT = sqrt(1.0-cosT*cosT);
    float phi = 2.0*PI*u2;
    vec3 H = vec3(sinT*cos(phi), sinT*sin(phi), cosT);
    vec3 up = abs(N.y)<0.999 ? vec3(0,1,0) : vec3(1,0,0);
    vec3 T = normalize(cross(up,N));
    vec3 B = cross(N,T);
    return normalize(T*H.x + B*H.y + N*H.z);
}

// Fresnel
vec3 F_Schlick(float cosT, vec3 F0) {
    float x = clamp(1.0-cosT, 0.0, 1.0);
    float x2 = x*x; return F0 + (1.0-F0)*x2*x2*x;
}

float V_SmithGGX(float NdotV, float NdotL, float alpha) {
    float a2 = alpha*alpha;
    float gV = NdotL*sqrt(NdotV*NdotV*(1.0-a2)+a2);
    float gL = NdotV*sqrt(NdotL*NdotL*(1.0-a2)+a2);
    return 0.5/(gV+gL+1e-7);
}

// ============================================================
// Scene — mini Cornell box setup
// ============================================================
struct Ray { vec3 origin, direction; };

bool iSphere(Ray r, vec3 c, float rad, float tMax, out float t, out vec3 n) {
    vec3 oc = r.origin-c;
    float b = dot(r.direction,oc);
    float cc = dot(oc,oc)-rad*rad;
    float disc = b*b-cc;
    if (disc<0.0) return false;
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

// Materials: 0=lambertian, 1=metal, 2=emissive, 3=glass
struct HitInfo {
    float t;
    vec3 normal, color;
    int material;
    float roughness, ior;
    vec3 emission;
};

#define OBJ_COUNT 12

void findHit(Ray r, out HitInfo h) {
    h.t = 1e38;
    h.material = -1;
    float t; vec3 n;

    float S = 2.0;

    // Back wall (white)
    if (iQuad(r, vec3(-S,0,-S*2), vec3(S*2,0,0), vec3(0,S*2,0), h.t, t, n))
        { h.t=t; h.normal=n; h.color=vec3(0.73); h.material=0; h.emission=vec3(0); }
    // Floor (white)
    if (iQuad(r, vec3(-S,0,-S*2), vec3(S*2,0,0), vec3(0,0,S*2), h.t, t, n))
        { h.t=t; h.normal=n; h.color=vec3(0.73); h.material=0; h.emission=vec3(0); }
    // Ceiling (white)
    if (iQuad(r, vec3(-S,S*2,0), vec3(S*2,0,0), vec3(0,0,-S*2), h.t, t, n))
        { h.t=t; h.normal=n; h.color=vec3(0.73); h.material=0; h.emission=vec3(0); }
    // Left wall (red)
    if (iQuad(r, vec3(-S,0,0), vec3(0,0,-S*2), vec3(0,S*2,0), h.t, t, n))
        { h.t=t; h.normal=n; h.color=vec3(0.65,0.05,0.05); h.material=0; h.emission=vec3(0); }
    // Right wall (green)
    if (iQuad(r, vec3(S,0,-S*2), vec3(0,0,S*2), vec3(0,S*2,0), h.t, t, n))
        { h.t=t; h.normal=n; h.color=vec3(0.12,0.45,0.15); h.material=0; h.emission=vec3(0); }

    // Ceiling light (emissive)
    if (iQuad(r, vec3(-0.5,S*2-0.01,-S+0.5), vec3(1,0,0), vec3(0,0,-1), h.t, t, n))
        { h.t=t; h.normal=n; h.color=vec3(1); h.material=2; h.emission=vec3(1,0.95,0.85)*8.0; }

    // Metal sphere
    if (iSphere(r, vec3(0.7,0.6,-2.8), 0.6, h.t, t, n))
        { h.t=t; h.normal=n; h.color=vec3(0.9,0.85,0.78); h.material=1; h.roughness=0.05; h.emission=vec3(0); }

    // Glass sphere
    if (iSphere(r, vec3(-0.8,0.5,-1.8), 0.5, h.t, t, n))
        { h.t=t; h.normal=n; h.color=vec3(1); h.material=3; h.ior=1.5; h.emission=vec3(0); }

    // Matte sphere
    if (iSphere(r, vec3(0.0,0.35,-1.3), 0.35, h.t, t, n))
        { h.t=t; h.normal=n; h.color=vec3(0.8,0.5,0.2); h.material=0; h.roughness=0.9; h.emission=vec3(0); }
}

// ============================================================
// The path tracing loop — THIS IS THE CORE ALGORITHM
// ============================================================
vec3 pathTrace(Ray ray) {
    vec3 color = vec3(0.0);      // accumulated light
    vec3 throughput = vec3(1.0); // how much light survives

    for (int depth = 0; depth < 8; depth++) {
        // Stop if we've reached the user-selected max depth
        if (depth >= maxDepth) break;

        HitInfo hit;
        findHit(ray, hit);

        // Miss → black (we're inside a box, so this rarely happens)
        if (hit.material == -1) break;

        // ── Emissive: collect light ──
        if (hit.material == 2) {
            color += throughput * hit.emission;
            break; // emissive surfaces don't scatter
        }

        vec3 hitPt = ray.origin + ray.direction * hit.t;
        vec3 N = hit.normal;

        // ── Lambertian: scatter in cosine-weighted hemisphere ──
        if (hit.material == 0) {
            vec3 scatterDir = cosineHemisphere(N);
            ray = Ray(hitPt + N*EPSILON, scatterDir);
            throughput *= hit.color;
        }
        // ── Metal: GGX importance-sampled reflection ──
        else if (hit.material == 1) {
            float alpha = max(hit.roughness*hit.roughness, 0.002);
            vec3 V = normalize(-ray.direction);
            vec3 H = sampleGGX(N, alpha);
            vec3 L = reflect(-V, H);
            float NdotL = dot(N, L);
            if (NdotL <= 0.0) break;
            float NdotV = max(dot(N,V), 0.001);
            float VdotH = max(dot(V,H), 0.0);
            float NdotH = max(dot(N,H), 0.0);
            vec3 F = F_Schlick(VdotH, hit.color);
            float G = V_SmithGGX(NdotV, NdotL, alpha) * 4.0*NdotV*NdotL;
            float weight = G * VdotH / (NdotH*NdotV + 1e-7);
            ray = Ray(hitPt + N*EPSILON, L);
            throughput *= F * weight;
        }
        // ── Glass: Snell + Fresnel ──
        else if (hit.material == 3) {
            vec3 unitDir = normalize(ray.direction);
            vec3 normal; float etaR;
            if (dot(unitDir, N) > 0.0) { normal = -N; etaR = hit.ior; }
            else { normal = N; etaR = 1.0/hit.ior; }
            float cosT = min(dot(-unitDir, normal), 1.0);
            float sinT2 = etaR*etaR*(1.0-cosT*cosT);
            float r0 = (1.0-etaR)/(1.0+etaR); r0 = r0*r0;
            float refl = r0 + (1.0-r0)*pow(1.0-cosT, 5.0);
            vec3 dir;
            if (sinT2 > 1.0 || refl > rnd()) {
                dir = reflect(unitDir, normal);
                ray = Ray(hitPt + normal*EPSILON, dir);
            } else {
                dir = refract(unitDir, normal, etaR);
                ray = Ray(hitPt - normal*EPSILON, dir);
            }
            throughput *= hit.color;
        }

        // ── Russian Roulette (after depth 2) ──
        // Randomly terminate paths that carry little energy.
        // The key insight: we DIVIDE throughput by the survival
        // probability, making this an UNBIASED estimator.
        if (depth > 2) {
            float p = clamp(max(throughput.x, max(throughput.y, throughput.z)), 0.05, 0.95);
            if (rnd() > p) break;  // terminate
            throughput /= p;       // compensate survivors
        }
    }
    return color;
}

// ============================================================
// Main
// ============================================================
void main() {
    uvec2 px = uvec2(gl_FragCoord.xy);
    vec2 pixelSize = 2.0 / resolution;

    int spp = 4;
    vec3 accumColor = vec3(0.0);

    for (int s = 0; s < spp; s++) {
        rngState = px.x*1973u + px.y*9277u + uint(frameCount)*26699u + uint(s)*39293u;
        rnd();

        vec2 jitter = (vec2(rnd(), rnd()) - 0.5) * pixelSize;
        vec2 ndc = fragTexCoord * 2.0 - 1.0 + jitter;
        vec4 wp4 = invViewProj * vec4(ndc, -1.0, 1.0);
        vec3 wp = wp4.xyz / wp4.w;
        Ray ray = Ray(cameraPosition, normalize(wp - cameraPosition));

        accumColor += pathTrace(ray);
    }

    vec3 color = accumColor / float(spp);

    // Simple Reinhard tone map (lesson 10 covers this in detail)
    color = color / (1.0 + color);
    color = pow(max(color, 0.0), vec3(1.0 / 2.2));

    finalColor = vec4(color, 1.0);
}
