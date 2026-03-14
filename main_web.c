#include "raylib.h"
#include "raymath.h"

#if defined(PLATFORM_WEB)
#include <emscripten/emscripten.h>
#endif

#include <stdio.h>
#include <string.h>

static const char *FRAGMENT_SHADER_PATH_WEB = "shaders/distance_web.glsl";

#define SCREEN_WIDTH 800
#define SCREEN_HEIGHT 600
#define MAX_SPHERES 10
#define MAX_LIGHTS 4

typedef struct Sphere {
    Vector3 center;
    float radius;
    Color color;
    int material; // 0 = lambertian, 1 = metal
} Sphere;

typedef struct DirLight {
    Vector3 direction;
    Vector3 color;
    float intensity;
} DirLight;

static inline Vector3 ColorToVec3(Color c) {
    return (Vector3){ (float)c.r/255.0f, (float)c.g/255.0f, (float)c.b/255.0f };
}

typedef struct AppState {
    Camera3D camera;
    Shader shader;
    RenderTexture2D targetTexture;
    int locTime;
    int locSphereCount;
    int locLightCount;
    int camPosLoc;
    int invVpLoc;
    Sphere spheres[MAX_SPHERES];
    int sphereCount;
    DirLight lights[MAX_LIGHTS];
    int lightCount;
    int selectedSphere;
    bool isDragging;
    float cameraAngleH;
    float cameraAngleV;
    float cameraDistance;
    Vector3 cameraTarget;
} AppState;

static AppState g;

static void SetSceneUniforms(void) {
    if (g.locSphereCount != -1)
        SetShaderValue(g.shader, g.locSphereCount, &g.sphereCount, SHADER_UNIFORM_INT);

    char name[32];
    for (int i = 0; i < MAX_SPHERES; i++) {
        int loc;
        sprintf(name, "u_s%d_center", i);
        if ((loc = GetShaderLocation(g.shader, name)) != -1)
            SetShaderValue(g.shader, loc, &g.spheres[i].center, SHADER_UNIFORM_VEC3);
        sprintf(name, "u_s%d_radius", i);
        if ((loc = GetShaderLocation(g.shader, name)) != -1)
            SetShaderValue(g.shader, loc, &g.spheres[i].radius, SHADER_UNIFORM_FLOAT);
        sprintf(name, "u_s%d_color", i);
        Vector3 colorVec = ColorToVec3(g.spheres[i].color);
        if ((loc = GetShaderLocation(g.shader, name)) != -1)
            SetShaderValue(g.shader, loc, &colorVec, SHADER_UNIFORM_VEC3);
        sprintf(name, "u_s%d_material", i);
        if ((loc = GetShaderLocation(g.shader, name)) != -1)
            SetShaderValue(g.shader, loc, &g.spheres[i].material, SHADER_UNIFORM_INT);
    }
}

static void SetLightUniforms(void) {
    if (g.locLightCount != -1)
        SetShaderValue(g.shader, g.locLightCount, &g.lightCount, SHADER_UNIFORM_INT);

    char name[32];
    for (int i = 0; i < MAX_LIGHTS; i++) {
        int loc;
        sprintf(name, "u_l%d_direction", i);
        if ((loc = GetShaderLocation(g.shader, name)) != -1)
            SetShaderValue(g.shader, loc, &g.lights[i].direction, SHADER_UNIFORM_VEC3);
        sprintf(name, "u_l%d_color", i);
        if ((loc = GetShaderLocation(g.shader, name)) != -1)
            SetShaderValue(g.shader, loc, &g.lights[i].color, SHADER_UNIFORM_VEC3);
        sprintf(name, "u_l%d_intensity", i);
        if ((loc = GetShaderLocation(g.shader, name)) != -1)
            SetShaderValue(g.shader, loc, &g.lights[i].intensity, SHADER_UNIFORM_FLOAT);
    }
}

// === API exposed to JS via EMSCRIPTEN_KEEPALIVE ===

#ifdef PLATFORM_WEB
EMSCRIPTEN_KEEPALIVE int GetSphereCount(void) { return g.sphereCount; }
EMSCRIPTEN_KEEPALIVE int GetSelectedSphere(void) { return g.selectedSphere; }
EMSCRIPTEN_KEEPALIVE int GetSphereColorR(int i) { return (i >= 0 && i < g.sphereCount) ? g.spheres[i].color.r : 0; }
EMSCRIPTEN_KEEPALIVE int GetSphereColorG(int i) { return (i >= 0 && i < g.sphereCount) ? g.spheres[i].color.g : 0; }
EMSCRIPTEN_KEEPALIVE int GetSphereColorB(int i) { return (i >= 0 && i < g.sphereCount) ? g.spheres[i].color.b : 0; }
EMSCRIPTEN_KEEPALIVE int GetSphereMaterial(int i) { return (i >= 0 && i < g.sphereCount) ? g.spheres[i].material : 0; }
EMSCRIPTEN_KEEPALIVE float GetSphereRadius(int i) { return (i >= 0 && i < g.sphereCount) ? g.spheres[i].radius : 0; }

