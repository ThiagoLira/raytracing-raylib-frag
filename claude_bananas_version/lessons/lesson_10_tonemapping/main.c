// Lesson 10: Tone Mapping & Color
//
// Compare how different tone mappers handle bright lights.
//
// Controls:
//   1 — no tone mapping (raw clamp)
//   2 — Reinhard
//   3 — ACES filmic
//   4 — AgX (modern, Blender default)
//   +/- — adjust exposure (EV stops)
//   R — reset accumulation
//   Right-click drag — orbit  |  Scroll — zoom

#include "raylib.h"
#include "raymath.h"
#include "rlgl.h"
#include <stdio.h>
#include <stdlib.h>
#include <string.h>

#define W 1280
#define H 720

static struct {
    Camera3D cam; Shader shader; Shader displayShader; RenderTexture2D canvas;
    RenderTexture2D accumTex[2];
    int accumIdx;
    int locCamPos, locInvVP, locRes, locFrame, locAccum;
    int locDispToneMap, locDispExposure;
    float angleH, angleV, dist;
    Vector3 target, prevCamPos;
    int frameCount, toneMapMode;
    float exposure;
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
    InitWindow(W, H, "Lesson 10 — Tone Mapping & Color");
    SetTargetFPS(60);
    
    g.cam = (Camera3D){ .up={0,1,0}, .fovy=45, .projection=CAMERA_PERSPECTIVE };
    g.target = (Vector3){0,0.3f,-2.5f}; g.dist = 5.5f;
    g.angleH = 0.15f; g.angleV = 0.2f;
    UpdateCam(); g.prevCamPos = g.cam.position;

    g.shader = LoadVer("shaders/lesson_combined.glsl");
    g.locCamPos   = GetShaderLocation(g.shader, "cameraPosition");
    g.locInvVP    = GetShaderLocation(g.shader, "invViewProj");
    g.locRes      = GetShaderLocation(g.shader, "resolution");
    g.locFrame    = GetShaderLocation(g.shader, "frameCount");
    g.locAccum    = GetShaderLocation(g.shader, "accumTexture");

    float res[2] = {(float)W, (float)H};
    SetShaderValue(g.shader, g.locRes, res, SHADER_UNIFORM_VEC2);

    g.displayShader = LoadVer("../display.glsl");
    g.locDispToneMap  = GetShaderLocation(g.displayShader, "toneMapMode");
    g.locDispExposure = GetShaderLocation(g.displayShader, "exposure");
    g.toneMapMode = 3; g.exposure = 0.0f;
    SetShaderValue(g.displayShader, g.locDispToneMap, &g.toneMapMode, SHADER_UNIFORM_INT);
    SetShaderValue(g.displayShader, g.locDispExposure, &g.exposure, SHADER_UNIFORM_FLOAT);

    g.canvas = LoadRenderTexture(W, H);

    // RGBA16F accum textures
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
    g.accumIdx = 0; g.frameCount = 0;
}

static const char *tmNames[] = {"None (raw clamp)", "Reinhard", "ACES Filmic", "AgX"};

