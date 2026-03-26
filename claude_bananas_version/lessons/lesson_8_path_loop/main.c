// Lesson 8: The Path Tracing Loop
//
// Watch how each additional bounce adds more light.
//
// Controls:
//   1-8 — set max bounce depth
//   Right-click drag — orbit  |  Scroll — zoom

#include "raylib.h"
#include "raymath.h"
#include "rlgl.h"
#include <stdio.h>
#include <stdlib.h>
#include <string.h>

#define W 960
#define H 540

static struct {
    Camera3D cam; Shader shader; RenderTexture2D canvas;
    int locCamPos, locInvVP, locViewProj, locRes, locFrame, locMaxDepth;
    float angleH, angleV, dist;
    Vector3 target;
    int frameCount, maxDepth;
} g;

static void UpdateCam(void) {
    float cv = cosf(g.angleV);
    g.cam.position = (Vector3){
        g.target.x + g.dist*cv*sinf(g.angleH),
        g.target.y + g.dist*sinf(g.angleV),
        g.target.z + g.dist*cv*cosf(g.angleH),
    };
    g.cam.target = g.target;
}

static Shader LoadVer(const char *p) {
    char *c = LoadFileText(p); if (!c) return (Shader){0};
    char *f = malloc(strlen(c)+64); sprintf(f, "#version 330\n%s", c);
    UnloadFileText(c); Shader s = LoadShaderFromMemory(NULL, f); free(f);
    return s;
}

static void Init(void) {
    InitWindow(W, H, "Lesson 8 — The Path Tracing Loop");
    SetTargetFPS(60);
    g.cam = (Camera3D){ .up={0,1,0}, .fovy=45, .projection=CAMERA_PERSPECTIVE };
    g.target = (Vector3){0, 2.0f, -2.0f}; g.dist = 6.0f;
    g.angleH = 0.0f; g.angleV = 0.15f;
    UpdateCam();

    g.shader = LoadVer("shaders/lesson_combined.glsl");
    g.locCamPos   = GetShaderLocation(g.shader, "cameraPosition");
    g.locInvVP    = GetShaderLocation(g.shader, "invViewProj");
    g.locViewProj = GetShaderLocation(g.shader, "viewProj");
    g.locRes      = GetShaderLocation(g.shader, "resolution");
    g.locFrame    = GetShaderLocation(g.shader, "frameCount");
    g.locMaxDepth = GetShaderLocation(g.shader, "maxDepth");

    float res[2] = {W, H};
    SetShaderValue(g.shader, g.locRes, res, SHADER_UNIFORM_VEC2);
    g.maxDepth = 4;
    SetShaderValue(g.shader, g.locMaxDepth, &g.maxDepth, SHADER_UNIFORM_INT);
    g.canvas = LoadRenderTexture(W, H);
}

static const char *depthDesc[] = {
    "Direct light only (emissive surfaces)",
    "One bounce (diffuse receives ceiling light)",
    "Two bounces (color bleeding from walls)",
    "Three bounces (indirect fills shadows)",
    "Four bounces (subtle inter-reflections)",
    "Five bounces (diminishing returns...)",
    "Six bounces (nearly converged)",
    "Seven+ bounces (full global illumination)",
};

static void Frame(void) {
    if (IsMouseButtonDown(MOUSE_BUTTON_RIGHT)) {
        Vector2 d = GetMouseDelta();
        g.angleH -= d.x*0.005f; g.angleV += d.y*0.005f;
        g.angleV = Clamp(g.angleV, -1.4f, 1.4f);
    }
    float w = GetMouseWheelMove();
    if (w != 0) { g.dist -= w*0.5f; g.dist = Clamp(g.dist, 1, 30); }
    UpdateCam();

    for (int k = KEY_ONE; k <= KEY_EIGHT; k++) {
        if (IsKeyPressed(k)) {
            g.maxDepth = k - KEY_ONE + 1;
            SetShaderValue(g.shader, g.locMaxDepth, &g.maxDepth, SHADER_UNIFORM_INT);
        }
    }

    g.frameCount++;
    SetShaderValue(g.shader, g.locFrame, &g.frameCount, SHADER_UNIFORM_INT);

    Matrix view = GetCameraMatrix(g.cam);
    Matrix proj = MatrixPerspective(g.cam.fovy*DEG2RAD, (float)W/H, 0.1f, 100.0f);
    Matrix vp = MatrixMultiply(view, proj);
    SetShaderValue(g.shader, g.locCamPos, &g.cam.position, SHADER_UNIFORM_VEC3);
    SetShaderValueMatrix(g.shader, g.locInvVP, MatrixInvert(vp));
    SetShaderValueMatrix(g.shader, g.locViewProj, vp);

    BeginTextureMode(g.canvas);
        ClearBackground(BLACK);
        BeginMode3D(g.cam); DrawPoint3D((Vector3){0,0,0}, BLACK); EndMode3D();
    EndTextureMode();

    BeginDrawing();
        ClearBackground(BLACK);
        BeginShaderMode(g.shader);
            DrawTextureRec(g.canvas.texture, (Rectangle){0,0,W,-H}, (Vector2){0,0}, WHITE);
        EndShaderMode();
        DrawFPS(10,10);
        DrawText(TextFormat("Max bounces: %d  [press 1-8]", g.maxDepth),
                 10, H-28, 18, RAYWHITE);
        DrawText(depthDesc[g.maxDepth-1], 10, H-50, 15, (Color){200,200,160,200});
    EndDrawing();
}

int main(void) {
    Init();
    while (!WindowShouldClose()) Frame();
    UnloadShader(g.shader); UnloadRenderTexture(g.canvas); CloseWindow();
    return 0;
}
