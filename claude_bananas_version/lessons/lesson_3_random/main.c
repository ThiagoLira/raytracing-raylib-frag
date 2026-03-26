// Lesson 3: Random Numbers on the GPU
//
// Visualize the PCG hash random number generator.
//
// Controls:
//   1 — static noise (same every frame)
//   2 — animated noise (changes each frame)
//   3 — random unit vectors as RGB colors

#include "raylib.h"
#include "raymath.h"
#include "rlgl.h"
#include <stdio.h>
#include <stdlib.h>
#include <string.h>

#define W 960
#define H 540

static struct {
    Shader shader;
    RenderTexture2D canvas;
    int locRes, locMode, locFrame;
    int mode, frameCount;
} g;

static Shader LoadVer(const char *p) {
    char *c = LoadFileText(p); if (!c) return (Shader){0};
    char *f = malloc(strlen(c)+64); sprintf(f, "#version 330\n%s", c);
    UnloadFileText(c); Shader s = LoadShaderFromMemory(NULL, f); free(f);
    return s;
}

static void Init(void) {
    InitWindow(W, H, "Lesson 3 — Random Numbers on the GPU");
    SetTargetFPS(60);
    g.shader = LoadVer("shaders/lesson_combined.glsl");
    g.locRes   = GetShaderLocation(g.shader, "resolution");
    g.locMode  = GetShaderLocation(g.shader, "mode");
    g.locFrame = GetShaderLocation(g.shader, "frameCount");
    float res[2] = {W, H};
    SetShaderValue(g.shader, g.locRes, res, SHADER_UNIFORM_VEC2);
    g.mode = 0;
    SetShaderValue(g.shader, g.locMode, &g.mode, SHADER_UNIFORM_INT);
    g.canvas = LoadRenderTexture(W, H);
}

static const char *modeNames[] = {
    "Static noise (same seed every frame)",
    "Animated noise (frame-varying seed)",
    "Random unit vectors as RGB"
};

static void Frame(void) {
    for (int k = KEY_ONE; k <= KEY_THREE; k++) {
        if (IsKeyPressed(k)) {
            g.mode = k - KEY_ONE;
            SetShaderValue(g.shader, g.locMode, &g.mode, SHADER_UNIFORM_INT);
        }
    }

    g.frameCount++;
    SetShaderValue(g.shader, g.locFrame, &g.frameCount, SHADER_UNIFORM_INT);

    BeginTextureMode(g.canvas);
        ClearBackground(BLACK);
        DrawRectangle(0, 0, W, H, BLACK);
    EndTextureMode();

    BeginDrawing();
        ClearBackground(BLACK);
        BeginShaderMode(g.shader);
            DrawTextureRec(g.canvas.texture,
                (Rectangle){0,0,W,-H}, (Vector2){0,0}, WHITE);
        EndShaderMode();
        DrawFPS(10,10);
        DrawText(TextFormat("[%d] %s", g.mode+1, modeNames[g.mode]),
                 10, H-28, 18, RAYWHITE);
        DrawText("Press 1/2/3 to switch modes", 10, H-50, 16,
                 (Color){200,200,160,200});
        // Explanation box
        if (g.mode == 0) {
            DrawText("Each pixel hashes its (x,y) coords into a pseudorandom value.",
                     10, 40, 16, (Color){220,220,200,220});
            DrawText("Notice: the pattern is the SAME every frame (deterministic).",
                     10, 60, 16, (Color){220,220,200,220});
        } else if (g.mode == 1) {
            DrawText("Now the frame number is mixed into the seed.",
                     10, 40, 16, (Color){220,220,200,220});
            DrawText("Each frame gets different noise = basis for Monte Carlo!",
                     10, 60, 16, (Color){220,220,200,220});
        } else {
            DrawText("randomUnitVec3() generates a direction on the unit sphere.",
                     10, 40, 16, (Color){220,220,200,220});
            DrawText("Mapped to color: (x,y,z) -> (R,G,B). Used for scatter dirs!",
                     10, 60, 16, (Color){220,220,200,220});
        }
    EndDrawing();
}

int main(void) {
    Init();
    while (!WindowShouldClose()) Frame();
    UnloadShader(g.shader); UnloadRenderTexture(g.canvas); CloseWindow();
    return 0;
}
