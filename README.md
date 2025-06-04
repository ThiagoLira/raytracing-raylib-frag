# Raytracing Raylib Fragment Shader

This project is a minimal C program that demonstrates how to combine [raylib](https://www.raylib.com/) with a GLSL fragment shader to produce a simple ray tracing effect.

The program renders a basic 3D scene of spheres using raylib. A custom shader located at `shaders/distance.glsl` performs iterative ray tracing in screen space. The executable draws the scene to a texture, then applies the fragment shader in a second pass.

## Building

A `Makefile` is provided. You need raylib and a C compiler installed. On many Linux distributions you can install the library with `libraylib-dev`.

```bash
make       # builds `raylib_c_project`
make run   # builds and runs the program
```

Alternatively, `./run.sh` cleans, rebuilds and runs the program.

## Files

- `main.c` – sets up the window, camera and shader, then renders the scene.
- `shaders/distance.glsl` – GLSL fragment shader implementing the ray tracing effect.
- `Makefile` – simple build script.
- `run.sh` – helper script to build and run.

## Usage

Run the executable after building. A window opens showing the ray‑traced spheres. Use the mouse to orbit the camera.

## License

This repository does not currently declare a license. Use at your own discretion.