static void Frame(void) {
    if (IsMouseButtonDown(MOUSE_BUTTON_RIGHT)) {
        Vector2 d = GetMouseDelta();
        g.angleH -= d.x*0.005f; g.angleV += d.y*0.005f;
        g.angleV = Clamp(g.angleV, -1.4f, 1.4f);
    }
    float w = GetMouseWheelMove();
    if (w != 0) { g.dist -= w*0.5f; g.dist = Clamp(g.dist, 1, 30); }
    UpdateCam();

    // Camera move detection
    if (g.cam.position.x != g.prevCamPos.x ||
        g.cam.position.y != g.prevCamPos.y ||
        g.cam.position.z != g.prevCamPos.z) {
        g.frameCount = 0;
        g.prevCamPos = g.cam.position;
    }

    // Tone map mode
    for (int k = KEY_ONE; k <= KEY_FOUR; k++)
        if (IsKeyPressed(k)) {
            g.toneMapMode = k-KEY_ONE;
            SetShaderValue(g.displayShader, g.locDispToneMap, &g.toneMapMode, SHADER_UNIFORM_INT);
            g.frameCount = 0; // reset to see the difference immediately
        }

    // Exposure
    if (IsKeyPressed(KEY_EQUAL)||IsKeyPressed(KEY_KP_ADD)) {
        g.exposure += 0.5f; if (g.exposure > 5.0f) g.exposure = 5.0f;
        SetShaderValue(g.displayShader, g.locDispExposure, &g.exposure, SHADER_UNIFORM_FLOAT);
        g.frameCount = 0;
    }
    if (IsKeyPressed(KEY_MINUS)||IsKeyPressed(KEY_KP_SUBTRACT)) {
        g.exposure -= 0.5f; if (g.exposure < -5.0f) g.exposure = -5.0f;
        SetShaderValue(g.displayShader, g.locDispExposure, &g.exposure, SHADER_UNIFORM_FLOAT);
        g.frameCount = 0;
    }

    if (IsKeyPressed(KEY_R)) g.frameCount = 0;

    g.frameCount++;
    SetShaderValue(g.shader, g.locFrame, &g.frameCount, SHADER_UNIFORM_INT);

    Matrix view = GetCameraMatrix(g.cam);
    Matrix proj = MatrixPerspective(g.cam.fovy*DEG2RAD, (float)W/H, 0.1f, 100.0f);
    Matrix vp = MatrixMultiply(view, proj);
    SetShaderValue(g.shader, g.locCamPos, &g.cam.position, SHADER_UNIFORM_VEC3);
    SetShaderValueMatrix(g.shader, g.locInvVP, MatrixInvert(vp));

    BeginTextureMode(g.canvas);
        ClearBackground(BLACK);
        BeginMode3D(g.cam); DrawPoint3D((Vector3){0,0,0}, BLACK); EndMode3D();
    EndTextureMode();

    int readIdx = g.accumIdx;
    int writeIdx = 1 - g.accumIdx;

    BeginTextureMode(g.accumTex[writeIdx]);
        BeginShaderMode(g.shader);
            if (g.locAccum != -1)
                SetShaderValueTexture(g.shader, g.locAccum, g.accumTex[readIdx].texture);
            DrawTextureRec(g.canvas.texture,
                (Rectangle){0,0,(float)g.canvas.texture.width,(float)-g.canvas.texture.height},
                (Vector2){0,0}, WHITE);
        EndShaderMode();
    EndTextureMode();
    g.accumIdx = writeIdx;

    BeginDrawing();
        ClearBackground(BLACK);
        BeginShaderMode(g.displayShader);
            DrawTextureRec(g.accumTex[g.accumIdx].texture,
                (Rectangle){0,0,(float)g.accumTex[g.accumIdx].texture.width,(float)-g.accumTex[g.accumIdx].texture.height},
                (Vector2){0,0}, WHITE);
        EndShaderMode();
        DrawFPS(10,10);
        DrawText(TextFormat("Tone map: %s  |  Exposure: %+.1f EV",
                 tmNames[g.toneMapMode], g.exposure), 10, H-28, 18, RAYWHITE);
        DrawText("[1] None  [2] Reinhard  [3] ACES  [4] AgX  |  [+/-] Exposure  [R] Reset",
                 10, H-50, 15, (Color){200,200,160,200});
        // Auto-screenshot for visual verification
        { static int _af = 0; if (++_af == 10) TakeScreenshot("/tmp/lesson10.png"); }
    EndDrawing();
}

int main(void) {
    Init();
    while (!WindowShouldClose()) Frame();
    UnloadShader(g.shader); UnloadRenderTexture(g.canvas);
    UnloadRenderTexture(g.accumTex[0]); UnloadRenderTexture(g.accumTex[1]);
    CloseWindow();
    return 0;
}
