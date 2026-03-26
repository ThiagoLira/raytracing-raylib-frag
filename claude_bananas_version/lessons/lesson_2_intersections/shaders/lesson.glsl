// ============================================================
// Lesson 2: Ray-Shape Intersections
// ============================================================
//
// A ray is: P(t) = Origin + t * Direction
//
// "Intersection" means: find the value of t where the ray
// touches a surface. Different shapes need different math.
//
// This lesson shows all three intersection types used in
// the full raytracer:
//   Sphere   — solve a quadratic equation
//   Quad     — intersect with a plane, then check 2D bounds
//   Triangle — Moller-Trumbore algorithm (barycentric coords)
//
// Controls: press 1-4 to show All / Sphere / Quad / Triangle

#ifdef GL_ES
precision highp float;
#endif

#define EPSILON 0.001

in vec2 fragTexCoord;
out vec4 finalColor;

uniform sampler2D texture0;
uniform vec3  cameraPosition;
uniform mat4  invViewProj;
uniform mat4  viewProj;
uniform vec2  resolution;
uniform int   mode;  // 0=all, 1=sphere only, 2=quad only, 3=triangle only

// ============================================================
// Ray struct
// ============================================================
struct Ray {
    vec3 origin;
    vec3 direction;
};

// ============================================================
// Intersection 1: SPHERE
// ============================================================
//
//  A sphere is all points P where |P - Center|^2 = R^2
//
//  Substitute P = O + t*D:
//    |O + t*D - C|^2 = R^2
//
//  Let oc = O - C, expand:
//    t^2*(D.D) + 2t*(D.oc) + (oc.oc - R^2) = 0
//
//  Since D is normalized, D.D = 1, so:
//    t^2 + 2*b*t + c = 0     where b = D.oc, c = oc.oc - R^2
//
//  Discriminant = b^2 - c
//    < 0 : ray misses sphere entirely
//    = 0 : ray grazes the edge (1 hit)
//    > 0 : ray passes through (2 hits, we want the nearer one)
//
bool intersectSphere(Ray r, vec3 center, float radius,
                     out float tHit, out vec3 normal) {
    vec3 oc = r.origin - center;
    float b = dot(r.direction, oc);          // half of the linear term
    float c = dot(oc, oc) - radius * radius; // constant term
    float disc = b * b - c;                  // discriminant

    if (disc < 0.0) return false;            // no real roots = miss

    float sqrtDisc = sqrt(disc);
    float t = -b - sqrtDisc;                 // near intersection
    if (t < EPSILON) {
        t = -b + sqrtDisc;                   // try far intersection
        if (t < EPSILON) return false;        // both behind us
    }

    tHit = t;
    normal = normalize(oc + t * r.direction); // points outward from center
    return true;
}

// ============================================================
// Intersection 2: QUAD  (from Peter Shirley's "Ray Tracing: The Rest of Your Life")
// ============================================================
//
//  A quad is defined by:
//    Q = corner point
//    u = first edge vector
//    v = second edge vector
//
//  The quad spans the parallelogram: Q + s*u + t*v  for s,t in [0,1]
//
//  Step 1: find where the ray hits the plane containing the quad
//    normal = cross(u, v)
//    t_hit = dot(Q - O, normal) / dot(D, normal)
//
//  Step 2: check if the hit point is inside the quad
//    project onto u and v axes, check both are in [0, 1]
//
bool intersectQuad(Ray r, vec3 Q, vec3 u, vec3 v,
                   out float tHit, out vec3 normal) {
    vec3 n = cross(u, v);                    // quad normal (not normalized yet)
    float nLen = length(n);
    if (nLen < 1e-8) return false;           // degenerate quad
    vec3 unitN = n / nLen;

    float denom = dot(unitN, r.direction);
    if (abs(denom) < 1e-8) return false;     // ray parallel to quad

    // Step 1: ray-plane intersection
    float t = dot(Q - r.origin, unitN) / denom;
    if (t < EPSILON) return false;            // quad is behind ray

    // Step 2: is the hit point inside the parallelogram?
    vec3 hitPt = r.origin + t * r.direction;
    vec3 p = hitPt - Q;                       // vector from corner to hit
    vec3 w = n / dot(n, n);                   // dual basis vector

    float alpha = dot(cross(p, v), w);        // u-coordinate
    float beta  = dot(cross(u, p), w);        // v-coordinate

    if (alpha < 0.0 || alpha > 1.0) return false;
    if (beta  < 0.0 || beta  > 1.0) return false;

    tHit = t;
    normal = (denom < 0.0) ? unitN : -unitN; // face toward the ray
    return true;
}

