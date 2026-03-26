# Full Lighting Reference — Build
# This Makefile should be run from within the VIBE_CODED_VERSION directory.

CC = gcc
TARGET = raylib_project

# Detect OS
UNAME_S := $(shell uname -s)

CFLAGS = -Wall -Wextra -O2 -DPLATFORM_DESKTOP

ifeq ($(UNAME_S),Darwin)
    CFLAGS += $(shell pkg-config --cflags raylib)
    LDFLAGS = $(shell pkg-config --libs raylib) -framework CoreVideo -framework IOKit -framework Cocoa -framework OpenGL
else
    CFLAGS += -I/usr/local/include
    LDFLAGS = -L/usr/local/lib -lraylib -lm -lpthread -ldl -lrt -lX11
endif

# Web target settings
EMCC = emcc
WEB_DIR = web
WEB_TARGET = $(WEB_DIR)/index.html

ifeq ($(UNAME_S),Darwin)
    RAYLIB_WEB_SRC ?= /tmp/raylib-web/src
else
    RAYLIB_WEB_SRC ?= /home/thiago/Documents/raylib/src
endif
RAYLIB_WEB_LIB := $(RAYLIB_WEB_SRC)/libraylib.web.a

CFLAGS_WEB = -Os -I$(RAYLIB_WEB_SRC) -DPLATFORM_WEB -DGRAPHICS_API_OPENGL_ES3 -s USE_GLFW=3 \
    -s MIN_WEBGL_VERSION=2 -s MAX_WEBGL_VERSION=2 -s ALLOW_MEMORY_GROWTH=1

# All exported C functions callable from JS
EXPORTED_FUNCS = _main,\
_GetSphereCount,_GetSelectedSphere,\
_GetSphereColorR,_GetSphereColorG,_GetSphereColorB,\
_GetSphereMaterial,_GetSphereRadius,\
_GetSphereEmissionR,_GetSphereEmissionG,_GetSphereEmissionB,_GetSphereEmissionStrength,\
_GetSphereIOR,_GetSphereRoughness,_GetSphereSpecular,_GetSphereShininess,\
_SelectSphere,_SetSphereColor,_SetSphereMaterial,_SetSphereRadius,\
_SetSphereEmission,_SetSphereEmissionStrength,\
_SetSphereIOR,_SetSphereRoughness,_SetSphereSpecular,_SetSphereShininess,\
_AddSphere,_DeleteSelectedSphere,\
_GetLightType,_GetLightColorR,_GetLightColorG,_GetLightColorB,\
_GetLightIntensity,_GetLightDirX,_GetLightDirY,_GetLightDirZ,\
_GetLightPosX,_GetLightPosY,_GetLightPosZ,_GetLightRadius,\
_SetLightType,_SetLightColor,_SetLightIntensity,_SetLightDir,_SetLightPos,_SetLightRadius,\
_GetAOStrength,_GetAORadius,_GetToneMapMode,\
_SetAOStrength,_SetAORadius,_SetToneMapMode,\
_GetCurrentScene,_SetScene,\
_GetEnvMode,_SetEnvMode,_GetEnvIntensity,_SetEnvIntensity,_GetEnvRotation,_SetEnvRotation,\
_GetExposure,_SetExposure,\
_GetSPP,_SetSPP,\
_GetFPSValue,_GetUncapFPS,_SetUncapFPS

LDFLAGS_WEB = $(RAYLIB_WEB_LIB) --preload-file shaders --shell-file shell.html \
    -s USE_GLFW=3 -s MIN_WEBGL_VERSION=2 -s MAX_WEBGL_VERSION=2 \
    -s ALLOW_MEMORY_GROWTH=1 -s FORCE_FILESYSTEM=1 \
    -s EXPORTED_FUNCTIONS="$(EXPORTED_FUNCS)" \
    -s EXPORTED_RUNTIME_METHODS=ccall,cwrap

all: $(TARGET)

$(TARGET): main_web.c
	$(CC) main_web.c -o $(TARGET) $(CFLAGS) $(LDFLAGS)

clean:
	rm -f $(TARGET) *.o
	rm -rf $(WEB_DIR)

run: $(TARGET)
	./$(TARGET)

web: $(WEB_TARGET)

$(WEB_TARGET): main_web.c shaders/raytrace.glsl shell.html
	mkdir -p $(WEB_DIR)
	$(EMCC) main_web.c -o $(WEB_TARGET) $(CFLAGS_WEB) $(LDFLAGS_WEB)

.PHONY: all clean run web
