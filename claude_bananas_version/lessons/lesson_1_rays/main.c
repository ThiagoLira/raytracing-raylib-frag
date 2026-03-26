// Lesson 1: What Is a Ray?
//
// Minimal raytracer host that renders one sphere against a sky gradient.
// The shader overlays vector arrows showing the ray from camera to pixel.
//
// Controls:
//   Right-click drag — orbit camera
//   Scroll wheel     — zoom in/out

#include "raylib.h"
#include "raymath.h"
#include "rlgl.h"
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <math.h>

#define SCREEN_WIDTH  960
#define SCREEN_HEIGHT 540

typedef struct {
    Camera3D camera;
    Shader   shader;
    RenderTexture2D canvas;
    // Shader uniform locations
    int locCamPos, locInvVP, locViewProj, locResolution, locTime;
    int locSphereCenter, locSphereRadius, locSphereColor;
    // Camera orbit state
    float angleH, angleV, distance;
    Vector3 target;
} App;

static App g;

// --- Camera orbit ---

static void UpdateCameraFromAngles(void) {
    float cosV = cosf(g.angleV);
    g.camera.position = (Vector3){
        g.target.x + g.distance * cosV * sinf(g.angleH),
        g.target.y + g.distance * sinf(g.angleV),
        g.target.z + g.distance * cosV * cosf(g.angleH),
    };
    g.camera.target = g.target;
}

// --- Shader loading (prepend #version) ---

static Shader LoadShaderWithVersion(const char *fragPath) {
    char *code = LoadFileText(fragPath);
    if (!code) { printf("ERROR: could not load %s\n", fragPath); return (Shader){0}; }
    int len = (int)strlen(code);
    char *full = (char *)RL_MALLOC(len + 64);
    sprintf(full, "#version 330\n%s", code);
    UnloadFileText(code);
    Shader s = LoadShaderFromMemory(NULL, full);
    RL_FREE(full);
    return s;
}

// --- Init ---

static void InitApp(void) {
    InitWindow(SCREEN_WIDTH, SCREEN_HEIGHT, "Lesson 1 — What Is a Ray?");
    SetTargetFPS(60);

    // Camera
    g.camera = (Camera3D){0};
    g.camera.up     = (Vector3){0, 1, 0};
    g.camera.fovy   = 45.0f;
    g.camera.projection = CAMERA_PERSPECTIVE;
    g.target   = (Vector3){0, 0, -2};
    g.distance = 5.0f;
    g.angleH   = 0.0f;
    g.angleV   = 0.15f;
    UpdateCameraFromAngles();

    // Shader
    g.shader = LoadShaderWithVersion("shaders/lesson_combined.glsl");
    g.locCamPos      = GetShaderLocation(g.shader, "cameraPosition");
    g.locInvVP       = GetShaderLocation(g.shader, "invViewProj");
    g.locViewProj    = GetShaderLocation(g.shader, "viewProj");
    g.locResolution  = GetShaderLocation(g.shader, "resolution");
    g.locTime        = GetShaderLocation(g.shader, "time");
    g.locSphereCenter = GetShaderLocation(g.shader, "sphereCenter");
    g.locSphereRadius = GetShaderLocation(g.shader, "sphereRadius");
    g.locSphereColor  = GetShaderLocation(g.shader, "sphereColor");

    // Static uniforms
    float res[2] = {(float)SCREEN_WIDTH, (float)SCREEN_HEIGHT};
    SetShaderValue(g.shader, g.locResolution, res, SHADER_UNIFORM_VEC2);

    Vector3 sc = {0.0f, 0.0f, -2.0f};
    float sr = 1.0f;
    float scol[3] = {0.8f, 0.3f, 0.3f};
    SetShaderValue(g.shader, g.locSphereCenter, &sc, SHADER_UNIFORM_VEC3);
    SetShaderValue(g.shader, g.locSphereRadius, &sr, SHADER_UNIFORM_FLOAT);
    SetShaderValue(g.shader, g.locSphereColor, scol, SHADER_UNIFORM_VEC3);

    // Canvas (dummy geometry for fullscreen shader pass)
    g.canvas = LoadRenderTexture(SCREEN_WIDTH, SCREEN_HEIGHT);
}

// --- Frame ---

static void UpdateDrawFrame(void) {
    // Orbit camera
    if (IsMouseButtonDown(MOUSE_BUTTON_RIGHT)) {
        Vector2 delta = GetMouseDelta();
        g.angleH -= delta.x * 0.005f;
        g.angleV += delta.y * 0.005f;
        if (g.angleV >  1.4f) g.angleV =  1.4f;
        if (g.angleV < -1.4f) g.angleV = -1.4f;
    }
    float wheel = GetMouseWheelMove();
    if (wheel != 0.0f) {
        g.distance -= wheel * 0.5f;
        if (g.distance < 1.0f)  g.distance = 1.0f;
        if (g.distance > 30.0f) g.distance = 30.0f;
    }
    UpdateCameraFromAngles();

    // Compute matrices
    Matrix view = GetCameraMatrix(g.camera);
    float aspect = (float)SCREEN_WIDTH / (float)SCREEN_HEIGHT;
    Matrix proj = MatrixPerspective(g.camera.fovy * DEG2RAD, aspect, 0.1f, 100.0f);
    Matrix vp = MatrixMultiply(view, proj);
    Matrix invVP = MatrixInvert(vp);

    // Upload uniforms
    SetShaderValue(g.shader, g.locCamPos, &g.camera.position, SHADER_UNIFORM_VEC3);
    SetShaderValueMatrix(g.shader, g.locInvVP, invVP);
    SetShaderValueMatrix(g.shader, g.locViewProj, vp);
    float t = (float)GetTime();
    SetShaderValue(g.shader, g.locTime, &t, SHADER_UNIFORM_FLOAT);

    // Rasterize dummy geometry (needed so the shader has a quad to run on)
    BeginTextureMode(g.canvas);
        ClearBackground(BLACK);
        BeginMode3D(g.camera);
            DrawCube((Vector3){0, 0, -2}, 0.01f, 0.01f, 0.01f, BLACK);
        EndMode3D();
    EndTextureMode();

    // Draw fullscreen with our shader
    BeginDrawing();
        ClearBackground(BLACK);
        BeginShaderMode(g.shader);
            DrawTextureRec(g.canvas.texture,
                (Rectangle){0, 0, (float)g.canvas.texture.width,
                             (float)-g.canvas.texture.height},
                (Vector2){0, 0}, WHITE);
        EndShaderMode();
        DrawFPS(10, 10);
        DrawText("Right-click drag: orbit | Scroll: zoom", 10, SCREEN_HEIGHT - 25, 16, RAYWHITE);
    EndDrawing();
}

int main(void) {
    InitApp();
    while (!WindowShouldClose()) UpdateDrawFrame();
    UnloadShader(g.shader);
    UnloadRenderTexture(g.canvas);
    CloseWindow();
    return 0;
}