// ============================================================
// Intersection 3: TRIANGLE  (Moller-Trumbore algorithm)
// ============================================================
//
//  A triangle has vertices A, B, C.
//  Any point on the triangle: P = A + u*(B-A) + v*(C-A)
//    where u >= 0, v >= 0, u+v <= 1    (barycentric coords)
//
//  Substitute P = O + t*D and solve the 3x3 system:
//    [-D | E1 | E2] * [t, u, v]^T = O - A
//
//  The Moller-Trumbore trick: use cross products to solve
//  this system efficiently without building a matrix.
//
bool intersectTriangle(Ray r, vec3 A, vec3 B, vec3 C,
                       out float tHit, out vec3 normal) {
    vec3 E1 = B - A;                          // edge 1
    vec3 E2 = C - A;                          // edge 2
    vec3 P = cross(r.direction, E2);
    float det = dot(E1, P);

    if (abs(det) < 1e-8) return false;        // ray parallel to triangle

    float invDet = 1.0 / det;
    vec3 T = r.origin - A;

    float u = dot(T, P) * invDet;             // barycentric u
    if (u < 0.0 || u > 1.0) return false;

    vec3 QV = cross(T, E1);
    float v = dot(r.direction, QV) * invDet;  // barycentric v
    if (v < 0.0 || u + v > 1.0) return false;

    float t = dot(E2, QV) * invDet;           // ray parameter
    if (t < EPSILON) return false;             // behind ray

    tHit = t;
    vec3 faceN = normalize(cross(E1, E2));
    normal = (det > 0.0) ? faceN : -faceN;   // face toward the ray
    return true;
}

// ============================================================
// Sky
// ============================================================
vec3 skyColor(vec3 dir) {
    float t = 0.5 * (dir.y + 1.0);
    vec3 bottom = vec3(0.85, 0.75, 0.65); // warm horizon
    vec3 top    = vec3(0.25, 0.45, 0.75); // blue zenith
    return mix(bottom, top, t);
}

// ============================================================
// Scene — hardcoded for clarity (no data texture)
// ============================================================

// Ground: giant sphere
const vec3  groundCenter = vec3(0, -100.5, -2);
const float groundRadius = 100.0;
const vec3  groundColor  = vec3(0.35, 0.35, 0.32);

// Sphere
const vec3  sphCenter = vec3(-2.0, 0.55, -3.0);
const float sphRadius = 0.85;
const vec3  sphColor  = vec3(0.85, 0.35, 0.3);  // coral

// Quad (a standing panel)
const vec3 quadQ = vec3(-0.3, 0.0, -4.2);
const vec3 quadU = vec3(1.6, 0.0, 0.0);
const vec3 quadV = vec3(0.0, 2.0, 0.0);
const vec3 quadColor = vec3(0.35, 0.55, 0.85);  // soft blue

// Triangle
const vec3 triA = vec3(2.0, 0.0, -3.6);
const vec3 triB = vec3(3.6, 0.0, -2.4);
const vec3 triC = vec3(2.6, 2.2, -3.0);
const vec3 triColor = vec3(0.9, 0.65, 0.2);     // warm amber

