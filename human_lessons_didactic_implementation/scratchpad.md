# Scratchpad — Lesson 2: Point Lights

## What's done (boilerplate, I did this)
- C side: `DirLight` → `Light` struct with `type` (0=dir, 1=point) and `position`
- C side: `SetLightUniforms()` sends type + position to shader
- C side: JS API getters/setters for type and position
- C side: initial light stays type=0 (directional) — nothing breaks
- Shader: `u_l{i}_type` and `u_l{i}_position` uniforms added
- Shader: `getLight()` returns type + position
- Shader: lighting loop restructured with if/else branching, directional path preserved

## What's left (student exercise)
The `if (lType == 1)` block in the lighting loop has 4 placeholder lines.
The student needs to fill in:
1. `toLight` — normalized vector from hit point to light position
2. `d` — distance from hit point to light position
3. `attIntensity` — apply attenuation formula using d
4. `maxShadowDist` — set to d so shadow ray is bounded

All 4 lines use concepts from LIGHTING_THEORY.md Section 2.

## Progress
- [x] C-side plumbing
- [x] Shader uniform plumbing
- [x] Lighting loop restructured with directional path intact
- [ ] Student fills in point light block (Exercise A+B+C combined)
