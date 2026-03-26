# Lesson 8: The Path Tracing Loop

This is where everything comes together. A "path" is a chain of ray bounces: camera hits a surface, scatters, hits another surface, scatters again, until it reaches a light or runs out of bounces.

## What you'll learn

- **The bounce loop**: at each hit, determine the material type (Lambertian/Metal/Glass), scatter accordingly, and multiply the throughput by the surface color.
- **Throughput**: tracks how much energy survives at each bounce. A red surface absorbs blue and green, so throughput becomes redder with each bounce. After many bounces, very little light gets through.
- **Russian Roulette**: instead of always doing max bounces, randomly terminate paths that carry little energy. Crucially, survivors are weighted by `1/probability` — making this an *unbiased* estimator (same expected value, less computation).
- **How bounces add light**: depth 1 = only direct emissive. Depth 2 = ceiling light illuminates surfaces. Depth 3 = colored walls bleed onto white surfaces. Each bounce captures more indirect illumination.

## What to look at

The scene is a Cornell box with red/green walls, a ceiling light, and three spheres (metal, glass, matte). Press 1-8 to set the max bounce depth and watch the image change:

- **Depth 1**: only the ceiling light is visible (emissive surface)
- **Depth 2**: surfaces lit by the ceiling light appear
- **Depth 3**: color bleeding from the red and green walls
- **Depth 4+**: subtle inter-reflections fill in

## Controls

| Key | Action |
|-----|--------|
| 1-8 | Set max bounce depth |
| Right-click drag | Orbit camera |
| Scroll wheel | Zoom |

## Build & run

```
make run
```
