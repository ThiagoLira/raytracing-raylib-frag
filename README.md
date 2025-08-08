# Raytracing Raylib Fragment Shader

This project is a minimal C program that demonstrates how to combine [raylib](https://www.raylib.com/) with a GLSL fragment shader to produce a simple ray tracing effect.

The program renders a basic 3D scene of spheres using raylib. A custom shader located at `shaders/distance.glsl` performs iterative ray tracing in screen space. The executable draws the scene to a texture, then applies the fragment shader in a second pass.

## Building

A `Makefile` is provided. You need raylib and a C compiler installed. On many Linux distributions you can install the library with `libraylib-dev`.

```bash
make       # builds `raylib_c_project`
make run   # builds and runs the program
make web   # builds a WebAssembly/WebGPU version
```

Alternatively, `./run.sh` cleans, rebuilds and runs the program.

### Building for the web (WebGL 1.0 via Emscripten)

raylib’s web backend targets WebGL 1.0 (OpenGL ES 2.0) via Emscripten. We provide a separate entry point `main_web.c` and a WebGL 1.0 shader `shaders/distance_web.glsl`.

Follow these steps on Arch Linux:

1) Install prerequisites

```bash
sudo pacman -S --needed git python \
  base-devel # if you don’t have build tools
```

2) Install Emscripten SDK

```bash
cd ~
git clone https://github.com/emscripten-core/emsdk.git
cd emsdk
./emsdk install latest
./emsdk activate latest
source ./emsdk_env.sh
# To make it permanent, add the following to your shell profile (~/.bashrc or ~/.config/fish/config.fish):
#   source ~/emsdk/emsdk_env.sh
```

3) Build raylib for web

```bash
cd ~
git clone https://github.com/raysan5/raylib.git
cd raylib/src
make -e PLATFORM=PLATFORM_WEB -B
# After success, you should have: ~/raylib/src/libraylib.a
```

4) Configure this project to use your raylib web build

Edit the `Makefile` and set the absolute path to your `raylib/src` as `RAYLIB_WEB_SRC`. Example:

```make
RAYLIB_WEB_SRC ?= /home/USER/raylib/src
```

5) Build web target

```bash
source ~/emsdk/emsdk_env.sh   # ensure emcc is on PATH in this shell
make clean
make web
```

This generates `web/index.html` and accompanying files, preloading the `shaders` directory.

6) Serve locally

```bash
cd web
python -m http.server 8000
# open http://localhost:8000 in a WebGL 1.0 capable browser
```

Notes:
- The web build compiles `main_web.c` and uses `shaders/distance_web.glsl` (GLSL ES 1.00) for WebGL 1.0.
- If you see shader compilation errors, ensure your GPU/browser supports WebGL 1.0 and that the shader version/qualifiers match GLSL ES 1.00.
- Based on guidance for web builds from community resources such as Stack Overflow [“How to make a HTML build from raylib”](https://stackoverflow.com/questions/67989952/how-to-make-a-html-build-from-raylib).

## Files

- `main.c` – sets up the window, camera and shader, then renders the scene.
- `shaders/distance.glsl` – GLSL fragment shader implementing the ray tracing effect.
- `Makefile` – simple build script.
- `run.sh` – helper script to build and run.

## Usage

Run the executable after building. A window opens showing the ray‑traced spheres. Use the mouse to orbit the camera.

## Demo



https://github.com/user-attachments/assets/71b209e4-12d8-42e7-9fa4-3d737641d1c9



## License

This repository does not currently declare a license. Use at your own discretion.
