# Compiler
CC = gcc

# Target executable name
TARGET = raylib_c_project

# Source files
SRCS = legacy_non_web/main.c

# Detect OS
UNAME_S := $(shell uname -s)

# Compiler flags (common)
CFLAGS = -Wall -Wextra -O2 -DPLATFORM_DESKTOP

# Platform-specific flags
ifeq ($(UNAME_S),Darwin)
    # macOS: use pkg-config for raylib paths (Homebrew)
    CFLAGS += $(shell pkg-config --cflags raylib)
    LDFLAGS = $(shell pkg-config --libs raylib) -framework CoreVideo -framework IOKit -framework Cocoa -framework OpenGL
else
    # Linux
    CFLAGS += -I/usr/local/include
    LDFLAGS = -L/usr/local/lib -lraylib -lm -lpthread -ldl -lrt -lX11
endif

# Web target settings
EMCC = emcc
WEB_DIR = web
WEB_TARGET = $(WEB_DIR)/index.html
# Path to your raylib web build (directory that contains libraylib.a)
# Example: /home/USER/repos/raylib/src
ifeq ($(UNAME_S),Darwin)
    RAYLIB_WEB_SRC ?= /tmp/raylib-web/src
else
    RAYLIB_WEB_SRC ?= /home/thiago/Documents/raylib/src
endif
RAYLIB_WEB_LIB := $(RAYLIB_WEB_SRC)/libraylib.web.a

# Emscripten flags targeting WebGL 1.0 (OpenGL ES 2.0)
CFLAGS_WEB = -Os -I$(RAYLIB_WEB_SRC) -DPLATFORM_WEB -s USE_GLFW=3 -s MIN_WEBGL_VERSION=1 -s MAX_WEBGL_VERSION=1 -s ALLOW_MEMORY_GROWTH=1
EXPORTED_FUNCS = _main,_GetSphereCount,_GetSelectedSphere,_GetSphereColorR,_GetSphereColorG,_GetSphereColorB,_GetSphereMaterial,_GetSphereRadius,_SelectSphere,_SetSphereColor,_SetSphereMaterial,_SetSphereRadius,_AddSphere,_DeleteSelectedSphere,_GetLightColorR,_GetLightColorG,_GetLightColorB,_GetLightIntensity,_GetLightDirX,_GetLightDirY,_GetLightDirZ,_SetLightColor,_SetLightIntensity,_SetLightDir
LDFLAGS_WEB = $(RAYLIB_WEB_LIB) --preload-file shaders --shell-file shell.html -s USE_GLFW=3 -s MIN_WEBGL_VERSION=1 -s MAX_WEBGL_VERSION=1 -s ALLOW_MEMORY_GROWTH=1 -s FORCE_FILESYSTEM=1 -s EXPORTED_FUNCTIONS="$(EXPORTED_FUNCS)" -s EXPORTED_RUNTIME_METHODS=ccall,cwrap

# Default target
all: $(TARGET)

# Rule to link the executable
$(TARGET): $(SRCS)
	$(CC) $(SRCS) -o $(TARGET) $(CFLAGS) $(LDFLAGS)

# Rule to clean build artifacts
clean:
	rm -f $(TARGET) *.o
	rm -rf $(WEB_DIR)

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
