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

# Phony targets (targets that are not files)
.PHONY: all clean run
