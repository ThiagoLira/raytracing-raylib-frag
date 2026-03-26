// Lesson 9: Temporal Accumulation
//
// Watch noise melt away as frames accumulate.
//
// Controls:
//   R — reset accumulation
//   P — pause/resume
//   Right-click drag — orbit (auto-resets)
//   Scroll — zoom

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
    RenderTexture2D accumTex[2];
    int accumIdx;
    int locCamPos, locInvVP, locRes, locFrame, locAccum;
    float angleH, angleV, dist;
    Vector3 target, prevCamPos;
    int frameCount;
    bool paused;
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
    InitWindow(W, H, "Lesson 9 — Temporal Accumulation");
    SetTargetFPS(60);
    g.cam = (Camera3D){ .up={0,1,0}, .fovy=45, .projection=CAMERA_PERSPECTIVE };
    g.target = (Vector3){0,0.3f,-2.2f}; g.dist = 5.0f;
    g.angleH = 0.2f; g.angleV = 0.2f;
    UpdateCam(); g.prevCamPos = g.cam.position;

    g.shader = LoadVer("shaders/lesson_combined.glsl");
    g.locCamPos = GetShaderLocation(g.shader, "cameraPosition");
    g.locInvVP  = GetShaderLocation(g.shader, "invViewProj");
    g.locRes    = GetShaderLocation(g.shader, "resolution");
    g.locFrame  = GetShaderLocation(g.shader, "frameCount");
    g.locAccum  = GetShaderLocation(g.shader, "accumTexture");

    float res[2] = {W, H};
    SetShaderValue(g.shader, g.locRes, res, SHADER_UNIFORM_VEC2);

    g.canvas = LoadRenderTexture(W, H);

    // Create RGBA16F accumulation textures (double-buffered)
    for (int i = 0; i < 2; i++) {
        g.accumTex[i] = LoadRenderTexture(W, H);
        unsigned int prevId = g.accumTex[i].texture.id;
        unsigned int newId = rlLoadTexture(NULL, W, H,
            RL_PIXELFORMAT_UNCOMPRESSED_R16G16B16A16, 1);
        rlTextureParameters(newId, RL_TEXTURE_MAG_FILTER, RL_TEXTURE_FILTER_BILINEAR);
        rlTextureParameters(newId, RL_TEXTURE_MIN_FILTER, RL_TEXTURE_FILTER_BILINEAR);
        rlTextureParameters(newId, RL_TEXTURE_WRAP_S, RL_TEXTURE_WRAP_CLAMP);
        rlTextureParameters(newId, RL_TEXTURE_WRAP_T, RL_TEXTURE_WRAP_CLAMP);
        rlFramebufferAttach(g.accumTex[i].id, newId,
            RL_ATTACHMENT_COLOR_CHANNEL0, RL_ATTACHMENT_TEXTURE2D, 0);
        rlUnloadTexture(prevId);
        g.accumTex[i].texture.id = newId;
        g.accumTex[i].texture.format = PIXELFORMAT_UNCOMPRESSED_R16G16B16A16;
    }
    g.accumIdx = 0;
    g.frameCount = 0;
}

static void Frame(void) {
    // Camera orbit
    if (IsMouseButtonDown(MOUSE_BUTTON_RIGHT)) {
        Vector2 d = GetMouseDelta();
        g.angleH -= d.x*0.005f; g.angleV += d.y*0.005f;
        g.angleV = Clamp(g.angleV, -1.4f, 1.4f);
    }
    float w = GetMouseWheelMove();
    if (w != 0) { g.dist -= w*0.5f; g.dist = Clamp(g.dist, 1, 30); }
    UpdateCam();

    // Camera move detection → reset
    if (g.cam.position.x != g.prevCamPos.x ||
        g.cam.position.y != g.prevCamPos.y ||
        g.cam.position.z != g.prevCamPos.z) {
        g.frameCount = 0;
        g.prevCamPos = g.cam.position;
    }

    if (IsKeyPressed(KEY_R)) g.frameCount = 0;
    if (IsKeyPressed(KEY_P)) g.paused = !g.paused;

    if (!g.paused) g.frameCount++;

    SetShaderValue(g.shader, g.locFrame, &g.frameCount, SHADER_UNIFORM_INT);

    Matrix view = GetCameraMatrix(g.cam);
    Matrix proj = MatrixPerspective(g.cam.fovy*DEG2RAD, (float)W/H, 0.1f, 100.0f);
    Matrix vp = MatrixMultiply(view, proj);
    SetShaderValue(g.shader, g.locCamPos, &g.cam.position, SHADER_UNIFORM_VEC3);
    SetShaderValueMatrix(g.shader, g.locInvVP, MatrixInvert(vp));

    // Rasterize canvas (dummy geometry)
    BeginTextureMode(g.canvas);
        ClearBackground(BLACK);
        BeginMode3D(g.cam); DrawPoint3D((Vector3){0,0,0}, BLACK); EndMode3D();
    EndTextureMode();

    // Raytrace pass → write to accumulation buffer
    int readIdx = g.accumIdx;
    int writeIdx = 1 - g.accumIdx;

    BeginTextureMode(g.accumTex[writeIdx]);
        BeginShaderMode(g.shader);
            if (g.locAccum != -1)
                SetShaderValueTexture(g.shader, g.locAccum, g.accumTex[readIdx].texture);
            DrawTextureRec(g.canvas.texture,
                (Rectangle){0,0,(float)W,(float)-H}, (Vector2){0,0}, WHITE);
        EndShaderMode();
    EndTextureMode();
    g.accumIdx = writeIdx;

    // Display (accumulated result already has tone mapping applied in shader)
    BeginDrawing();
        ClearBackground(BLACK);
        DrawTextureRec(g.accumTex[g.accumIdx].texture,
            (Rectangle){0,0,(float)W,(float)-H}, (Vector2){0,0}, WHITE);
        DrawFPS(10,10);

        // Frame counter — the key metric
        DrawRectangle(W-200, 5, 195, 45, (Color){0,0,0,160});
        DrawText(TextFormat("Frames: %d", g.frameCount), W-190, 10, 20, RAYWHITE);
        float noise = g.frameCount > 0 ? 1.0f/sqrtf((float)g.frameCount) : 1.0f;
        DrawText(TextFormat("Noise: %.0f%%", noise*100.0f), W-190, 32, 16,
                 noise > 0.3f ? (Color){255,100,100,255} :
                 noise > 0.1f ? (Color){255,200,100,255} :
                                (Color){100,255,100,255});

        DrawText(g.paused ? "[P] PAUSED  [R] Reset" : "[R] Reset  [P] Pause",
                 10, H-28, 18, RAYWHITE);
        DrawText("Orbit: right-drag (resets accumulation)  |  Zoom: scroll",
                 10, H-50, 15, (Color){200,200,160,200});
    EndDrawing();
}

int main(void) {
    Init();
    while (!WindowShouldClose()) Frame();
    UnloadShader(g.shader);
    UnloadRenderTexture(g.canvas);
    UnloadRenderTexture(g.accumTex[0]);
    UnloadRenderTexture(g.accumTex[1]);
    CloseWindow();
    return 0;
}
