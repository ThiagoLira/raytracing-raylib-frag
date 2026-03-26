# Lesson 6: PBR Metals — Microfacet Theory

Real metal surfaces are covered in microscopic bumps (microfacets). Each one is a tiny mirror, but they point in different directions. The rougher the surface, the more random their orientations, and the blurrier the reflection.

## What you'll learn

- **GGX Normal Distribution (D)**: describes how microfacets are oriented. Low roughness = tight peak (mirror). High roughness = broad distribution (blurry).
- **Fresnel-Schlick (F)**: metals reflect more light at grazing angles. Gold looks more golden head-on, but reflects white at the edges.
- **Smith masking-shadowing (G)**: microfacets can block each other. Tall bumps cast shadows on their neighbors, reducing the overall reflectance at steep angles.
- **GGX importance sampling**: instead of random directions, we sample where the GGX distribution is large — dramatically reducing noise for sharp reflections.

## What to look at

Seven metal spheres sit in a row, from mirror-smooth (left) to very rough (right). The colors go from gold to gunmetal. Use left/right arrows to select a sphere — a ring highlights it and shows a dot whose size represents the roughness.

Notice how the leftmost sphere shows sharp sky reflections while the rightmost is a diffuse blur. The checkerboard ground helps visualize the reflection quality.

## Controls

| Key | Action |
|-----|--------|
| Left/Right | Select sphere |
| Right-click drag | Orbit camera |
| Scroll wheel | Zoom |

## Build & run

```
make run
```
