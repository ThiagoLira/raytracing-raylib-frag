// Lesson 1: From Pixels to Rays
//
// Step through the coordinate transform pipeline that turns
// a 2D screen pixel into a 3D ray.
//
// Controls:
//   1 — Stage 1: UV coordinates (what the GPU gives you)
//   2 — Stage 2: NDC (centered, normalized)
//   3 — Stage 3: World position (after inverse view-projection)
//   4 — Stage 4: Ray direction (the unit vector)
//   5 — Stage 5: Hit distance (depth buffer)
//   6 — Stage 6: Full raytrace (the final image)
//   Right-click drag — orbit camera
//   Scroll wheel     — zoom

#include "raylib.h"
#include "raymath.h"
#include "rlgl.h"
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <math.h>

#define W 1280
#define H 720

static struct {
    Camera3D cam;
    Shader shader;
    RenderTexture2D canvas;
    int locCamPos, locInvVP, locViewProj, locRes, locMode;
    int locSphereCenter, locSphereRadius, locSphereColor;
    float angleH, angleV, dist;
    Vector3 target;
    int mode;
} g;

static void UpdateCam(void) {
    float cv = cosf(g.angleV);
    g.cam.position = (Vector3){
        g.target.x + g.dist * cv * sinf(g.angleH),
        g.target.y + g.dist * sinf(g.angleV),
        g.target.z + g.dist * cv * cosf(g.angleH),
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
    InitWindow(W, H, "Lesson 1 — From Pixels to Rays");
    SetTargetFPS(60);
    

    g.cam = (Camera3D){ .up={0,1,0}, .fovy=45, .projection=CAMERA_PERSPECTIVE };
    g.target = (Vector3){0, 0, -2};
    g.dist = 5.0f; g.angleH = 0.0f; g.angleV = 0.15f;
    UpdateCam();

    g.shader = LoadVer("shaders/lesson_combined.glsl");
    g.locCamPos      = GetShaderLocation(g.shader, "cameraPosition");
    g.locInvVP       = GetShaderLocation(g.shader, "invViewProj");
    g.locViewProj    = GetShaderLocation(g.shader, "viewProj");
    g.locRes         = GetShaderLocation(g.shader, "resolution");
    g.locMode        = GetShaderLocation(g.shader, "mode");
    g.locSphereCenter = GetShaderLocation(g.shader, "sphereCenter");
    g.locSphereRadius = GetShaderLocation(g.shader, "sphereRadius");
    g.locSphereColor  = GetShaderLocation(g.shader, "sphereColor");

    float res[2] = {(float)W, (float)H};
    SetShaderValue(g.shader, g.locRes, res, SHADER_UNIFORM_VEC2);

    Vector3 sc = {0, 0, -2}; float sr = 1.0f; float scol[3] = {0.8f, 0.3f, 0.3f};
    SetShaderValue(g.shader, g.locSphereCenter, &sc, SHADER_UNIFORM_VEC3);
    SetShaderValue(g.shader, g.locSphereRadius, &sr, SHADER_UNIFORM_FLOAT);
    SetShaderValue(g.shader, g.locSphereColor, scol, SHADER_UNIFORM_VEC3);

    g.mode = 0;
    SetShaderValue(g.shader, g.locMode, &g.mode, SHADER_UNIFORM_INT);
    g.canvas = LoadRenderTexture(W, H);
}

static const char *stageNames[] = {
    "UV Coordinates  —  what the GPU gives each pixel: (0,0) to (1,1)",
    "NDC (clip space)  —  remap to (-1,-1) to (1,1), center = origin",
    "World Position  —  invViewProj unprojects 2D back to 3D (orbit to see it change!)",
    "Ray Direction  —  normalize(worldPos - cameraPos) = the ray's heading",
    "Hit Distance  —  how far the ray travels before hitting the sphere (depth)",
    "Full Raytrace  —  the complete pipeline: pixel -> ray -> intersection -> color",
};

static const char *stageDetail[] = {
    "Red = U (horizontal)  |  Green = V (vertical)  |  Black=(0,0)  Yellow=(1,1)",
    "White crosshair = NDC origin (0,0) = where the camera looks",
    "Color = fract(worldPos * 0.3):  R=X  G=Y  B=Z  —  orbit the camera!",
    "Color = rayDir * 0.5 + 0.5:  center = forward dir, edges = field of view fan-out",
    "Bright = close to camera  |  Dark = far away  |  Navy = miss (sky)",
    "Normal arrows (yellow)  |  Axes at origin (RGB=XYZ)  |  Camera dot (white)",
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

    for (int k = KEY_ONE; k <= KEY_SIX; k++) {
        if (IsKeyPressed(k)) {
            g.mode = k - KEY_ONE;
            SetShaderValue(g.shader, g.locMode, &g.mode, SHADER_UNIFORM_INT);
        }
    }

    Matrix view = GetCameraMatrix(g.cam);
    float asp = (float)W/H;
    Matrix proj = MatrixPerspective(g.cam.fovy*DEG2RAD, asp, 0.1f, 100.0f);
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

        // Stage number + name
        DrawRectangle(0, H-62, W, 62, (Color){0,0,0,200});
        DrawText(TextFormat("Stage %d/6: %s", g.mode+1, stageNames[g.mode]),
                 10, H-58, 17, RAYWHITE);
        DrawText(stageDetail[g.mode], 10, H-35, 14, (Color){200,200,160,220});
        DrawText("[1-6] switch stages  |  Right-drag: orbit  |  Scroll: zoom",
                 10, H-16, 13, (Color){160,160,140,180});
        // Auto-screenshot for visual verification
        { static int _af = 0; if (++_af == 10) TakeScreenshot("/tmp/lesson1.png"); }
    EndDrawing();
}

int main(void) {
    Init();
    while (!WindowShouldClose()) Frame();
    UnloadShader(g.shader); UnloadRenderTexture(g.canvas); CloseWindow();
    return 0;
}