EMSCRIPTEN_KEEPALIVE void SelectSphere(int i) {
    g.selectedSphere = (i >= 0 && i < g.sphereCount) ? i : -1;
}

EMSCRIPTEN_KEEPALIVE void SetSphereColor(int i, int r, int gr, int b) {
    if (i < 0 || i >= g.sphereCount) return;
    g.spheres[i].color = (Color){ (unsigned char)r, (unsigned char)gr, (unsigned char)b, 255 };
    SetSceneUniforms();
}

EMSCRIPTEN_KEEPALIVE void SetSphereMaterial(int i, int mat) {
    if (i < 0 || i >= g.sphereCount) return;
    g.spheres[i].material = mat;
    SetSceneUniforms();
}

EMSCRIPTEN_KEEPALIVE void SetSphereRadius(int i, float r) {
    if (i < 0 || i >= g.sphereCount) return;
    g.spheres[i].radius = r;
    SetSceneUniforms();
}

EMSCRIPTEN_KEEPALIVE void AddSphere(void) {
    if (g.sphereCount >= MAX_SPHERES) return;
    g.spheres[g.sphereCount] = (Sphere){ g.cameraTarget, 0.5f, GRAY, 0 };
    g.selectedSphere = g.sphereCount;
    g.sphereCount++;
    SetSceneUniforms();
}

EMSCRIPTEN_KEEPALIVE void DeleteSelectedSphere(void) {
    if (g.selectedSphere < 0 || g.selectedSphere >= g.sphereCount) return;
    g.spheres[g.selectedSphere] = g.spheres[g.sphereCount - 1];
    memset(&g.spheres[g.sphereCount - 1], 0, sizeof(Sphere));
    g.sphereCount--;
    g.selectedSphere = -1;
    SetSceneUniforms();
}

EMSCRIPTEN_KEEPALIVE float GetLightColorR(int i) { return (i >= 0 && i < g.lightCount) ? g.lights[i].color.x : 0; }
EMSCRIPTEN_KEEPALIVE float GetLightColorG(int i) { return (i >= 0 && i < g.lightCount) ? g.lights[i].color.y : 0; }
EMSCRIPTEN_KEEPALIVE float GetLightColorB(int i) { return (i >= 0 && i < g.lightCount) ? g.lights[i].color.z : 0; }
EMSCRIPTEN_KEEPALIVE float GetLightIntensity(int i) { return (i >= 0 && i < g.lightCount) ? g.lights[i].intensity : 0; }
EMSCRIPTEN_KEEPALIVE float GetLightDirX(int i) { return (i >= 0 && i < g.lightCount) ? g.lights[i].direction.x : 0; }
EMSCRIPTEN_KEEPALIVE float GetLightDirY(int i) { return (i >= 0 && i < g.lightCount) ? g.lights[i].direction.y : 0; }
EMSCRIPTEN_KEEPALIVE float GetLightDirZ(int i) { return (i >= 0 && i < g.lightCount) ? g.lights[i].direction.z : 0; }

EMSCRIPTEN_KEEPALIVE void SetLightColor(int i, float r, float gr, float b) {
    if (i < 0 || i >= g.lightCount) return;
    g.lights[i].color = (Vector3){ r, gr, b };
    SetLightUniforms();
}

EMSCRIPTEN_KEEPALIVE void SetLightIntensity(int i, float val) {
    if (i < 0 || i >= g.lightCount) return;
    g.lights[i].intensity = val;
    SetLightUniforms();
}

EMSCRIPTEN_KEEPALIVE void SetLightDir(int i, float x, float y, float z) {
    if (i < 0 || i >= g.lightCount) return;
    g.lights[i].direction = (Vector3){ x, y, z };
    SetLightUniforms();
}
#endif

// Ray-sphere intersection
static float RaySphereIntersect(Vector3 origin, Vector3 dir, Vector3 center, float radius) {
    Vector3 oc = Vector3Subtract(origin, center);
    float a = Vector3DotProduct(dir, dir);
    float b = Vector3DotProduct(dir, oc);
    float c = Vector3DotProduct(oc, oc) - radius * radius;
    float disc = b * b - a * c;
    if (disc < 0.0f) return -1.0f;
    float t = (-b - sqrtf(disc)) / a;
    return t > 0.0f ? t : -1.0f;
}

