// Lesson 7: Glass & Refraction
//
// See how light bends through transparent materials.
//
// Controls:
//   1 — reflection only
//   2 — refraction only
//   3 — full Fresnel (realistic)
//   +/- — adjust IOR (index of refraction)
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
    Camera3D cam; Shader shader; RenderTexture2D canvas;
    int locCamPos, locInvVP, locViewProj, locRes, locMode, locFrame, locIOR;
    float angleH, angleV, dist;
    Vector3 target;
    int mode, frameCount;
    float ior;
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
    InitWindow(W, H, "Lesson 7 — Glass & Refraction");
    SetTargetFPS(60);
    
    g.cam = (Camera3D){ .up={0,1,0}, .fovy=45, .projection=CAMERA_PERSPECTIVE };
    g.target = (Vector3){0,0.4f,-2.5f}; g.dist = 5.0f;
    g.angleH = 0.3f; g.angleV = 0.2f;
    UpdateCam();

    g.shader = LoadVer("shaders/lesson_combined.glsl");
    g.locCamPos   = GetShaderLocation(g.shader, "cameraPosition");
    g.locInvVP    = GetShaderLocation(g.shader, "invViewProj");
    g.locViewProj = GetShaderLocation(g.shader, "viewProj");
    g.locRes      = GetShaderLocation(g.shader, "resolution");
    g.locMode     = GetShaderLocation(g.shader, "mode");
    g.locFrame    = GetShaderLocation(g.shader, "frameCount");
    g.locIOR      = GetShaderLocation(g.shader, "ior");

    float res[2] = {(float)W, (float)H};
    SetShaderValue(g.shader, g.locRes, res, SHADER_UNIFORM_VEC2);
    g.mode = 2; g.ior = 1.5f;
    SetShaderValue(g.shader, g.locMode, &g.mode, SHADER_UNIFORM_INT);
    SetShaderValue(g.shader, g.locIOR, &g.ior, SHADER_UNIFORM_FLOAT);
    g.canvas = LoadRenderTexture(W, H);
}

static const char *modeNames[] = {"Reflection Only", "Refraction Only", "Full Fresnel"};

// Common IOR reference values
static const char *iorLabel(float v) {
    if (v < 1.05f) return "(air)";
    if (v > 1.30f && v < 1.36f) return "(water)";
    if (v > 1.48f && v < 1.53f) return "(glass)";
    if (v > 2.38f && v < 2.45f) return "(diamond)";
    return "";
}

static void Frame(void) {
    if (IsMouseButtonDown(MOUSE_BUTTON_RIGHT)) {
        Vector2 d = GetMouseDelta();
        g.angleH -= d.x*0.005f; g.angleV += d.y*0.005f;
        g.angleV = Clamp(g.angleV, -1.4f, 1.4f);
    }
    float w = GetMouseWheelMove();
    if (w != 0) { g.dist -= w*0.5f; g.dist = Clamp(g.dist, 1, 30); }
    UpdateCam();

    for (int k = KEY_ONE; k <= KEY_THREE; k++)
        if (IsKeyPressed(k)) {
            g.mode = k-KEY_ONE;
            SetShaderValue(g.shader, g.locMode, &g.mode, SHADER_UNIFORM_INT);
        }
    if (IsKeyPressed(KEY_EQUAL)||IsKeyPressed(KEY_KP_ADD)) {
        g.ior += 0.05f; if (g.ior > 2.5f) g.ior = 2.5f;
        SetShaderValue(g.shader, g.locIOR, &g.ior, SHADER_UNIFORM_FLOAT);
    }
    if (IsKeyPressed(KEY_MINUS)||IsKeyPressed(KEY_KP_SUBTRACT)) {
        g.ior -= 0.05f; if (g.ior < 1.0f) g.ior = 1.0f;
        SetShaderValue(g.shader, g.locIOR, &g.ior, SHADER_UNIFORM_FLOAT);
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
            DrawTexturePro(g.canvas.texture, (Rectangle){0,0,(float)g.canvas.texture.width,(float)-g.canvas.texture.height}, (Rectangle){0,0,W,H}, (Vector2){0,0}, 0, WHITE);
        EndShaderMode();
        DrawFPS(10,10);
        DrawText(TextFormat("%s  |  IOR: %.2f %s  [+/- to adjust]",
                 modeNames[g.mode], g.ior, iorLabel(g.ior)),
                 10, H-28, 18, RAYWHITE);
        DrawText("[1] Reflect  [2] Refract  [3] Fresnel  |  Orbit: right-drag  Zoom: scroll",
                 10, H-50, 15, (Color){200,200,160,200});
        // Auto-screenshot for visual verification
        { static int _af = 0; if (++_af == 10) TakeScreenshot("/tmp/lesson7.png"); }
    EndDrawing();
}

int main(void) {
    Init();
    while (!WindowShouldClose()) Frame();
    UnloadShader(g.shader); UnloadRenderTexture(g.canvas); CloseWindow();
    return 0;
}
