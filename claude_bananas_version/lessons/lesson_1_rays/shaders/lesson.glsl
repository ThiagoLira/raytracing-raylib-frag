// ============================================================
// Lesson 1: From Pixels to Rays
// ============================================================
//
// THE BIG QUESTION: You have a 2D screen full of pixels.
// How does each pixel know what 3D direction to look at?
//
// Answer: a pipeline of coordinate transforms.
//
// This lesson lets you SEE each stage of that pipeline by
// coloring pixels according to their coordinates at each step.
//
// THE PIPELINE:
//
//   ┌──────────────┐     fragTexCoord      ┌─────────────┐
//   │  Screen UV   │  ──────────────────►  │ [0,1] x [0,1]│
//   │  (per pixel) │   from rasterizer     │  u,v coords  │
//   └──────────────┘                       └──────┬───────┘
//                                                 │
//                                          * 2 - 1│
//                                                 ▼
//                                        ┌─────────────────┐
//                                        │  NDC (clip space)│
//                                        │ [-1,1] x [-1,1] │
//                                        └────────┬────────┘
//                                                 │
//                                     invViewProj │ (matrix multiply)
//                                                 ▼
//                                        ┌─────────────────┐
//                                        │  World position  │
//                                        │  (3D, x/y/z)    │
//                                        └────────┬────────┘
//                                                 │
//                                    normalize(   │ - cameraPos)
//                                                 ▼
//                                        ┌─────────────────┐
//                                        │  Ray direction   │
//                                        │  (unit vector)   │
//                                        └─────────────────┘
//
// Press 1-5 to visualize each stage.

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
uniform int   mode;  // 0-4: pipeline stages, 5: final raytrace

uniform vec3  sphereCenter;
uniform float sphereRadius;
uniform vec3  sphereColor;

// ============================================================
// Ray-sphere intersection
// ============================================================
bool intersectSphere(vec3 O, vec3 D, vec3 C, float R,
                     out float t, out vec3 N) {
    vec3 oc = O - C;
    float b = dot(D, oc);
    float c = dot(oc, oc) - R*R;
    float disc = b*b - c;
    if (disc < 0.0) return false;
    float sq = sqrt(disc);
    t = -b - sq;
    if (t < EPSILON) { t = -b + sq; if (t < EPSILON) return false; }
    N = normalize(oc + t * D);
    return true;
}

vec3 skyColor(vec3 dir) {
    float t = 0.5 * (dir.y + 1.0);
    return mix(vec3(0.7, 0.6, 0.5), vec3(0.25, 0.45, 0.8), t);
}

