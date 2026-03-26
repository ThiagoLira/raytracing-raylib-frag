# Claude Goes Bananas: GPU Path Tracer

> **Disclaimer:** The rest of this repo (`human_lessons_didactic_implementation/`) is a carefully hand-written, step-by-step educational ray tracer. This folder is... not that. I gave [Claude Code](https://claude.ai/claude-code) the keys and said "go nuts." This is what happened in one session.

## What Is This

A real-time Monte Carlo path tracer running entirely in a WebGL 2.0 fragment shader, built on [raylib](https://www.raylib.com/). It renders physically-based materials, global illumination, and a cinematic procedural sky — all at interactive framerates in a browser.

Everything here was written by Claude (Opus 4.6) in a single conversation, extending the original raylib GPU ray marcher from the didactic version into something... significantly more ambitious.

## Features

- **WebGL 2.0 / GLSL ES 3.00** with scene data packed into RGBA32F textures
- **Cook-Torrance GGX microfacet BRDF** with importance sampling (replaces Blinn-Phong)
- **Multiple Importance Sampling (MIS)** with power heuristic for emissive primitives
- **Next Event Estimation (NEE)** — direct sampling of emissive lights (quad + sphere solid angle)
- **Multi-primitive support** — spheres, quads, triangles, boxes (6-quad construction)
- **AgX tone mapping** (Blender 3.6+ standard) + Reinhard + ACES, with exposure control
- **Procedural golden hour sky** with sun disk, bloom halo, and atmospheric gradient
- **Linear HDR accumulation** in RGBA16F with no-black-flash temporal blending
- **PCG integer RNG** replacing sin-hash (no correlation artifacts)
- **Multi-SPP rendering** (1-64 samples per frame, adjustable)
- **Adaptive AO** — disabled during camera motion for responsiveness
- **Scene presets** — cinematic default scene + Cornell Box
- **Interactive web UI** — orbit camera, sphere picking/dragging, material editing, metal presets (Gold/Copper/Silver/Iron)
- **Ludicrous mode** — uncap FPS to let beefy GPUs eat

## Performance

Optimized with:
- 8-wide horizontal scene texture layout (GPU cache-friendly)
- Bounding sphere pre-rejection for shadow/AO rays on quads/triangles
- Dedicated closest-hit vs any-hit trace functions
- Sphere normal via division-by-radius (no `normalize()`)
- Fresnel via multiply chain (no `pow()`)
- Single texelFetch for NEE emission (was 3)

Result: **2x FPS improvement** over naive implementation (26 FPS -> 57 FPS at 16 SPP, 1280x720).

## Building

### Prerequisites

- [raylib](https://www.raylib.com/) source (for headers)
- [Emscripten](https://emscripten.org/) SDK (for web build)

### Build raylib for WebGL 2.0

```bash
cd /path/to/raylib/src
make PLATFORM=PLATFORM_WEB GRAPHICS=GRAPHICS_API_OPENGL_ES3 -j$(nproc)
```

### Build the path tracer

Edit the `Makefile` to point `RAYLIB_WEB_SRC` to your raylib source directory, then:

```bash
# Web build (WebGL 2.0)
make web

# Native build (desktop OpenGL 3.3)
make

# Serve locally
cd web && python3 -m http.server 8080
# Open http://localhost:8080
```

## Files

| File | Lines | What |
|------|-------|------|
| `main_web.c` | ~950 | Host application: scene management, camera, texture packing, render loop, Emscripten JS API |
| `shaders/raytrace.glsl` | ~850 | The entire path tracer: intersection, GGX BRDF, MIS/NEE, environment, accumulation |
| `shaders/display.glsl` | ~90 | Display pass: AgX/ACES/Reinhard tone mapping + sRGB gamma + exposure |
| `shell.html` | ~650 | Web UI: sidebar controls, scene presets, material editing |
| `Makefile` | ~80 | Build config for native + Emscripten |

## The Cinematic Default Scene

The default scene is a golden hour composition:
- Hollow glass sphere center stage (double-sphere trick for realistic bubble)
- Mirror chrome and polished gold heroes flanking
- Three deliberate emissive accents (amber backlight, cyan floor reflection, magenta rim)
- Cinematic 3-point lighting (warm key, cool fill, warm rim)
- Dark mirror floor catching all the colored light bounces
- Low camera angle — hero shot perspective

## How It Differs From the Didactic Version

| | Didactic (`human_lessons_didactic_implementation/`) | Claude Bananas (`claude_bananas_version/`) |
|---|---|---|
| **Purpose** | Learn ray tracing step by step | Push the GPU as far as it goes |
| **Written by** | Human (me), carefully | Claude, in one session |
| **Approach** | One feature at a time, explained | Everything at once, optimized |
| **Materials** | Blinn-Phong | Cook-Torrance GGX PBR |
| **Lighting** | Direct + simple shadows | MIS + NEE + solid angle sampling |
| **Tone mapping** | Reinhard/ACES | AgX (Blender standard) |
| **Scene data** | Per-sphere uniforms | Texture-packed, cache-optimized |
| **WebGL** | 1.0 | 2.0 (GLSL ES 3.00) |
