// ============================================================
// VIZ PRIMITIVES — SDF-based vector/point/axis drawing for lessons
// ============================================================
//
// Pure functions that project 3D geometry to screen space and
// render it as colored overlays using signed distance fields.
//
// Usage: call draw*() functions, each returns vec4(rgb, alpha).
// Composite over your scene color with:
//   vec4 overlay = drawArrow(...);
//   color = mix(color, overlay.rgb, overlay.a);
//
// Requires these uniforms to be available:
//   uniform mat4 viewProj;    // view * projection matrix
//   uniform vec2 resolution;  // screen size in pixels

// --- Projection utility ---

// Project a 3D world position to screen UV [0,1] space.
// Returns vec3(u, v, depth). depth < 0 means behind camera.
vec3 projectToScreen(vec3 worldPos, mat4 mvp, vec2 res) {
    vec4 clip = mvp * vec4(worldPos, 1.0);
    if (clip.w <= 0.0) return vec3(-1.0, -1.0, -1.0); // behind camera
    vec3 ndc = clip.xyz / clip.w;
    // NDC [-1,1] -> UV [0,1], flip Y for screen convention
    return vec3(ndc.xy * 0.5 + 0.5, ndc.z);
}

// --- SDF helpers ---

// Distance from point p to line segment (a, b), in 2D screen pixels.
float sdSegment(vec2 p, vec2 a, vec2 b) {
    vec2 pa = p - a, ba = b - a;
    float h = clamp(dot(pa, ba) / dot(ba, ba), 0.0, 1.0);
    return length(pa - ba * h);
}

// Distance from point p to a triangle defined by 3 vertices (2D).
// Used for arrowheads.
float sdTriangle(vec2 p, vec2 a, vec2 b, vec2 c) {
    vec2 e0 = b - a, e1 = c - b, e2 = a - c;
    vec2 v0 = p - a, v1 = p - b, v2 = p - c;

    vec2 pq0 = v0 - e0 * clamp(dot(v0, e0) / dot(e0, e0), 0.0, 1.0);
    vec2 pq1 = v1 - e1 * clamp(dot(v1, e1) / dot(e1, e1), 0.0, 1.0);
    vec2 pq2 = v2 - e2 * clamp(dot(v2, e2) / dot(e2, e2), 0.0, 1.0);

    float s = sign(e0.x * e2.y - e0.y * e2.x);
    vec2 d = min(min(
        vec2(dot(pq0, pq0), s * (v0.x * e0.y - v0.y * e0.x)),
        vec2(dot(pq1, pq1), s * (v1.x * e1.y - v1.y * e1.x))),
        vec2(dot(pq2, pq2), s * (v2.x * e2.y - v2.y * e2.x)));

    return -sqrt(d.x) * sign(d.y);
}

// Soft edge: convert SDF distance to alpha with antialiasing
float edgeAlpha(float dist, float thickness) {
    return 1.0 - smoothstep(thickness - 1.0, thickness + 1.0, dist);
}

// --- Drawing functions ---
// All return vec4(color.rgb, alpha) for compositing.
// `pixelCoord` is gl_FragCoord.xy (pixel coordinates, origin bottom-left).

// Draw a filled circle at a 3D world position.
vec4 vizPoint(vec2 pixelCoord, vec3 worldPos, mat4 mvp, vec2 res,
              vec3 color, float radiusPx) {
    vec3 sp = projectToScreen(worldPos, mvp, res);
    if (sp.z < 0.0) return vec4(0.0);
    vec2 screenPx = sp.xy * res;
    float dist = length(pixelCoord - screenPx);
    float alpha = edgeAlpha(dist, radiusPx);
    return vec4(color, alpha);
}

// Draw a line segment between two 3D world positions.
vec4 vizLine(vec2 pixelCoord, vec3 worldA, vec3 worldB, mat4 mvp, vec2 res,
             vec3 color, float thicknessPx) {
    vec3 spA = projectToScreen(worldA, mvp, res);
    vec3 spB = projectToScreen(worldB, mvp, res);
    if (spA.z < 0.0 && spB.z < 0.0) return vec4(0.0);
    vec2 pxA = spA.xy * res;
    vec2 pxB = spB.xy * res;
    float dist = sdSegment(pixelCoord, pxA, pxB);
    float alpha = edgeAlpha(dist, thicknessPx);
    return vec4(color, alpha);
}

