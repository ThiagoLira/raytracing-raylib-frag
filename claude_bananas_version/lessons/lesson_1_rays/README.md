# Lesson 1: From Pixels to Rays

The fundamental question of ray tracing: **how does a 2D pixel on your screen become a 3D ray in the world?**

Answer: a pipeline of coordinate transforms. This lesson lets you **see each stage** by coloring every pixel according to its coordinates at that step.

## The pipeline

```
Screen UV [0,1]          ← what the GPU gives you (fragTexCoord)
    │
    │  * 2 - 1
    ▼
NDC [-1,1]               ← centered, camera looks at (0,0)
    │
    │  invViewProj *      ← THE KEY STEP: a matrix "unprojects" 2D → 3D
    ▼
World position (x,y,z)   ← a point in 3D space on the camera's near plane
    │
    │  normalize(worldPos - cameraPos)
    ▼
Ray direction (unit vec)  ← the direction this pixel should look
```

## What to look at

Press 1-6 to step through the pipeline:

| Stage | What you see | What it teaches |
|-------|-------------|-----------------|
| **1. UV** | Red/green gradient | The GPU gives each pixel a (u,v) from (0,0) to (1,1) |
| **2. NDC** | Centered gradient + crosshair | Remap to (-1,1) so the center pixel = origin |
| **3. World pos** | Colorful pattern that changes when you orbit | The inverse view-projection matrix turns 2D screen coords into 3D world coords. **Orbit the camera** to see the same pixel map to a different world position! |
| **4. Ray dir** | Smooth color field | Each pixel's ray direction as RGB. Center = forward, edges = the field-of-view fan |
| **5. Depth** | White sphere on dark background | How far the ray traveled — a depth buffer. Close = bright, far = dark, miss = navy |
| **6. Full raytrace** | Shaded sphere with arrows | The complete pipeline end-to-end: pixel → ray → intersection → shading |

The most important moment is **stage 3**: orbit the camera and watch the colors change. That's the matrix at work — same pixel, different viewpoint, different world position.

## Controls

| Key | Action |
|-----|--------|
| 1-6 | Switch pipeline stage |
| Right-click drag | Orbit camera |
| Scroll wheel | Zoom |

## Build & run

```
make run
```
