# Raytracing Raylib Fragment Shader

A real-time ray tracer built with [raylib](https://www.raylib.com/) and GLSL fragment shaders. This repo contains three versions: a hand-written educational implementation (with it's accompaining AI-generated reference implementation) and another AI-generated version that went... significantly further.


https://github.com/user-attachments/assets/12de5811-e995-49a6-97a3-4ef701aead94



## Versions

### [`human_lessons_didactic_implementation/`](human_lessons_didactic_implementation/)

The original — a carefully hand-written, step-by-step ray tracer built for learning. WebGL 1.0, Blinn-Phong materials, interactive scene editor. Each feature was added incrementally with a companion [LIGHTING_THEORY.md](human_lessons_didactic_implementation/LIGHTING_THEORY.md) explaining the math.

### [`vibe_coded_reference_implementation/`](vibe_coded_reference_implementation/)

First AI-assisted version. It is the vibe coded version implementing everything from the original plan of the lessons for the human version in one-shot.

### [`claude_bananas_version/`](claude_bananas_version/)

I gave [Claude Code](https://claude.ai/claude-code) the keys and said "go nuts." In one session it rewrote the renderer into a full Monte Carlo path tracer:

- **WebGL 2.0** with scene data in RGBA32F textures
- **Cook-Torrance GGX** microfacet BRDF (replaces Blinn-Phong)
- **MIS + NEE** (Multiple Importance Sampling + Next Event Estimation)
- **AgX tone mapping** (Blender 3.6+ standard)
- **Procedural golden hour sky** with sun bloom
- **Multi-SPP** (1-64 samples/frame), temporal accumulation
- **Cache-optimized** 8-wide texture layout, bounding sphere rejection

See the [full README](claude_bananas_version/README.md) for details.

## Quick Start

```bash
# Build raylib for WebGL 2.0
cd /path/to/raylib/src
make PLATFORM=PLATFORM_WEB GRAPHICS=GRAPHICS_API_OPENGL_ES3 -j$(nproc)

# Build the Claude version
cd claude_bananas_version
# Edit Makefile: set RAYLIB_WEB_SRC to your raylib/src path
make web

# Serve
cd web && python3 -m http.server 8080
# Open http://localhost:8080
```

## Controls

| Action | Input |
|---|---|
| Orbit camera | Right-click + drag |
| Zoom | Scroll wheel |
| Select sphere | Left-click |
| Move sphere | Left-click + drag |
| Add/delete/edit | Sidebar panel |

## Original Demo (Human Version)

https://github.com/user-attachments/assets/71b209e4-12d8-42e7-9fa4-3d737641d1c9

## License

This repository does not currently declare a license. Use at your own discretion.
