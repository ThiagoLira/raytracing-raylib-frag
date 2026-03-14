# Raytracing Raylib Fragment Shader

A real-time ray tracer built with [raylib](https://www.raylib.com/) and GLSL, featuring an interactive web-based scene editor. The fragment shader performs iterative path tracing with support for Lambertian and metallic materials, directional lighting, and soft shadows.

## Features

- Path tracing with configurable bounce depth and multi-sample anti-aliasing
- Up to 10 spheres and 4 directional lights
- Interactive scene editor (web build):
  - Click to select spheres, drag to move them
  - Add/delete spheres from the sidebar
  - Color picker, material selector (Lambertian/Metal), radius slider
  - Light controls: color, intensity, direction
  - Orbital camera (right-click drag) with scroll zoom

## Building

### Web build (primary target)

The web build compiles to WebAssembly via Emscripten, targeting WebGL 1.0. It includes a custom HTML shell with a sidebar UI for scene editing.

#### Prerequisites

1. Install [Emscripten SDK](https://emscripten.org/docs/getting_started/downloads.html):

```bash
git clone https://github.com/emscripten-core/emsdk.git
cd emsdk
./emsdk install latest
./emsdk activate latest
source ./emsdk_env.sh
```

2. Build raylib for web:

```bash
git clone https://github.com/raysan5/raylib.git
cd raylib/src
make -e PLATFORM=PLATFORM_WEB -B
```

3. Set `RAYLIB_WEB_SRC` in the `Makefile` to point to your `raylib/src` directory:

```make
RAYLIB_WEB_SRC ?= /path/to/raylib/src
```

#### Build and run

```bash
source ~/emsdk/emsdk_env.sh
make clean && make web
python3 -m http.server -d web 8000
# open http://localhost:8000
```

### Desktop build (legacy)

Desktop source files are in `legacy_non_web/`. To build:

```bash
make   # builds raylib_c_project from legacy_non_web/main.c
```

Requires raylib installed locally (e.g. via Homebrew on macOS or `libraylib-dev` on Linux).

## Files

- `main_web.c` – web entry point with scene state, camera controls, sphere picking/dragging, and C API exported to JavaScript
- `shaders/distance_web.glsl` – GLSL ES 1.00 fragment shader (path tracing, up to 10 spheres + 4 lights)
- `shell.html` – custom Emscripten HTML shell with sidebar scene editor UI
- `Makefile` – build targets for desktop and web
- `legacy_non_web/` – original desktop-only `main.c` and `distance.glsl`

## Controls

| Action | Input |
|---|---|
| Orbit camera | Right-click + drag |
| Zoom | Scroll wheel |
| Select sphere | Left-click |
| Move sphere | Left-click + drag |
| Add/delete/edit | Sidebar panel |

## Demo



https://github.com/user-attachments/assets/71b209e4-12d8-42e7-9fa4-3d737641d1c9



## License

This repository does not currently declare a license. Use at your own discretion.