// ============================================================
// Main
// ============================================================
void main() {
    // Generate ray for this pixel
    vec2 ndc = fragTexCoord * 2.0 - 1.0;
    vec4 worldPos4 = invViewProj * vec4(ndc, -1.0, 1.0);
    vec3 worldPos = worldPos4.xyz / worldPos4.w;

    Ray ray = Ray(cameraPosition, normalize(worldPos - cameraPosition));

    // Find closest hit across all objects
    float bestT = 1e38;
    vec3  bestNormal;
    vec3  bestColor;
    int   bestObj = -1; // 0=ground, 1=sphere, 2=quad, 3=triangle

    float t; vec3 n;

    // Ground (always visible)
    if (intersectSphere(ray, groundCenter, groundRadius, t, n) && t < bestT) {
        bestT = t; bestNormal = n; bestColor = groundColor; bestObj = 0;
    }

    // Sphere (visible in mode 0 or 1)
    if ((mode == 0 || mode == 1) &&
        intersectSphere(ray, sphCenter, sphRadius, t, n) && t < bestT) {
        bestT = t; bestNormal = n; bestColor = sphColor; bestObj = 1;
    }

    // Quad (visible in mode 0 or 2)
    if ((mode == 0 || mode == 2) &&
        intersectQuad(ray, quadQ, quadU, quadV, t, n) && t < bestT) {
        bestT = t; bestNormal = n; bestColor = quadColor; bestObj = 2;
    }

    // Triangle (visible in mode 0 or 3)
    if ((mode == 0 || mode == 3) &&
        intersectTriangle(ray, triA, triB, triC, t, n) && t < bestT) {
        bestT = t; bestNormal = n; bestColor = triColor; bestObj = 3;
    }

    // Shading
    vec3 color;
    if (bestObj >= 0) {
        // Simple directional light
        vec3 lightDir = normalize(vec3(0.8, 1.0, 0.4));
        float diff = max(dot(bestNormal, lightDir), 0.0);
        color = bestColor * (0.15 + diff * 0.85);

        // Subtle normal-mapped tint for visual interest
        if (bestObj > 0) {
            color = mix(color, bestNormal * 0.5 + 0.5, 0.15);
        }
    } else {
        color = skyColor(ray.direction);
    }

    // --- Viz overlays ---
    vec2 px = gl_FragCoord.xy;

    // World-space axes at origin
    vec4 axes = vizAxes(px, vec3(0.0), viewProj, resolution, 0.8, 1.5);
    color = vizComposite(color, axes);

    // Normal arrows on each visible object
    if (mode == 0 || mode == 1) {
        // Sphere normals at cardinal points
        vec4 nTop  = vizArrow(px, sphCenter + vec3(0,sphRadius,0),
                              vec3(0,1,0), 0.5, viewProj, resolution,
                              vec3(1.0, 0.9, 0.2), 1.5);
        vec4 nFront = vizArrow(px, sphCenter + vec3(0,0,sphRadius),
                               vec3(0,0,1), 0.5, viewProj, resolution,
                               vec3(1.0, 0.9, 0.2), 1.5);
        vec4 nRight = vizArrow(px, sphCenter + vec3(sphRadius,0,0),
                               vec3(1,0,0), 0.5, viewProj, resolution,
                               vec3(1.0, 0.9, 0.2), 1.5);
        color = vizComposite(color, nTop);
        color = vizComposite(color, nFront);
        color = vizComposite(color, nRight);
    }

    if (mode == 0 || mode == 2) {
        // Quad normal at center
        vec3 quadCenter = quadQ + quadU * 0.5 + quadV * 0.5;
        vec3 quadNormal = normalize(cross(quadU, quadV));
        vec4 nQuad = vizArrow(px, quadCenter, quadNormal, 0.6,
                              viewProj, resolution,
                              vec3(1.0, 0.9, 0.2), 1.5);
        color = vizComposite(color, nQuad);
    }

    if (mode == 0 || mode == 3) {
        // Triangle normal at centroid
        vec3 triCenter = (triA + triB + triC) / 3.0;
        vec3 triNormal = normalize(cross(triB - triA, triC - triA));
        vec4 nTri = vizArrow(px, triCenter, triNormal, 0.6,
                             viewProj, resolution,
                             vec3(1.0, 0.9, 0.2), 1.5);
        color = vizComposite(color, nTri);

        // Triangle vertices as dots
        vec4 dA = vizPoint(px, triA, viewProj, resolution, triColor, 4.0);
        vec4 dB = vizPoint(px, triB, viewProj, resolution, triColor, 4.0);
        vec4 dC = vizPoint(px, triC, viewProj, resolution, triColor, 4.0);
        color = vizComposite(color, dA);
        color = vizComposite(color, dB);
        color = vizComposite(color, dC);

        // Triangle edge wireframe
        vec4 eAB = vizLine(px, triA, triB, viewProj, resolution, vec3(1.0,0.8,0.4), 1.0);
        vec4 eBC = vizLine(px, triB, triC, viewProj, resolution, vec3(1.0,0.8,0.4), 1.0);
        vec4 eCA = vizLine(px, triC, triA, viewProj, resolution, vec3(1.0,0.8,0.4), 1.0);
        color = vizComposite(color, eAB);
        color = vizComposite(color, eBC);
        color = vizComposite(color, eCA);
    }

    // Gamma correction
    color = pow(max(color, 0.0), vec3(1.0 / 2.2));
    finalColor = vec4(color, 1.0);
}
