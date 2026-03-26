# Lesson 3: Random Numbers on the GPU

Path tracing is a Monte Carlo method — it relies on random sampling to approximate lighting. But GPUs don't have `rand()`. We have to build our own.

## What you'll learn

- **PCG hash**: a function that scrambles any integer into a pseudorandom integer. Feed it pixel coordinates and you get unique noise per pixel.
- **Determinism**: same input = same output. This isn't a bug, it's essential for reproducibility.
- **Seeding**: by mixing the frame number into the seed, each frame gets different noise. This is what makes temporal accumulation work (lesson 9).

## What to look at

- **Mode 1 (static)**: the noise pattern never changes — same seed, same output, every frame. This proves the hash is deterministic.
- **Mode 2 (animated)**: the frame counter is mixed into the seed, so every frame looks different. This is what the raytracer actually uses.
- **Mode 3 (unit vectors)**: `randomUnitVec3()` generates directions on the sphere, mapped to RGB. This previews how we'll scatter rays in lesson 4.

## Controls

| Key | Action |
|-----|--------|
| 1 | Static noise |
| 2 | Animated noise |
| 3 | Random unit vectors as color |

## Build & run

```
make run
```
