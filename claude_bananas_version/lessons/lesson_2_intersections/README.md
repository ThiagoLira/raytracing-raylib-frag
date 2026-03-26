# Lesson 2: Ray-Shape Intersections

The raytracer supports three primitive shapes. Each one needs different math to answer "where does my ray hit this surface?"

## What you'll learn

- **Sphere**: substitute the ray equation into the sphere equation, get a quadratic. Discriminant tells you hit/miss.
- **Quad**: intersect with the plane, then check if the hit point falls inside the parallelogram using dual-basis projection.
- **Triangle** (Moller-Trumbore): solve for barycentric coordinates using cross products — no matrix inversion needed.

## What to look at

Three objects sit side by side: a coral sphere, a blue quad (wall panel), and an amber triangle. Yellow arrows show the surface normal at each shape. Press 1-4 to isolate individual shapes and study the intersection code for each one.

Notice how sphere normals vary across the surface, while the quad has a single uniform normal. The triangle vertices and edges are highlighted with dots and wireframe lines.

## Controls

| Key | Action |
|-----|--------|
| 1 | Show all shapes |
| 2 | Sphere only |
| 3 | Quad only |
| 4 | Triangle only |
| Right-click drag | Orbit camera |
| Scroll wheel | Zoom |

## Build & run

```
make run
```
