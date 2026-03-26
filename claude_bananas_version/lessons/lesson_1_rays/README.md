# Lesson 1: What Is a Ray?

A ray has two parts: an **origin** (where it starts) and a **direction** (where it's heading). The entire raytracer is built on this idea — for every pixel on screen, we shoot a ray from the camera into the scene and ask "what did it hit?"

## What you'll learn

- How screen pixels map to 3D rays using the inverse view-projection matrix
- The `Ray` struct: `origin + t * direction` gives you any point along the ray
- Basic ray-sphere intersection (solving a quadratic equation)

## What to look at

The shader shows 5 sample rays as colored arrows from the camera into the scene. The yellow one goes through the center pixel, the green ones through the corners. When a ray hits the sphere, a yellow arrow shows the surface normal at the hit point.

Orbit the camera to see how the rays fan out from different viewpoints.

## Controls

| Key | Action |
|-----|--------|
| Right-click drag | Orbit camera |
| Scroll wheel | Zoom in/out |

## Build & run

```
make run
```
