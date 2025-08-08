# Compiler
CC = gcc

# Target executable name
TARGET = raylib_c_project

# Source files
SRCS = main.c

# Compiler flags
# -Wall: Enable all warnings
# -Wextra: Enable extra warnings
# -O2: Optimization level 2
# -I/usr/local/include: Add Raylib include path (adjust if Raylib is elsewhere)
# -DPLATFORM_DESKTOP: Define platform (for Raylib, usually Desktop for standalone)
CFLAGS = -Wall -Wextra -O2 -I/usr/local/include -DPLATFORM_DESKTOP

# Linker flags
# -L/usr/local/lib: Add Raylib library path (adjust if Raylib is elsewhere)
# -lraylib: Link with the Raylib library
# -lm: Link with the math library
# -lpthread: Link with pthread library (often needed by Raylib)
# -ldl: Link with dynamic linking library (often needed by Raylib)
# -lrt: Link with real-time extensions library (on some Linux systems)
# -lX11: Link with X11 library (on Linux for windowing)
# Note: For Windows or macOS, these linker flags might differ slightly.
#       For Windows (MinGW), it might be: -lraylib -lopengl32 -lgdi32 -lwinmm
#       For macOS, it might be: -lraylib -framework CoreVideo -framework IOKit -framework Cocoa -framework GLUT -framework OpenGL
LDFLAGS = -L/usr/local/lib -lraylib -lm -lpthread -ldl -lrt -lX11

# Web target settings
EMCC = emcc
WEB_DIR = web
WEB_TARGET = $(WEB_DIR)/index.html
# Path to your raylib web build (directory that contains libraylib.a)
# Example: /home/USER/repos/raylib/src
RAYLIB_WEB_SRC ?= /home/thiago/Documents/raylib/src
RAYLIB_WEB_LIB := $(RAYLIB_WEB_SRC)/libraylib.web.a

# Emscripten flags targeting WebGL 1.0 (OpenGL ES 2.0)
CFLAGS_WEB = -Os -I$(RAYLIB_WEB_SRC) -DPLATFORM_WEB -s USE_GLFW=3 -s MIN_WEBGL_VERSION=1 -s MAX_WEBGL_VERSION=1 -s ALLOW_MEMORY_GROWTH=1
LDFLAGS_WEB = $(RAYLIB_WEB_LIB) --preload-file shaders -s USE_GLFW=3 -s MIN_WEBGL_VERSION=1 -s MAX_WEBGL_VERSION=1 -s ALLOW_MEMORY_GROWTH=1 -s FORCE_FILESYSTEM=1

# Default target
all: $(TARGET)

# Rule to link the executable
$(TARGET): $(SRCS)
	$(CC) $(SRCS) -o $(TARGET) $(CFLAGS) $(LDFLAGS)

# Rule to clean build artifacts
clean:
	rm -f $(TARGET) *.o

# Rule to run the executable (optional)
run: $(TARGET)
	./$(TARGET)

# Build WebAssembly version using WebGPU
web: $(WEB_TARGET)

$(WEB_TARGET): main_web.c
	mkdir -p $(WEB_DIR)
	$(EMCC) main_web.c -o $(WEB_TARGET) $(CFLAGS_WEB) $(LDFLAGS_WEB)

# Phony targets (targets that are not files)
.PHONY: all clean run web