static void UpdateCameraFromAngles(void) {
    float cosV = cosf(g.cameraAngleV);
    g.camera.position = (Vector3){
        g.cameraTarget.x + g.cameraDistance * cosV * sinf(g.cameraAngleH),
        g.cameraTarget.y + g.cameraDistance * sinf(g.cameraAngleV),
        g.cameraTarget.z + g.cameraDistance * cosV * cosf(g.cameraAngleH),
    };
    g.camera.target = g.cameraTarget;
}

static void InitApp(void) {
    InitWindow(SCREEN_WIDTH, SCREEN_HEIGHT, "Raylib Web - Raytracing Shader");
    SetTargetFPS(60);

    g.camera = (Camera3D){0};
    g.camera.up = (Vector3){0.0f, 1.0f, 0.0f};
    g.camera.fovy = 45.0f;
    g.camera.projection = CAMERA_PERSPECTIVE;

    g.cameraTarget = (Vector3){0.0f, 0.0f, 0.0f};
    g.cameraDistance = 4.5f;
    g.cameraAngleH = 0.0f;
    g.cameraAngleV = 0.45f;
    UpdateCameraFromAngles();

    g.sphereCount = 4;
    g.spheres[0] = (Sphere){ (Vector3){0.0f, 0.0f, -1.0f}, 0.9f, DARKGREEN, 1 };
    g.spheres[1] = (Sphere){ (Vector3){0.0f, -100.5f, -1.0f}, 100.0f, DARKPURPLE, 1 };
    g.spheres[2] = (Sphere){ (Vector3){2.0f, 0.3f, 5.0f}, 0.8f, DARKBROWN, 1 };
    g.spheres[3] = (Sphere){ (Vector3){5.0f, 0.1f, 2.0f}, 0.8f, RED, 1 };
    memset(&g.spheres[4], 0, sizeof(Sphere) * (MAX_SPHERES - 4));

    g.lightCount = 1;
    g.lights[0] = (DirLight){ (Vector3){0.0f, 0.0f, -1.0f}, (Vector3){0.6f, 0.05f, 0.05f}, 0.9f };
    memset(&g.lights[1], 0, sizeof(DirLight) * (MAX_LIGHTS - 1));

    g.selectedSphere = -1;
    g.isDragging = false;

    g.shader = LoadShader(0, FRAGMENT_SHADER_PATH_WEB);
    g.locTime = GetShaderLocation(g.shader, "time");
    g.locSphereCount = GetShaderLocation(g.shader, "sphereCount");
    g.locLightCount = GetShaderLocation(g.shader, "lightCount");
    g.camPosLoc = GetShaderLocation(g.shader, "cameraPosition");
    g.invVpLoc = GetShaderLocation(g.shader, "invViewProj");

    SetSceneUniforms();
    SetLightUniforms();

    g.targetTexture = LoadRenderTexture(SCREEN_WIDTH, SCREEN_HEIGHT);
}

