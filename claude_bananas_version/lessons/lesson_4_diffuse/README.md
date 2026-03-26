# Lesson 4: Diffuse Reflection & Hemisphere Sampling

A matte (Lambertian) surface scatters incoming light in all directions above the surface. To render it, we pick a random direction and keep tracing. But *how* we pick that direction matters a lot.

## What you'll learn

- **Uniform hemisphere sampling**: every direction above the surface is equally likely. Simple, but wastes samples on shallow angles that contribute little light.
- **Cosine-weighted hemisphere sampling**: biases toward the normal. Matches Lambert's cosine law, so the cos(theta) in the rendering equation cancels with the PDF. Less noise for free.
- **Why cosine is better**: with uniform sampling, you must multiply by `cos(theta) * 2pi`. With cosine sampling, the math simplifies to just `albedo * incoming_light`. Same result, less variance.

## What to look at

Toggle between uniform (1) and cosine-weighted (2) at the same SPP. Cosine-weighted produces a noticeably cleaner image. Increase SPP with +/- to see both converge to the same result (just at different speeds).

The scene has two matte spheres on a ground plane, lit only by the sky. All the light comes from random scatter — there are no explicit light sources.

## Controls

| Key | Action |
|-----|--------|
| 1 | Uniform hemisphere sampling |
| 2 | Cosine-weighted hemisphere sampling |
| +/- | Adjust samples per pixel (1, 4, 16, 64) |
| Right-click drag | Orbit camera |
| Scroll wheel | Zoom |

## Build & run

```
make run
```
