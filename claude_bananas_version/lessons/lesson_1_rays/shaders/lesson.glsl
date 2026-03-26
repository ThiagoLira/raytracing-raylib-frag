// Lesson 1: What Is a Ray?
//
// A ray has two parts:
//   1. An ORIGIN — where it starts (the camera position)
//   2. A DIRECTION — where it's heading (toward each pixel)
//
// This shader casts one ray per pixel, tests if it hits a sphere,
// and overlays vector arrows to visualize what's happening.

#ifdef GL_ES
precision highp float;
#endif

#define EPSILON 0.001
#define PI 3.14159265359

in vec2 fragTexCoord;
out vec4 finalColor;

uniform sampler2D texture0;

// Camera
uniform vec3 cameraPosition;
uniform mat4 invViewProj;   // for ray generation
uniform mat4 viewProj;      // for viz primitive projection
uniform vec2 resolution;
uniform float time;

// Scene: just one sphere
uniform vec3  sphereCenter;
uniform float sphereRadius;
uniform vec3  sphereColor;

// ============================================================
// VIZ PRIMITIVES — included via Makefile concatenation
// (projectToScreen, vizPoint, vizLine, vizArrow, vizAxes, etc.)
// The #include happens at build time: cat viz_primitives.glsl + lesson.glsl
// ============================================================

// ============================================================
// Ray-sphere intersection (from main shader, simplified)
// ============================================================
//
// Given ray origin O and direction D, solve for t in:
//   |O + t*D - C|^2 = r^2
//
// Expanding: t^2 + 2t*(D·(O-C)) + |O-C|^2 - r^2 = 0
// Use half-b optimization: b = D·(O-C), discriminant = b^2 - c

bool intersectSphere(vec3 rayOrigin, vec3 rayDir,
                     vec3 center, float radius,
                     out float tHit, out vec3 hitNormal) {
    vec3 oc = rayOrigin - center;
    float b = dot(rayDir, oc);
    float c = dot(oc, oc) - radius * radius;
    float disc = b * b - c;
    if (disc < 0.0) return false;

    float sqrtDisc = sqrt(disc);
    float t = -b - sqrtDisc;   // near hit
    if (t < EPSILON) {
        t = -b + sqrtDisc;     // try far hit
        if (t < EPSILON) return false;
    }
    tHit = t;
    hitNormal = normalize(oc + t * rayDir);
    return true;
}

// ============================================================
// Sky gradient — simple vertical blend
// ============================================================
vec3 skyColor(vec3 dir) {
    float t = 0.5 * (dir.y + 1.0);
    return mix(vec3(0.3, 0.5, 0.8), vec3(1.0), t);
}

// ============================================================
// Main
// ============================================================
void main() {
    // --- Step 1: Generate the ray for this pixel ---
    //
    // Each pixel on screen corresponds to a direction in 3D space.
    // We use the inverse view-projection matrix to unproject the
    // pixel's NDC coordinate back to a world-space point on the
    // near plane. The ray direction is from camera to that point.

    vec2 ndc = fragTexCoord * 2.0 - 1.0;       // [0,1] -> [-1,1]
    vec4 clipPos = vec4(ndc, -1.0, 1.0);
    vec4 worldPos4 = invViewProj * clipPos;
    vec3 worldPos = worldPos4.xyz / worldPos4.w;

    vec3 rayOrigin = cameraPosition;
    vec3 rayDir = normalize(worldPos - cameraPosition);

    // --- Step 2: Test intersection with the sphere ---

    float tHit;
    vec3 hitNormal;
    vec3 color;

    if (intersectSphere(rayOrigin, rayDir, sphereCenter, sphereRadius, tHit, hitNormal)) {
        // Simple diffuse shading: dot(normal, light direction)
        vec3 lightDir = normalize(vec3(1.0, 1.0, 0.5));
        float diff = max(dot(hitNormal, lightDir), 0.0);
        float ambient = 0.15;
        color = sphereColor * (ambient + diff * 0.85);

        // --- Visualize the surface normal at the hit point ---
        vec3 hitPoint = rayOrigin + rayDir * tHit;
        vec4 normalArrow = vizArrow(gl_FragCoord.xy, hitPoint,
                                     hitNormal, 0.6,
                                     viewProj, resolution,
                                     vec3(1.0, 1.0, 0.0), 2.0);
        color = vizComposite(color, normalArrow);
    } else {
        color = skyColor(rayDir);
    }

    // --- Step 3: Overlay viz primitives ---

    vec2 px = gl_FragCoord.xy;

    // Show XYZ axes at the world origin so we have spatial reference
    vec4 axes = vizAxes(px, vec3(0.0), viewProj, resolution, 1.0, 2.0);
    color = vizComposite(color, axes);

    // Show the ray as a yellow arrow for pixels near the center of the screen.
    // We only draw it for a few specific "sample" rays so it's not overwhelming.
    // Pick 5 rays spread across the screen to visualize.
    vec2 samplePixels[5] = vec2[5](
        resolution * vec2(0.5, 0.5),   // center
        resolution * vec2(0.25, 0.25), // bottom-left quadrant
        resolution * vec2(0.75, 0.25), // bottom-right quadrant
        resolution * vec2(0.25, 0.75), // top-left quadrant
        resolution * vec2(0.75, 0.75)  // top-right quadrant
    );

    for (int i = 0; i < 5; i++) {
        // Reconstruct the ray for this sample pixel
        vec2 sampleNDC = (samplePixels[i] / resolution) * 2.0 - 1.0;
        vec4 sampleClip = vec4(sampleNDC, -1.0, 1.0);
        vec4 sampleWorld4 = invViewProj * sampleClip;
        vec3 sampleWorldPos = sampleWorld4.xyz / sampleWorld4.w;
        vec3 sampleDir = normalize(sampleWorldPos - cameraPosition);

        // Draw the ray as an arrow from camera origin in the ray direction
        float rayLen = 4.0;
        // If this sample ray hits the sphere, shorten to the hit distance
        float sHit;
        vec3 sNorm;
        if (intersectSphere(cameraPosition, sampleDir, sphereCenter, sphereRadius, sHit, sNorm)) {
            rayLen = sHit;
        }

        vec3 arrowColor = (i == 0) ? vec3(1.0, 1.0, 0.3) : vec3(0.3, 1.0, 0.6);
        vec4 rayArrow = vizArrow(px, cameraPosition, sampleDir, rayLen,
                                  viewProj, resolution, arrowColor, 1.5);
        color = vizComposite(color, rayArrow);
    }

    // Show the camera position as a bright dot
    vec4 camDot = vizPoint(px, cameraPosition, viewProj, resolution,
                           vec3(1.0, 1.0, 1.0), 5.0);
    color = vizComposite(color, camDot);

    // Show the sphere center as a dot
    vec4 centerDot = vizPoint(px, sphereCenter, viewProj, resolution,
                               vec3(1.0, 0.5, 0.0), 4.0);
    color = vizComposite(color, centerDot);

    // sRGB gamma (so colors look correct on screen)
    color = pow(max(color, 0.0), vec3(1.0 / 2.2));

    finalColor = vec4(color, 1.0);
}
