# Lesson 7: Glass & Refraction

When light enters a transparent material, it bends. This is refraction, governed by Snell's Law. The amount of bending depends on the Index of Refraction (IOR) — higher IOR = more bending.

## What you'll learn

- **Snell's Law**: `n1 * sin(theta1) = n2 * sin(theta2)`. Air has IOR ~1.0, glass ~1.5, diamond ~2.42.
- **Total internal reflection**: when going from glass to air at a steep angle, refraction becomes mathematically impossible (`sin(theta) > 1`). All light reflects. This is why diamonds sparkle.
- **Fresnel effect**: even when refraction is possible, the reflect/refract ratio depends on the viewing angle. At grazing angles, almost everything reflects. Schlick's approximation models this cheaply.
- **The glass scattering function**: randomly choose reflect or refract based on the Fresnel probability. Offset the scattered ray slightly to avoid self-intersection.

## What to look at

Colored spheres sit behind the glass sphere — you can see refraction distorting them. Toggle between reflection only (1), refraction only (2), and full Fresnel (3) to understand each component.

Adjust IOR with +/- to see how bending changes. The HUD shows common reference values (water 1.33, glass 1.5, diamond 2.42). At high IOR, the glass sphere acts almost like a lens.

## Controls

| Key | Action |
|-----|--------|
| 1 | Reflection only |
| 2 | Refraction only |
| 3 | Full Fresnel (realistic) |
| +/- | Adjust IOR (1.0 to 2.5) |
| Right-click drag | Orbit camera |
| Scroll wheel | Zoom |

## Build & run

```
make run
```
