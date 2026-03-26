CC = gcc
TARGET = lesson_3

UNAME_S := $(shell uname -s)
CFLAGS = -Wall -Wextra -O2
ifeq ($(UNAME_S),Darwin)
    CFLAGS += $(shell pkg-config --cflags raylib)
    LDFLAGS = $(shell pkg-config --libs raylib) -framework CoreVideo -framework IOKit -framework Cocoa -framework OpenGL
else
    CFLAGS += -I/usr/local/include
    LDFLAGS = -L/usr/local/lib -lraylib -lm -lpthread -ldl -lrt -lX11
endif

COMBINED_SHADER = shaders/lesson_combined.glsl
VIZ_PRIMS = ../viz_primitives.glsl
LESSON_SHADER = shaders/lesson.glsl

all: $(TARGET)

$(COMBINED_SHADER): $(VIZ_PRIMS) $(LESSON_SHADER)
	cat $(VIZ_PRIMS) $(LESSON_SHADER) > $(COMBINED_SHADER)

$(TARGET): main.c $(COMBINED_SHADER)
	$(CC) main.c -o $(TARGET) $(CFLAGS) $(LDFLAGS)

clean:
	rm -f $(TARGET) $(COMBINED_SHADER)

run: $(TARGET)
	./$(TARGET)

.PHONY: all clean run