static void UpdateDrawFrame(void) {
    // Camera: right-click drag to orbit, scroll to zoom
    if (IsMouseButtonDown(MOUSE_BUTTON_RIGHT)) {
        Vector2 delta = GetMouseDelta();
        g.cameraAngleH -= delta.x * 0.005f;
        g.cameraAngleV += delta.y * 0.005f;
        if (g.cameraAngleV > 1.4f) g.cameraAngleV = 1.4f;
        if (g.cameraAngleV < -1.4f) g.cameraAngleV = -1.4f;
    }
    float wheel = GetMouseWheelMove();
    if (wheel != 0.0f) {
        g.cameraDistance -= wheel * 0.5f;
        if (g.cameraDistance < 1.0f) g.cameraDistance = 1.0f;
        if (g.cameraDistance > 50.0f) g.cameraDistance = 50.0f;
    }
    UpdateCameraFromAngles();

    // Sphere picking on left click
    if (IsMouseButtonPressed(MOUSE_BUTTON_LEFT)) {
        Vector2 mouse = GetMousePosition();
        float nx = (2.0f * mouse.x / SCREEN_WIDTH) - 1.0f;
        float ny = 1.0f - (2.0f * mouse.y / SCREEN_HEIGHT);
        Matrix view = GetCameraMatrix(g.camera);
        float aspect = (float)SCREEN_WIDTH / (float)SCREEN_HEIGHT;
        Matrix proj = MatrixPerspective(g.camera.fovy * DEG2RAD, aspect, 0.1f, 100.0f);
        Matrix vp = MatrixMultiply(view, proj);
        Matrix invVP = MatrixInvert(vp);

        Vector4 nearClip = { nx, ny, -1.0f, 1.0f };
        Vector4 worldNear = {
            invVP.m0*nearClip.x + invVP.m4*nearClip.y + invVP.m8*nearClip.z + invVP.m12*nearClip.w,
            invVP.m1*nearClip.x + invVP.m5*nearClip.y + invVP.m9*nearClip.z + invVP.m13*nearClip.w,
            invVP.m2*nearClip.x + invVP.m6*nearClip.y + invVP.m10*nearClip.z + invVP.m14*nearClip.w,
            invVP.m3*nearClip.x + invVP.m7*nearClip.y + invVP.m11*nearClip.z + invVP.m15*nearClip.w,
        };
        Vector3 worldPos = { worldNear.x/worldNear.w, worldNear.y/worldNear.w, worldNear.z/worldNear.w };
        Vector3 rayDir = Vector3Normalize(Vector3Subtract(worldPos, g.camera.position));

        float closestT = 1e38f;
        int closestIdx = -1;
        for (int i = 0; i < g.sphereCount; i++) {
            float t = RaySphereIntersect(g.camera.position, rayDir, g.spheres[i].center, g.spheres[i].radius);
            if (t > 0.0f && t < closestT) {
                closestT = t;
                closestIdx = i;
            }
        }
        g.selectedSphere = closestIdx;
        g.isDragging = (closestIdx != -1);
    }

    if (IsMouseButtonReleased(MOUSE_BUTTON_LEFT)) {
        g.isDragging = false;
    }

    // Drag sphere on camera-perpendicular plane
    if (g.isDragging && g.selectedSphere >= 0 && IsMouseButtonDown(MOUSE_BUTTON_LEFT)) {
        Vector2 delta = GetMouseDelta();
        if (delta.x != 0.0f || delta.y != 0.0f) {
            Vector3 forward = Vector3Normalize(Vector3Subtract(g.camera.target, g.camera.position));
            Vector3 right = Vector3Normalize(Vector3CrossProduct(forward, g.camera.up));
            Vector3 up = Vector3CrossProduct(right, forward);
            float moveFactor = g.cameraDistance * 0.003f;
            g.spheres[g.selectedSphere].center = Vector3Add(
                g.spheres[g.selectedSphere].center,
                Vector3Add(
                    Vector3Scale(right, delta.x * moveFactor),
                    Vector3Scale(up, -delta.y * moveFactor)
                )
            );
            SetSceneUniforms();
        }
    }

    // Render
    float t = (float)GetTime();
    if (g.locTime != -1) SetShaderValue(g.shader, g.locTime, &t, SHADER_UNIFORM_FLOAT);

    BeginTextureMode(g.targetTexture);
        ClearBackground(LIGHTGRAY);
        BeginMode3D(g.camera);
            for (int i = 0; i < g.sphereCount; i++)
                DrawSphere(g.spheres[i].center, g.spheres[i].radius, g.spheres[i].color);
            if (g.selectedSphere >= 0 && g.selectedSphere < g.sphereCount)
                DrawSphereWires(g.spheres[g.selectedSphere].center,
                    g.spheres[g.selectedSphere].radius + 0.02f, 8, 8, YELLOW);
            DrawGrid(10, 1.0f);
        EndMode3D();
    EndTextureMode();

    BeginDrawing();
        ClearBackground(BLACK);

        Matrix view = GetCameraMatrix(g.camera);
        float aspect = (float)SCREEN_WIDTH / (float)SCREEN_HEIGHT;
        Matrix proj = MatrixPerspective(g.camera.fovy * DEG2RAD, aspect, 0.1f, 100.0f);
        Matrix viewProj = MatrixMultiply(view, proj);
        Matrix invViewProj = MatrixInvert(viewProj);
        if (g.camPosLoc != -1) SetShaderValue(g.shader, g.camPosLoc, &g.camera.position, SHADER_UNIFORM_VEC3);
        if (g.invVpLoc != -1) SetShaderValueMatrix(g.shader, g.invVpLoc, invViewProj);

        BeginShaderMode(g.shader);
            DrawTextureRec(
                g.targetTexture.texture,
                (Rectangle){ 0, 0, (float)g.targetTexture.texture.width, (float)-g.targetTexture.texture.height },
                (Vector2){ 0, 0 },
                WHITE
            );
        EndShaderMode();

        DrawFPS(10, 10);
    EndDrawing();
}

int main(void) {
    InitApp();

#if defined(PLATFORM_WEB)
    emscripten_set_main_loop(UpdateDrawFrame, 0, 1);
#else
    while (!WindowShouldClose()) {
        UpdateDrawFrame();
    }
    if (g.shader.id != 0) UnloadShader(g.shader);
    UnloadRenderTexture(g.targetTexture);
    CloseWindow();
#endif

    return 0;
}
