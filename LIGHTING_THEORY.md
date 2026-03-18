# Lighting Theory for the Ray Tracer

This document covers the math behind 8 lighting features you can add to the fragment shader ray tracer. Each section describes the physical intuition, the key equations, and how the feature plugs into the existing bounce loop.

Throughout the document, these symbols are reused:

- **P** — the hit point on a surface
- **N** — the unit outward normal at P
- **V** — the unit vector from P toward the camera (view direction)
- **L** — the unit vector from P toward a light source
- **R** — a reflected or refracted direction

---

## 1. Shadow Rays

### Intuition

Right now the shader adds directional light contribution unconditionally at the end of the bounce loop. In reality, a point should only receive direct light if nothing blocks the path between it and the light source. A **shadow ray** tests exactly that.

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

### Connection to existing shader

The shader already has `intersectSphere`. You'd call it for the shadow ray before adding `dirlight1`'s contribution. The only new concept is the bias offset **εN** which you already use (0.0001) when spawning bounce rays.

---

## 2. Point Lights

### Intuition

A directional light has a fixed direction everywhere — like sunlight. A **point light** has a position in the world, so its direction and intensity vary with distance.

### Math

- **P** — the hit point on a surface
- **N** — the unit outward normal at P
- **V** — the unit vector from P toward the camera (view direction)
- **L** — the unit vector from P toward a light source
- **R** — a reflected or refracted direction

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

   where k_linear and k_quadratic are tunable constants.

4. **Diffuse contribution (Lambertian):**

   ```
   diffuse = C_light · attenuation · max(N · L, 0)
   ```

5. **Shadow test range:** When casting a shadow ray toward a point light, you only count hits with **0 < t < d** (not beyond the light).

### Connection to existing shader

Replace the single `DirectionalLight` struct with a `PointLight` struct carrying `position`, `color`, `intensity`, and attenuation constants. Compute **L** per-hit-point instead of using a global direction.

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

### Connection to existing shader

You already have `randomOnHemisphere` which gives uniform hemisphere samples. For AO, fire K short rays (length ≤ r_max) from each hit point and count how many are blocked. Multiply the surface color by the resulting AO factor (1.0 = fully open, 0.0 = fully occluded).

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
   outColor += accumulatedColor · (E · s)
   ```

2. An emissive surface can also reflect — if you want a glowing mirror, continue bouncing. If it's a pure light source (like a lamp), terminate the ray after adding emission.

### Connection to existing shader

Add a material type (e.g., material == 2 for emissive). In the bounce loop, when you detect this material, add the emission contribution to `outColor` scaled by `accumulatedColor`. You can optionally terminate the ray or let it continue bouncing for combined emissive+reflective surfaces.

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

To **sample a point P' on a disk light**: pick random u₁, u₂ ∈ [0,1), then:

```
θ = 2π · u₁
ρ = r_light · sqrt(u₂)        (sqrt for uniform distribution over area)
P' = P_light + ρ · (cos θ · T + sin θ · B)
```

where **T** and **B** are tangent and bitangent vectors of the disk.

To **sample a point on a sphere light**: use uniform sphere sampling and keep only the hemisphere facing the shading point, or use the solid-angle sampling formula for better efficiency.

Each sample fires a shadow ray from **P** toward **P'_j**. The fraction that are unoccluded determines the shadow softness.

### Connection to existing shader

Replace the single shadow ray from Section 1 with M jittered shadow rays toward random points on the light's surface. Average the results. More samples = smoother penumbra but higher cost.

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

### Connection to existing shader

For Lambertian (material == 0) surfaces, after the diffuse bounce calculation, add the specular term using the direct light direction. You'd need to pass `n_s` and `k_s` per sphere (or as uniforms). This is additive to the existing diffuse computation.

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
- If **u < R(θ)** → reflect the ray (specular reflection)
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

### Connection to existing shader

Add material type == 2 (or 3, if 2 is emissive) for dielectric. In the bounce loop, when this material is hit, compute the refraction ratio, check for total internal reflection, evaluate Schlick, and stochastically choose reflect vs. refract. The existing RNG (`randomDouble`) provides the random threshold.

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

### Connection to existing shader

Apply these operations at the very end of `main()`, after averaging the samples and before writing to `gl_FragColor`. Remove the existing `clampColor` calls inside the bounce loop (let values exceed 1.0 during accumulation), and instead apply tone mapping + gamma as the final step.

---

## Summary Table

| Feature | Key equation | Main new concept |
|---|---|---|
| Shadow rays | Reuse intersection test for shadow ray | Visibility function V(P, L) |
| Point lights | attenuation = I₀ / d² | Per-hit light direction + falloff |
| Ambient occlusion | AO = (1/K) Σ V(P, ωᵢ) | Monte Carlo hemisphere visibility |
| Emissive materials | outColor += accumulated · E · s | L_emit term in rendering equation |
| Soft shadows | L = (A/M) Σ Lₑ · G · V | Jittered samples on light surface |
| Blinn-Phong specular | k_s · (N · H)^n_s | Half-vector H = normalize(L + V) |
| Refraction | η₁ sin θ₁ = η₂ sin θ₂ + Schlick | Stochastic reflect/refract branching |
| Tone mapping + gamma | Reinhard: C/(1+C), then C^(1/2.2) | HDR compression before display |