// ============================================================
// Main — each mode visualizes one stage of the pipeline
// ============================================================
void main() {
    vec2 px = gl_FragCoord.xy;
    vec3 color;

    // ══════════════════════════════════════════════════════════
    // STAGE 1: Screen UV coordinates
    // ══════════════════════════════════════════════════════════
    //
    // fragTexCoord is what the GPU gives us for free.
    // It's the pixel position normalized to [0, 1]:
    //   bottom-left = (0, 0)
    //   top-right   = (1, 1)
    //
    // We visualize it as color: Red = U (horizontal), Green = V (vertical).
    // You should see a gradient: black corner, red edge, green edge, yellow corner.

    vec2 uv = fragTexCoord;  // [0, 1]

    if (mode == 0) {
        color = vec3(uv.x, uv.y, 0.0);
        // Label the corners conceptually:
        // bottom-left is (0,0) = black
        // bottom-right is (1,0) = red
        // top-left is (0,1) = green
        // top-right is (1,1) = yellow
        finalColor = vec4(color, 1.0);
        return;
    }

    // ══════════════════════════════════════════════════════════
    // STAGE 2: NDC (Normalized Device Coordinates)
    // ══════════════════════════════════════════════════════════
    //
    // Remap [0,1] → [-1,1].  This puts the CENTER of the screen
    // at (0,0), which is where the camera looks.
    //
    //   ndc = uv * 2.0 - 1.0
    //
    // Now: center = (0,0), edges = ±1.
    // We visualize by mapping [-1,1] back to [0,1] for display.
    // The center should be gray (0.5, 0.5), edges colored.

    vec2 ndc = uv * 2.0 - 1.0;  // [-1, 1]

    if (mode == 1) {
        // Remap for display: -1→0 (dark), 0→0.5 (gray), +1→1 (bright)
        color = vec3(ndc * 0.5 + 0.5, 0.3);

        // Draw crosshair at center (NDC origin = where camera points)
        float distToCenter = min(abs(px.x - resolution.x*0.5),
                                  abs(px.y - resolution.y*0.5));
        if (distToCenter < 1.0) color = vec3(1.0);

        finalColor = vec4(color, 1.0);
        return;
    }

    // ══════════════════════════════════════════════════════════
    // STAGE 3: World position (after inverse view-projection)
    // ══════════════════════════════════════════════════════════
    //
    // The NDC coordinate is a point in "clip space" — a 2D
    // coordinate that the camera sees. To find where that point
    // is in the 3D world, we multiply by the INVERSE of the
    // view-projection matrix.
    //
    //   clipPos = vec4(ndc, -1, 1)     ← on the near plane (z = -1)
    //   worldPos = (invViewProj * clipPos).xyz / .w
    //
    // This is the key trick: the matrix "unprojects" 2D → 3D.
    // Orbit the camera to see the world positions change!

    vec4 clipPos = vec4(ndc, -1.0, 1.0);
    vec4 worldPos4 = invViewProj * clipPos;
    vec3 worldPos = worldPos4.xyz / worldPos4.w;

    if (mode == 2) {
        // Color by world X, Y, Z → R, G, B
        // Remap from world coords (roughly -5..5) to visible range
        color = fract(worldPos * 0.3) * 0.8 + 0.1;

        // Orbit the camera! Watch the colors change — same pixel,
        // different world position, because the matrix changed.
        finalColor = vec4(color, 1.0);
        return;
    }

    // ══════════════════════════════════════════════════════════
    // STAGE 4: Ray direction
    // ══════════════════════════════════════════════════════════
    //
    // The ray starts at the camera and goes TOWARD the world
    // position we just computed:
    //
    //   rayDir = normalize(worldPos - cameraPosition)
    //
    // This is a UNIT VECTOR (length = 1) pointing into the scene.
    // We visualize it as color: R = X component, G = Y, B = Z.
    // Remap from [-1,1] to [0,1] for display.
    //
    // Center pixel → ray points straight ahead (along camera look)
    // Edge pixels → rays fan out to cover the field of view

    vec3 rayDir = normalize(worldPos - cameraPosition);

    if (mode == 3) {
        color = rayDir * 0.5 + 0.5;  // remap [-1,1] → [0,1]

        // Notice: the center pixel is a uniform color (the forward
        // direction), and it shifts smoothly toward the edges.
        // This fan-out IS your field of view.
        finalColor = vec4(color, 1.0);
        return;
    }

    // ══════════════════════════════════════════════════════════
    // STAGE 5: Hit distance (how far the ray traveled)
    // ══════════════════════════════════════════════════════════
    //
    // Now we USE the ray. Cast it into the scene and measure
    // how far it goes before hitting something.
    //
    // Short distance = close to camera (bright)
    // Long distance = far away (dark)
    // Miss = sky (blueish)
    //
    // This is essentially a depth buffer — the foundation of
    // knowing WHERE things are in the scene.

    if (mode == 4) {
        float t; vec3 N;
        if (intersectSphere(cameraPosition, rayDir, sphereCenter, sphereRadius, t, N)) {
            // Map distance to brightness: near=white, far=dark
            float depth = 1.0 - clamp(t / 8.0, 0.0, 1.0);
            color = vec3(depth);
        } else {
            color = vec3(0.05, 0.05, 0.12);  // miss = very dark blue
        }
        finalColor = vec4(color, 1.0);
        return;
    }

    // ══════════════════════════════════════════════════════════
    // STAGE 6: Full raytrace (putting it all together)
    // ══════════════════════════════════════════════════════════
    //
    // Pipeline complete:
    //   pixel UV → NDC → invViewProj → worldPos → rayDir → intersection → shading
    //
    // Stages 1-4 are invisible plumbing. This is what the user sees.
    // Every lesson after this builds on top of this ray generation.

    float tHit; vec3 hitN;
    if (intersectSphere(cameraPosition, rayDir, sphereCenter, sphereRadius, tHit, hitN)) {
        vec3 hitPt = cameraPosition + rayDir * tHit;
        vec3 lightDir = normalize(vec3(0.8, 1.0, 0.4));
        float diff = max(dot(hitN, lightDir), 0.0);
        color = sphereColor * (0.12 + diff * 0.88);

        // Show the surface normal as an arrow
        vec4 nArrow = vizArrow(px, hitPt, hitN, 0.5,
                                viewProj, resolution,
                                vec3(1.0, 0.9, 0.2), 2.0);
        color = vizComposite(color, nArrow);
    } else {
        color = skyColor(rayDir);
    }

    // World-space axes at origin
    vec4 axes = vizAxes(px, vec3(0.0), viewProj, resolution, 0.8, 1.5);
    color = vizComposite(color, axes);

    // Camera position dot
    vec4 camDot = vizPoint(px, cameraPosition, viewProj, resolution,
                           vec3(1.0), 5.0);
    color = vizComposite(color, camDot);

    // Show a single ray from camera through the center pixel
    vec4 centerRay = vizArrow(px, cameraPosition, rayDir, 3.5,
                               viewProj, resolution,
                               vec3(1.0, 1.0, 0.3), 1.5);
    color = vizComposite(color, centerRay);

    color = pow(max(color, 0.0), vec3(1.0 / 2.2));
    finalColor = vec4(color, 1.0);
}
