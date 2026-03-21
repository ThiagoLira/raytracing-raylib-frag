# Lighting Theory for the Ray Tracer

This document covers the math behind 9 lighting and rendering features for the fragment-shader ray tracer. Each section describes the physical intuition, the key equations, and a concrete implementation roadmap: which functions to write, which uniforms to add, and where in the existing code each feature plugs in.

**The goal is to teach — not to hand you the solution.** Every section tells you *what* to build and *why*, but writing the GLSL is your job.

## Codebase orientation

You will be editing two files:

- **`shaders/distance_web.glsl`** — the fragment shader where all ray tracing happens
- **`main_web.c`** — the C host that creates the window, manages uniforms, and drives the render loop

The shader already contains:
- A basic ray-sphere intersection (`intersectSphere`)
- A closest-hit loop (`findClosestHit`) that walks all spheres
- A bounce loop (`colorRayIterative`) that traces rays and accumulates color
- A direct lighting section inside the bounce loop that handles both directional and point lights
- Shadow ray testing using `findClosestHit` on a ray from the hit point toward each light
- A per-sphere getter (`getSphere`) and per-light getter (`getLight`) that work around WebGL 1.0's lack of dynamic array indexing
- Basic RNG (`randomDouble`, `randomOnHemisphere`) seeded from pixel position and time

**Lessons 1–2** explain features that are already present in the base shader. Read them to understand the code you're building on top of. **Lessons 3–9** are the features you will implement yourself.

Throughout the document, these symbols are reused:

- **P** — the hit point on a surface
- **N** — the unit outward normal at P
- **V** — the unit vector from P toward the camera (view direction)
- **L** — the unit vector from P toward a light source
- **R** — a reflected or refracted direction

---

## 1. Shadow Rays

### Intuition

A surface point should only receive direct light from a source if nothing blocks the path between them. A **shadow ray** tests exactly this: cast a ray from the hit point toward the light, and if it hits any geometry before reaching the light, the point is in shadow.

### Math

Given a hit point **P** with normal **N**, and a light direction **L** (unit vector toward the light):

1. Construct a shadow ray with origin **P + εN** (biased along the normal to avoid self-intersection; ε ≈ 0.001) and direction **L**.

2. Test this ray against every sphere in the scene using the same quadratic intersection:

   For a sphere with center **C** and radius **r**, the ray **P' + tL** intersects when:

   ```
   t = −(L · (P' − C)) ± sqrt( (L · (P' − C))² − |P' − C|² + r² )
   ```

   If any **t > 0** exists (and for directional lights, any positive t; for point lights, t must be less than the distance to the light), the point is in shadow.

3. If the shadow ray hits geometry → skip the direct light contribution for that light. If it reaches the light unobstructed → add the light contribution as before.

### What's already in the code

This feature is **already implemented** in the base shader. Look inside the light loop in `colorRayIterative`:

- A `shadowRay` is constructed with origin at `closestHit.hitPoint + closestHit.normal * 0.0001` — the **εN** bias prevents the ray from immediately hitting the surface it starts on (a visual artifact called **shadow acne**)
- `findClosestHit` is called on the shadow ray to check for blockers
- The boolean `inShadow` gates whether the light contribution is added to `outColor`
- The check `shadowHit.t < maxShadowDist` ensures that for point lights, only blockers *between* the surface and the light count as shadows (objects behind the light don't cast shadow)

**Why this matters for later lessons:** The shadow test currently uses `findClosestHit`, which computes the full closest intersection including material lookups. In lesson 3 (AO) and lesson 5 (soft shadows), you'll fire many short rays per pixel. At that point, you'll want a cheaper helper — `anyHitWithin(ray, maxDist)` — that returns `true` at the first intersection without bothering to find the closest or look up materials.

**Try this to verify you understand:** Temporarily comment out the shadow test (make `inShadow` always false) and observe how the scene looks without shadows. Then put it back.

---

## 2. Point Lights

### Intuition

A directional light has a fixed direction everywhere — like sunlight. A **point light** has a position in the world, so its direction and intensity vary with distance.

### Math

Given a point light at position **P_light** with color **C_light** and intensity **I₀**:

1. **Direction to light:**

   ```
   L = normalize(P_light − P)
   ```

2. **Distance:**

   ```
   d = |P_light − P|
   ```

3. **Attenuation (inverse-square law):**

   Light intensity falls off with the square of the distance. The physically correct attenuation is:

   ```
   attenuation = I₀ / (d²)
   ```

   In practice a clamped version avoids division-by-near-zero and allows artistic control:

   ```
   attenuation = I₀ / (1 + k_linear · d + k_quadratic · d²)
   ```

   where `k_linear` and `k_quadratic` are tunable constants (already declared as uniforms in the shader).

4. **Diffuse contribution (Lambertian):**

   ```
   diffuse = C_light · attenuation · max(N · L, 0)
   ```

5. **Shadow test range:** When casting a shadow ray toward a point light, you only count hits with **0 < t < d** (not beyond the light). This is the `maxShadowDist` variable.

### What's already in the code

This feature is **already implemented** in the base shader. Inside the light loop:

- The `Light` struct uses a `type` field: 0 = directional, 1 = point
- The `if (lType == 1)` branch computes `toLight`, `attIntensity`, and `maxShadowDist` from the light's position
- The attenuation formula uses the `k_linear` and `k_quadratic` uniforms, set from the C side with defaults of 0.09 and 0.032
- The `else` branch handles directional lights: `toLight = normalize(-lDir)`, no attenuation, infinite `maxShadowDist`

**Key architectural detail:** The light loop is designed so that `toLight`, `attIntensity`, and `maxShadowDist` are filled differently depending on `lType`, but the shadow test and Lambertian diffuse calculation after the type switch are shared. This means later features (specular, soft shadows) can also be written once and work for both light types.

**Try this:** In the C code, change the light from directional (`type = 0`) to point (`type = 1`) and give it a position. Watch how the shading changes: the light direction now varies across the surface, and distant surfaces are dimmer.

---

## 3. Ambient Occlusion

### Intuition

Corners, crevices, and contact points between objects receive less indirect light because nearby geometry blocks many incoming directions. **Ambient occlusion** (AO) approximates this by measuring how "open" the hemisphere above a surface point is.

### Math

The ambient occlusion at point **P** with normal **N** is the integral of visibility over the hemisphere:

```
AO(P) = (1 / π) ∫_Ω V(P, ω) · (N · ω) dω
```

where:
- **Ω** is the hemisphere oriented around **N**
- **ω** is a direction on that hemisphere
- **V(P, ω)** = 1 if a ray from P in direction ω does NOT hit anything within a small radius **r_max**, 0 otherwise
- **(N · ω)** is a cosine weighting (directions glancing along the surface matter less)

**Monte Carlo estimator** with K samples:

```
AO(P) ≈ (1 / K) Σ_{i=1}^{K} V(P, ω_i)
```

where each **ω_i** is a cosine-weighted random direction on the hemisphere (the cosine weighting cancels the (N · ω) / π factor when you importance-sample).

To generate a **cosine-weighted** direction: pick two uniform random numbers u₁, u₂ ∈ [0,1), then in the local tangent frame:

```
x = cos(2π · u₁) · sqrt(u₂)
y = sin(2π · u₁) · sqrt(u₂)
z = sqrt(1 − u₂)
```

Transform (x, y, z) from the tangent frame (where N = (0,0,1)) to world space using a tangent/bitangent/normal basis.

**r_max** controls the occlusion radius — how far away geometry can be and still count as occluding. Short rays (small r_max) give contact shadows; longer rays give broader darkening.

### Building the tangent frame

To transform from the tangent frame to world space, you need an orthonormal basis (tangent **T**, bitangent **B**, normal **N**). A standard approach:

1. Pick an "up" vector that isn't parallel to **N** — typically `(0, 1, 0)`, but fall back to `(1, 0, 0)` when **N** is nearly vertical (check `abs(N.y) < 0.999`)
2. **T** = normalize(cross(up, **N**))
3. **B** = cross(**N**, **T**)

Then the world-space direction is: **T** · x + **B** · y + **N** · z.

### Implementation roadmap

**New defines:**
- `AO_SAMPLES` — how many hemisphere rays to fire (4 is a good starting point; temporal accumulation in lesson 9 will smooth it out)

**New uniforms (shader):**
- `aoRadius` (float) — maximum ray distance for occlusion test
- `aoStrength` (float) — 0.0 = no AO, 1.0 = full AO

**New functions (shader):**

1. `cosineWeightedHemisphere(normal, seed)` → vec3 — generates a cosine-weighted random direction in the hemisphere around `normal`. This uses the tangent frame construction above. The base shader already has `randomOnHemisphere` which gives uniform samples, but cosine-weighted is better for AO because it matches the physical integral and reduces variance for the same sample count.

2. `anyHitWithin(ray, maxDist)` → bool — tests the ray against all spheres and returns `true` as soon as any intersection with `0 < t < maxDist` is found. Unlike `findClosestHit`, this doesn't need to find the *closest* hit or look up materials — it exits early at the first blocker. You will reuse this function for shadow testing in lesson 5.

3. `computeAO(hitPoint, normal, seed)` → float — fires `AO_SAMPLES` rays from `hitPoint` in cosine-weighted directions, counts how many are blocked within `aoRadius`, and returns the occlusion factor. A return value of 1.0 means fully open; 0.0 means fully occluded.

**Where in the bounce loop:**
- Call `computeAO` once per hit, *before* the light loop
- Multiply the result into both the ambient term and the direct lighting contribution
- For performance, only compute AO on the first few bounces (e.g., `depth < 3`) — deeper bounces contribute less to the final image and aren't worth the extra rays

**On the C side:**
- Add `aoRadius` and `aoStrength` to `AppState`
- Look up their shader locations in `InitApp`
- Set reasonable defaults (e.g., 0.5 and 0.5)
- Send them via `SetShaderValue`

**Early return optimization:** If `aoStrength` is zero, `computeAO` should return 1.0 immediately without firing any rays.

**Common mistake:** Using `randomOnHemisphere` instead of `cosineWeightedHemisphere`. The uniform version wastes samples at glancing angles and produces noisier results for the same sample count.

**How to verify:** Place two spheres close together (touching or nearly touching). You should see a darkening in the crevice between them. Set `aoStrength` to 1.0 to make it dramatic, then dial it back.

---

## 4. Emissive Materials

### Intuition

Some objects glow — lava, neon lights, light bulbs. An **emissive** surface adds its own light at the hit point regardless of incoming illumination. Because the ray tracer already bounces rays, an emissive sphere will naturally illuminate nearby surfaces through those bounces.

### Math

The rendering equation for a surface point is:

```
L_out(P, V) = L_emit(P, V) + ∫_Ω f(ω_i, V) · L_in(P, ω_i) · (N · ω_i) dω_i
```

where:
- **L_emit(P, V)** is the emitted radiance (non-zero only for emissive materials)
- **f(ω_i, V)** is the BRDF (bidirectional reflectance distribution function)
- **L_in** is the incoming radiance from direction ω_i

For a path tracer, at each bounce:

```
color_at_this_bounce = emission + attenuation · color_of_next_bounce
```

Concretely, in the iterative loop:

1. When a ray hits an emissive surface with emission color **E** and emission strength **s**:

   ```
   outColor += throughput · (E · s)
   ```

   where `throughput` is the accumulated product of all surface colors along the ray path (called `accumulatedColor` in the base shader).

2. An emissive surface can also reflect — if you want a glowing mirror, continue bouncing. If it's a pure light source (like a lamp), terminate the ray after adding emission.

### Implementation roadmap

**New material type:** material == 2 for emissive.

**New per-sphere uniforms:**
- `u_s*_emission` (vec3) — emission color (e.g., warm orange: (1.0, 0.8, 0.3))
- `u_s*_emissionStrength` (float) — intensity multiplier (values > 1.0 make it glow brighter)

**Shader changes:**

1. Expand the sphere getter function to return emission fields alongside color and material. The current `getSphere` returns (center, radius, color, material). You'll need to either expand it or split it into a geometry getter and a material getter — the latter approach avoids re-fetching geometry data in the shadow/AO helpers that only need position and radius.

2. In `colorRayIterative`, after fetching the hit material but *before* the direct lighting loop: add `throughput * emission * emissionStrength` to `outColor`. This should happen regardless of material type — non-emissive spheres will just have `emissionStrength = 0`.

3. After adding emission, if `material == 2`: `break` out of the bounce loop. A pure emissive surface is a light source; it doesn't reflect or scatter.

**C side:**
- Add `emission` (Vector3) and `emissionStrength` (float) fields to the `Sphere` struct
- Add setter/getter functions for the JS API if needed
- Write a `MakeEmissive(pos, radius, color, emissionColor, emissionStrength)` helper for convenience
- Update `SetSceneUniforms` to send the new per-sphere fields

**How to verify:** Create a small sphere with high `emissionStrength` (e.g., 5.0) near a diffuse surface. The diffuse surface should pick up color from the emissive sphere via bounced rays. The emissive sphere itself should appear bright regardless of whether any lights illuminate it.

**Common mistake:** Adding emission *after* the direct lighting loop or *after* the material type check. Emission should be added first, unconditionally, so that even the first bounce captures it.

---

## 5. Soft Shadows and Area Lights

### Intuition

Real lights have physical size. The larger the light source, the softer the shadow edges (penumbra). A point on the surface may "see" part of the light (partial shadow / penumbra) or none of it (full shadow / umbra).

### Math

Model the light as a disk or sphere with center **P_light**, normal **N_light** (for a disk), and radius **r_light**.

The direct illumination integral over the light surface A is:

```
L_direct(P) = ∫_A L_e · G(P, P') · V(P, P') dA'
```

where:
- **P'** is a point on the light surface
- **L_e** is the light's emitted radiance
- **V(P, P')** is 1 if P and P' can see each other, 0 otherwise
- **G(P, P')** is the geometry term:

```
G(P, P') = max(N · L', 0) · max(N_light · (−L'), 0) / |P − P'|²
```

with **L' = normalize(P' − P)**.

**Monte Carlo estimator** with M samples:

```
L_direct(P) ≈ (A / M) Σ_{j=1}^{M} L_e · G(P, P'_j) · V(P, P'_j)
```

In practice, the implementation is much simpler than this integral suggests. Rather than formally evaluating the geometry term, you **jitter the shadow ray targets**:

- **Point light:** pick M random points near the light position (within a sphere of radius `r_light`), cast shadow rays toward each, and average the visibility
- **Directional light:** add small random perturbations to the light direction

The fraction of unoccluded rays becomes the **shadow factor** — 0.0 = fully shadowed, 1.0 = fully lit, values in between = penumbra.

### Implementation roadmap

**New defines:**
- `SOFT_SHADOW_SAMPLES` — how many jittered shadow rays to fire (4 is a good starting point)

**New per-light uniform:**
- `u_l*_radius` (float) — the physical radius of the light. 0.0 = point source (hard shadow, single ray). Larger values = wider penumbra.

**New function (shader):**

`computeShadowFactor(hitPoint, normal, toLight, maxDist, lightPos, lightRadius, lightType, seed)` → float

This replaces the existing single shadow ray test in the light loop. The logic:

1. If `lightRadius ≤ 0.001`: fall back to a single hard shadow ray (exactly what lesson 1 already does). Return 0.0 or 1.0.

2. If `lightRadius > 0.001`: fire `SOFT_SHADOW_SAMPLES` jittered shadow rays. For each sample:
   - Generate a random 3D jitter vector scaled by `lightRadius`
   - For point lights: add the jitter to `lightPos` to get a jittered target, compute direction and distance from `hitPoint` to that target
   - For directional lights: add a small fraction of the jitter to `toLight` and renormalize
   - Cast the shadow ray using `anyHitWithin` (from lesson 3)
   - Count unoccluded rays

3. Return the fraction of unoccluded rays.

**Where in the bounce loop:**
- Replace the existing `inShadow` boolean check with a call to `computeShadowFactor`
- Multiply the light contribution (diffuse + specular) by the returned factor instead of gating with an if/else

**C side:**
- Add `radius` (float) to the `Light` struct
- Update `SetLightUniforms` and the getter/setter API to handle the new field
- A directional light with radius 0.0 behaves identically to before (backward compatible)

**How to verify:** Give a point light a radius of 0.3–0.5. The shadow edges should become soft and blurry instead of razor-sharp. Moving the light further from the surface should make shadows softer (the light subtends a larger angle). With radius 0.0 the shadow should be hard, identical to before.

**Common mistake:** Using `findClosestHit` instead of `anyHitWithin` for the shadow samples. With multiple lights and multiple samples each, this function gets called many times per pixel — the early-exit optimization from lesson 3 matters here.

---

## 6. Specular Highlights (Blinn-Phong)

### Intuition

Lambertian surfaces look uniformly matte. Real surfaces — plastic, wet paint, polished wood — show a bright highlight where the light reflection aligns with your eye. The **Blinn-Phong** model adds this cheaply.

### Math

Given:
- **N** — surface normal
- **L** — unit direction toward the light
- **V** — unit direction toward the camera
- **n_s** — shininess exponent (higher = tighter highlight; 1–2 = very rough, 256+ = mirror-like)

Compute the **half-vector**:

```
H = normalize(L + V)
```

The specular term is:

```
specular = k_s · max(N · H, 0)^(n_s)
```

where **k_s** is the specular reflectance coefficient (0 to 1).

The full Blinn-Phong shading at a point:

```
color = k_a · ambient
      + k_d · C_surface · max(N · L, 0)          ← diffuse (Lambertian)
      + k_s · C_light  · max(N · H, 0)^(n_s)     ← specular
```

where k_a + k_d + k_s ≤ 1 to conserve energy (approximately).

**Energy conservation note:** The raw Blinn-Phong model is not energy-conserving. A simple normalization factor is:

```
specular_normalized = ((n_s + 2) / (2π)) · max(N · H, 0)^(n_s)
```

This ensures the total reflected energy doesn't exceed the incoming energy regardless of shininess.

### Implementation roadmap

**New per-sphere uniforms:**
- `u_s*_specular` (float) — the k_s coefficient. 0.0 = no specular. Good defaults: 0.05 for matte plastic, 0.5–0.8 for metal.
- `u_s*_shininess` (float) — the n_s exponent. Good defaults: 32 for soft highlights, 128–256 for sharp ones.

**Where in the bounce loop:**

Specular goes *inside* the light loop, computed alongside diffuse — not after it. The steps:

1. **Before the light loop:** Compute the view direction **V** = `normalize(cameraPosition - hitPoint)`. The `cameraPosition` is already available as a uniform.

2. **Inside the light loop**, after computing the diffuse term and the shadow factor:
   - Compute the half-vector **H** = `normalize(toLight + V)`
   - Compute `NdotH = max(dot(normal, H), 0.0)`
   - Apply the normalization factor: `(shininess + 2.0) / (2.0 * PI)`
   - The specular color uses the **light** color, not the surface color — specular highlights show the color of the light source, not the material
   - Gate the specular by the same shadow factor as diffuse (shadowed areas shouldn't have specular highlights)
   - Add both terms together: `throughput * (diffuse + specular) * shadow * ao`

**C side:**
- Add `specular` (float) and `shininess` (float) to the `Sphere` struct
- Update `SetSceneUniforms` to send them
- Set sensible defaults per material type

**Common mistakes:**
- Using the surface color for specular instead of the light color — highlights should show the color of the light
- Computing specular outside the light loop — you need the per-light direction **L** to compute **H**
- Forgetting to guard with `hitSpec > 0.0 && hitShine > 0.0` to skip the computation when specular isn't configured

**How to verify:** Set a sphere to have specular = 0.5, shininess = 128. Orbit the camera — you should see a bright, tight highlight that moves as the viewing angle changes. Lower the shininess to 8 and the highlight should become broad and soft.

---

## 7. Refraction (Snell's Law + Fresnel)

### Intuition

Transparent materials like glass or water bend light as it enters and exits. The bending angle depends on the ratio of refractive indices. At shallow angles, more light reflects than refracts (the Fresnel effect — think of a lake being mirror-like at grazing angles).

### Math

#### Snell's Law

When a ray crosses from a medium with refractive index **η₁** into one with index **η₂**:

```
η₁ · sin(θ₁) = η₂ · sin(θ₂)
```

where θ₁ is the angle of incidence and θ₂ is the angle of refraction, both measured from the normal.

The refracted direction vector **T** given incident direction **D** (pointing into the surface) and normal **N**:

```
η = η₁ / η₂
cos(θ₁) = −(N · D)
sin²(θ₂) = η² · (1 − cos²(θ₁))
```

If **sin²(θ₂) > 1** → **total internal reflection** (no refraction possible; the ray reflects entirely). Otherwise:

```
T = η · D + (η · cos(θ₁) − sqrt(1 − sin²(θ₂))) · N
```

Common refractive indices: air ≈ 1.0, glass ≈ 1.5, water ≈ 1.33, diamond ≈ 2.42.

#### Determining inside vs. outside

When a ray hits a sphere, check the dot product **D · N**:
- If **D · N < 0**: ray is entering the sphere (outside → inside). Use η = η_air / η_material. Normal stays as-is.
- If **D · N > 0**: ray is exiting the sphere (inside → outside). Use η = η_material / η_air. Flip the normal: N = −N.

#### Fresnel Reflectance (Schlick Approximation)

The fraction of light reflected (vs. refracted) depends on the angle. The exact Fresnel equations are complex, but **Schlick's approximation** is:

```
R₀ = ((η₁ − η₂) / (η₁ + η₂))²
R(θ) = R₀ + (1 − R₀) · (1 − cos θ)⁵
```

where **cos θ** = |N · D| (use the refracted angle's cosine if entering a denser medium).

**R(θ)** is the probability of reflection. At each hit:
- Generate a random number **u ∈ [0, 1)**
- If **u < R(θ)** or if total internal reflection → reflect the ray
- Otherwise → refract the ray using direction **T**

This stochastic branching naturally produces the correct blend of reflection and refraction over many samples.

#### Putting it together for a glass sphere

A glass sphere is a **dielectric**. When a ray hits it:
1. Determine if entering or exiting (flip normal + swap η ratio accordingly)
2. Compute sin²(θ₂). If > 1 → total internal reflection → reflect.
3. Otherwise compute Fresnel reflectance R(θ) via Schlick.
4. Randomly choose reflect or refract based on R(θ).
5. Spawn the new ray from P + εN (reflected) or P − εN (refracted, biased INTO the surface).
6. Attenuation for clear glass is (1, 1, 1) — glass doesn't absorb. Tinted glass multiplies by a color.

### Implementation roadmap

**New material type:** material == 3 for dielectric (glass). Material 2 is already taken by emissive.

**New per-sphere uniform:**
- `u_s*_ior` (float) — index of refraction. 1.5 for glass, 1.33 for water, 2.42 for diamond.

**GLSL built-ins you should use:**
- `reflect(D, N)` — computes the reflection of direction D about normal N. Don't rewrite this by hand.
- `refract(D, N, eta)` — computes the refracted direction using Snell's law. Returns `vec3(0)` on total internal reflection in some implementations, but you should check for TIR explicitly using the sin²(θ₂) > 1 condition before calling it.

**New function (shader):**

`scatterDielectric(currentRay, hit, ior, seed, scattered, attenuation)` — determines whether the ray reflects or refracts, and outputs the scattered ray and attenuation.

The logic, step by step:
1. Normalize the incoming ray direction
2. Check `dot(unitDir, hit.normal)` to determine inside vs. outside. If positive (exiting): flip normal, set `etaRatio = ior`. If negative (entering): keep normal, set `etaRatio = 1.0 / ior`.
3. Compute cos(θ) and sin²(θ₂)
4. Compute Schlick reflectance R₀ from `etaRatio`, then R(θ) using cos(θ)
5. If total internal reflection OR `randomDouble(seed) < R(θ)`: reflect. Spawn ray from `hitPoint + normal * ε`.
6. Otherwise: refract. Spawn ray from `hitPoint - normal * ε` (biased *into* the surface).
7. Set attenuation to `vec3(1.0)` for clear glass.

**Where in the bounce loop:**

In the scatter section at the bottom of the loop (where metal and Lambertian are already handled), add a branch for `material == 3` that calls `scatterDielectric` instead of the existing scatter logic.

**C side:**
- Add `ior` (float) to the `Sphere` struct (default 1.5)
- Add a `MakeGlass(pos, radius, tint, ior)` helper
- Update setters/getters and `SetSceneUniforms`

**Critical detail — the ray spawn bias:**
- Reflection: offset along **+N** (away from the surface, into the medium the ray came from)
- Refraction: offset along **−N** (into the surface, into the medium the ray is entering)

Getting this wrong produces black spots, incorrect self-shadowing, or the refracted ray immediately re-hitting the same surface.

**How to verify:** Create a glass sphere (ior = 1.5) on a colored ground plane. You should see:
- The ground visible through the sphere, but distorted (refraction)
- A bright reflection of the sky/lights on the sphere surface (Fresnel)
- At grazing angles (edges of the sphere), more reflection than refraction
- If you set ior = 1.0, the sphere should become invisible (no bending)

---

## 8. Tone Mapping and Gamma Correction

### Intuition

The ray tracer accumulates radiance values that can exceed 1.0 (especially with multiple lights, emissives, or many bounces). Simply clamping to [0,1] loses detail in bright areas. **Tone mapping** compresses the high dynamic range (HDR) into displayable range [0,1] while preserving detail. **Gamma correction** accounts for the nonlinear response of monitors.

### Math

#### Reinhard Tone Mapping

The simplest global operator. For each color channel independently:

```
C_mapped = C / (1 + C)
```

This maps [0, ∞) → [0, 1) smoothly. Dark values (C << 1) are nearly unchanged; bright values are compressed.

An extended version with a white point **W** (the luminance that maps to pure white):

```
C_mapped = C · (1 + C / W²) / (1 + C)
```

#### ACES Filmic Tone Mapping

A curve fitted to the Academy Color Encoding System, widely used in games and film. For each channel:

```
C_mapped = (C · (2.51 · C + 0.03)) / (C · (2.43 · C + 0.59) + 0.14)
```

This is a rational polynomial that produces a gentle shoulder (highlight rolloff) and a slight toe (shadow lift), giving a more filmic, pleasing look than Reinhard.

#### Gamma Correction

Monitors apply a nonlinear transfer function (approximately power 2.2) to pixel values. If you output linear values, the image looks too dark. To compensate, apply the inverse:

```
C_display = C_linear ^ (1 / 2.2)
```

This is applied **after** tone mapping, as the final step before writing the output color.

#### Full pipeline

The order matters:

```
1. Raw HDR color from ray tracing        →  C_hdr
2. Tone map (Reinhard or ACES)           →  C_mapped = tonemap(C_hdr)
3. Clamp to [0, 1]                       →  C_clamped = clamp(C_mapped, 0, 1)
4. Gamma correct                         →  C_final = C_clamped ^ (1/2.2)
5. Output                                →  fragColor = vec4(C_final, 1.0)
```

### Implementation roadmap

**New uniform:**
- `toneMapMode` (int) — 0 = no tone mapping, 1 = Reinhard, 2 = ACES. This lets you toggle between methods at runtime.

**New functions (shader):**
- `tonemapReinhard(c)` → vec3 — applies the Reinhard operator per channel
- `tonemapACES(c)` → vec3 — applies the ACES filmic curve per channel
- `gammaCorrect(c)` → vec3 — applies gamma correction: `pow(max(c, 0.0), vec3(1.0 / 2.2))`

**Where this goes:**

At the very end of `main()`, after the multi-sample average is computed and before writing to `gl_FragColor`:

1. Apply tone mapping based on `toneMapMode`
2. Clamp to [0, 1]
3. Apply gamma correction
4. Write to `gl_FragColor`

**Important:** Do NOT clamp colors inside the bounce loop. Let HDR values exceed 1.0 during accumulation — that's the whole point. Tone mapping at the end compresses them gracefully.

**C side:**
- Add `toneMapMode` (int) to `AppState`
- Look up the shader location in `InitApp`
- Set a default (2 for ACES is a good choice)
- Expose getter/setter for the UI

**How to verify:** Create a bright emissive sphere (`emissionStrength = 10`). Without tone mapping (mode 0), the area around it will blow out to white. With Reinhard (mode 1), the bright areas compress but darks stay. With ACES (mode 2), you get richer contrast with a filmic look. Toggle gamma correction off (temporarily output linear values) — the whole image will look unnaturally dark, which proves gamma is working.

**Common mistake:** Applying gamma correction inside the bounce loop or before tone mapping. Gamma is always the very last step before output. Everything up to that point operates in linear space.

---

## 9. Temporal Accumulation and Denoising

### Intuition

By this point you have three sources of Monte Carlo noise in your ray tracer: ambient occlusion (lesson 3), soft shadows (lesson 5), and stochastic refraction (lesson 7). Each of these fires a small number of random rays per pixel per frame and averages the results. With only K = 4 samples, the image looks grainy — individual pixels "guess" different random directions each frame, producing visible speckle.

Monte Carlo noise decreases as **1 / √N**, where N is the total number of samples. To halve the noise you need 4× as many samples. Raising the per-frame sample count (say from 4 to 64) works but kills performance. A much better strategy: **accumulate samples across frames**. Each frame contributes 1 new sample, and the running average over N frames converges to a clean image — giving you the quality of N samples per pixel at the cost of only 1 sample per frame.

### Math

#### Running average

Given a sequence of per-pixel color samples **C₁, C₂, …, Cₙ** from N successive frames, the Monte Carlo estimate is:

```
C̄ₙ = (1/N) Σᵢ₌₁ᴺ Cᵢ
```

This can be computed **incrementally** without storing all previous samples:

```
C̄ₙ = C̄ₙ₋₁ + (1/N)(Cₙ − C̄ₙ₋₁)
     = mix(C̄ₙ₋₁, Cₙ, 1/N)
```

Each frame you blend the new sample with the accumulated result using weight **α = 1/N**. As N grows, each new sample has less influence and the image converges.

#### Gamma-correct accumulation

Accumulation must happen in **linear** color space. If the stored buffer contains gamma-corrected values (as it will, since your output goes through gamma correction before display), you must undo the gamma before blending and reapply it after:

```
C_linear_prev = C_stored ^ 2.2        ← un-gamma
C_linear_new  = tonemap(raytrace())    ← new sample (linear, tone-mapped)
C_blended     = mix(C_linear_prev, C_linear_new, 1/N)
C_stored      = C_blended ^ (1/2.2)   ← re-gamma for storage and display
```

Averaging gamma-corrected values directly (skipping the un-gamma / re-gamma) produces visible brightness errors — dark areas appear too dark and gradients show banding.

#### Ping-pong buffers

You cannot read from and write to the same texture in the same draw call (this is undefined behavior in OpenGL / WebGL). The solution is **ping-pong**: maintain two off-screen textures A and B.

```
Frame 1: read nothing        → write result to A
Frame 2: read A as input     → write blended result to B
Frame 3: read B as input     → write blended result to A
Frame 4: read A as input     → write blended result to B
...
```

Each frame, swap which buffer is read and which is written. Display whichever was most recently written.

#### When to reset

The accumulated average is only valid while the scene is static. When anything changes — camera position, sphere properties, light settings — the old accumulation is stale. Reset the frame counter to 1 so the next frame writes a fresh sample with no blending.

### RNG quality

The accumulation exposes a hidden problem: **seed quality**. The common GLSL pattern:

```
seed = fract(sin(seed * 12.9898) * 43758.5453);
return seed;
```

feeds each output back as the next input, creating a 1D feedback loop. This produces correlated sequences — adjacent pixels get similar random numbers, and patterns emerge across frames. Two improvements fix this:

**1. Counter-based RNG.** Instead of feeding the output back, increment a counter and hash it. The counter guarantees the input to the hash is always different. The hash is used as a pure function, not a feedback loop. Your `randomDouble` function should increment `currentSeed` by a fixed amount (e.g., 1.0), then hash the counter to get a return value.

**2. Per-pixel, per-frame seed initialization.** Use a 2D hash of the pixel position to decorrelate pixels, and vary by frame count to decorrelate frames. A good 2D → 1D hash (Dave Hoskins' "Hash without Sine") avoids precision issues that the `sin`-based hash can have on some GPUs:

```
float hash12(vec2 p) {
    vec3 p3 = fract(vec3(p.xyx) * 0.1031);
    p3 += dot(p3, p3.yzx + 33.33);
    return fract((p3.x + p3.y) * p3.z);
}
```

Combine: `seed = hash12(gl_FragCoord.xy) * large_number + float(frameCount) * irrational_offset`

This ensures every pixel on every frame starts from a unique, well-distributed seed.

### Sub-pixel jitter (anti-aliasing)

With only 1 sample per pixel per frame, you also get free anti-aliasing by **jittering** the ray within the pixel. Each frame, offset the screen coordinate by a random amount in the range ±0.5 pixels before unprojecting:

```
vec2 pixelSize = 2.0 / resolution;   // size of one pixel in NDC space
vec2 jitter = (vec2(rand(), rand()) - 0.5) * pixelSize;
vec2 ndc = fragTexCoord * 2.0 - 1.0 + jitter;
```

Over many accumulated frames, the jittered samples cover the full pixel area, smoothing edges and sub-pixel detail without any additional cost. Note that the jitter must be in NDC space (where the full screen spans -1 to +1), not in world space — the original shader's jitter values of ~1e-10 are far too small to have any effect.

### Implementation roadmap

This lesson requires changes on **both** the shader and the C/host side.

**New uniforms (shader):**
- `frameCount` (int) — how many frames have been accumulated
- `accumTexture` (sampler2D) — the previous frame's accumulated result, bound as a second texture
- `resolution` (vec2) — screen dimensions in pixels, needed for proper sub-pixel jitter

**Shader changes:**

1. Add the `hash12` function and rewrite `randomDouble` to use a counter-based approach: increment the seed by 1.0 each call, then hash it, instead of feeding the output back.

2. Replace the initial seed calculation. Instead of `gl_FragCoord.x * 0.123 + gl_FragCoord.y * 0.456 + time`, use `hash12(gl_FragCoord.xy)` combined with `frameCount`.

3. Replace the multi-sample loop (currently 4 or 8 `samples_per_pixel`) with a **single sample** per frame, but with proper sub-pixel jitter on the NDC coordinates before unprojecting.

4. In `main()`, after tone mapping and clamping but *before* gamma correction:
   - If `frameCount > 1`: read the previous frame from `accumTexture` using `texture2D`, un-gamma it (raise to power 2.2), and `mix` with the new linear sample using blend factor `1.0 / float(frameCount)`
   - Apply gamma correction to the blended result

5. Cap the blend factor denominator at some maximum (e.g., 512) to prevent floating-point precision issues at very high frame counts.

**C side — the ping-pong setup:**

1. **AppState additions:** Two `RenderTexture2D` buffers (the ping-pong pair), an `accumIndex` (int — which buffer was last written), `frameCount` (int), shader locations for `frameCount`, `accumTexture`, and `resolution`, and a `prevCamPos` (Vector3) for change detection.

2. **In `InitApp`:** Create both accumulation textures at screen resolution using `LoadRenderTexture`. Look up the three new shader locations. Send the `resolution` uniform once (it doesn't change).

3. **Reset `frameCount` to 0** in `SetSceneUniforms`, `SetLightUniforms`, and `SetRenderUniforms` — these are already called whenever anything in the scene changes, so one line in each resets the accumulation automatically.

4. **In `UpdateDrawFrame`:** Before rendering, compare `camera.position` with `prevCamPos` — if different, reset `frameCount` to 0 and save the new position. Increment `frameCount` and send it to the shader. Bind the *read* accumulation texture using `SetShaderValueTexture`. Render the raytrace pass into the *write* accumulation texture using `BeginTextureMode`. Swap `accumIndex`. Display the latest accumulation texture to screen.

**How to verify:** Run the app and hold the camera still. The image should start noisy and progressively become clean over 1–2 seconds. Move the camera — the image should reset to noisy and converge again. If it doesn't converge, the accumulation blending or the frameCount reset is wrong. If it converges but has brightness errors, you're probably averaging in gamma space (forgot the un-gamma step).

**Common mistakes:**
- Accumulating in gamma space (averaging gamma-corrected values without the un-gamma / re-gamma round trip)
- Forgetting to reset `frameCount` when the scene changes — the accumulated image smears old frames into new
- Using the same texture for both read and write in a single draw call (undefined behavior in OpenGL/WebGL)
- Using `time` as the only source of seed variation — frames close in time get near-identical seeds and don't contribute new information

---

## Summary Table

| # | Feature | Key equation | Main new concept |
|---|---|---|---|
| 1 | Shadow rays | Reuse intersection test for shadow ray | Visibility function V(P, L) |
| 2 | Point lights | attenuation = I₀ / (1 + k₁d + k₂d²) | Per-hit light direction + falloff |
| 3 | Ambient occlusion | AO = (1/K) Σ V(P, ωᵢ) | Monte Carlo hemisphere visibility |
| 4 | Emissive materials | outColor += throughput · E · s | L_emit term in rendering equation |
| 5 | Soft shadows | shadow = (1/M) Σ V(P, P'ⱼ) | Jittered samples toward light surface |
| 6 | Blinn-Phong specular | k_s · ((n_s+2)/2π) · (N · H)^n_s | Half-vector H = normalize(L + V) |
| 7 | Refraction | η₁ sin θ₁ = η₂ sin θ₂ + Schlick | Stochastic reflect/refract branching |
| 8 | Tone mapping + gamma | Reinhard: C/(1+C), then C^(1/2.2) | HDR compression before display |
| 9 | Temporal accumulation | C̄ₙ = mix(C̄ₙ₋₁, Cₙ, 1/N) | Running average + ping-pong buffers |