// Draw an arrow: line + triangular arrowhead.
// `origin` is the tail, arrow points in `direction` for `len` world units.
vec4 vizArrow(vec2 pixelCoord, vec3 origin, vec3 direction, float len,
              mat4 mvp, vec2 res, vec3 color, float thicknessPx) {
    vec3 dir = normalize(direction);
    vec3 tip = origin + dir * len;
    vec3 shaftEnd = origin + dir * (len * 0.82); // shaft stops before tip

    // Shaft line
    vec4 shaft = vizLine(pixelCoord, origin, shaftEnd, mvp, res, color, thicknessPx);

    // Arrowhead triangle
    vec3 spTip = projectToScreen(tip, mvp, res);
    vec3 spBase = projectToScreen(shaftEnd, mvp, res);
    if (spTip.z < 0.0) return shaft;

    vec2 pxTip = spTip.xy * res;
    vec2 pxBase = spBase.xy * res;
    vec2 fwd = pxTip - pxBase;
    float fwdLen = length(fwd);
    if (fwdLen < 1.0) return shaft;
    fwd /= fwdLen;
    vec2 perp = vec2(-fwd.y, fwd.x);

    float headWidth = thicknessPx * 3.0;
    vec2 left  = pxBase - perp * headWidth;
    vec2 right = pxBase + perp * headWidth;

    float triDist = sdTriangle(pixelCoord, pxTip, left, right);
    float headAlpha = 1.0 - smoothstep(-1.0, 1.0, triDist);

    // Combine shaft + head
    float alpha = max(shaft.a, headAlpha);
    return vec4(color, alpha);
}

// Draw RGB-colored XYZ axes at a world origin.
// Returns the combined overlay of all three axes.
vec4 vizAxes(vec2 pixelCoord, vec3 origin, mat4 mvp, vec2 res,
             float scale, float thicknessPx) {
    vec4 xAxis = vizArrow(pixelCoord, origin, vec3(1, 0, 0), scale,
                          mvp, res, vec3(1.0, 0.2, 0.2), thicknessPx);
    vec4 yAxis = vizArrow(pixelCoord, origin, vec3(0, 1, 0), scale,
                          mvp, res, vec3(0.2, 1.0, 0.2), thicknessPx);
    vec4 zAxis = vizArrow(pixelCoord, origin, vec3(0, 0, 1), scale,
                          mvp, res, vec3(0.3, 0.4, 1.0), thicknessPx);

    // Layer: X on bottom, Y middle, Z on top
    vec3 c = vec3(0.0);
    float a = 0.0;
    // X
    c = mix(c, xAxis.rgb, xAxis.a);
    a = max(a, xAxis.a);
    // Y
    c = mix(c, yAxis.rgb, yAxis.a);
    a = max(a, yAxis.a);
    // Z
    c = mix(c, zAxis.rgb, zAxis.a);
    a = max(a, zAxis.a);
    return vec4(c, a);
}

// Draw a ground-plane grid (Y=0 plane) — projects world-space grid lines.
// Draws `count` lines in X and Z directions centered at origin.
vec4 vizGrid(vec2 pixelCoord, mat4 mvp, vec2 res,
             float spacing, int count, vec3 color, float thicknessPx) {
    float halfExtent = spacing * float(count);
    float bestAlpha = 0.0;

    for (int i = -count; i <= count; i++) {
        float offset = float(i) * spacing;
        // Z-parallel lines (along Z axis)
        vec4 zLine = vizLine(pixelCoord,
            vec3(offset, 0.0, -halfExtent),
            vec3(offset, 0.0,  halfExtent),
            mvp, res, color, thicknessPx);
        bestAlpha = max(bestAlpha, zLine.a);
        // X-parallel lines (along X axis)
        vec4 xLine = vizLine(pixelCoord,
            vec3(-halfExtent, 0.0, offset),
            vec3( halfExtent, 0.0, offset),
            mvp, res, color, thicknessPx);
        bestAlpha = max(bestAlpha, xLine.a);
    }
    return vec4(color, bestAlpha);
}

// --- Compositing helper ---
// Apply an overlay on top of existing scene color.
vec3 vizComposite(vec3 sceneColor, vec4 overlay) {
    return mix(sceneColor, overlay.rgb, overlay.a);
}

// ============================================================
// END VIZ PRIMITIVES
// ============================================================
