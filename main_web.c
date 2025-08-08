#include "raylib.h"
#include "raymath.h"

#if defined(PLATFORM_WEB)
#include <emscripten/emscripten.h>
#endif

#include <stdio.h>

// Use the WebGL2-compatible shader
static const char *FRAGMENT_SHADER_PATH_WEB = "shaders/distance_web.glsl";

typedef struct Sphere {
    Vector3 center;
    float radius;
    Color color;
    int material; // 0 = lambertian, 1 = metal
} Sphere;

static inline Vector3 ColorToVec3(Color c) {
    return (Vector3){ (float)c.r/255.0f, (float)c.g/255.0f, (float)c.b/255.0f };
}

#define SCREEN_WIDTH 800
#define SCREEN_HEIGHT 600
#define SPHERE_COUNT 4

typedef struct AppState {
    Camera3D camera;
    Shader shader;
    RenderTexture2D targetTexture;
    int locTime;
    int locSphereCount;
    int camPosLoc;
    int invVpLoc;
    Sphere spheres[SPHERE_COUNT];
} AppState;

static AppState g; // global state for web main loop

static void SetSceneUniforms(void) {
    if (g.locSphereCount != -1) {
        int count = SPHERE_COUNT;
        SetShaderValue(g.shader, g.locSphereCount, &count, SHADER_UNIFORM_INT);
    }

    // WebGL 1.0 shader expects flat uniforms u_sX_*
    // Sphere 0
    int loc; Vector3 colorVec;
    if ((loc = GetShaderLocation(g.shader, "u_s0_center")) != -1)
        SetShaderValue(g.shader, loc, &g.spheres[0].center, SHADER_UNIFORM_VEC3);
    if ((loc = GetShaderLocation(g.shader, "u_s0_radius")) != -1)
        SetShaderValue(g.shader, loc, &g.spheres[0].radius, SHADER_UNIFORM_FLOAT);
    colorVec = ColorToVec3(g.spheres[0].color);
    if ((loc = GetShaderLocation(g.shader, "u_s0_color")) != -1)
        SetShaderValue(g.shader, loc, &colorVec, SHADER_UNIFORM_VEC3);
    if ((loc = GetShaderLocation(g.shader, "u_s0_material")) != -1)
        SetShaderValue(g.shader, loc, &g.spheres[0].material, SHADER_UNIFORM_INT);

    // Sphere 1
    if ((loc = GetShaderLocation(g.shader, "u_s1_center")) != -1)
        SetShaderValue(g.shader, loc, &g.spheres[1].center, SHADER_UNIFORM_VEC3);
    if ((loc = GetShaderLocation(g.shader, "u_s1_radius")) != -1)
        SetShaderValue(g.shader, loc, &g.spheres[1].radius, SHADER_UNIFORM_FLOAT);
    colorVec = ColorToVec3(g.spheres[1].color);
    if ((loc = GetShaderLocation(g.shader, "u_s1_color")) != -1)
        SetShaderValue(g.shader, loc, &colorVec, SHADER_UNIFORM_VEC3);
    if ((loc = GetShaderLocation(g.shader, "u_s1_material")) != -1)
        SetShaderValue(g.shader, loc, &g.spheres[1].material, SHADER_UNIFORM_INT);

    // Sphere 2
    if ((loc = GetShaderLocation(g.shader, "u_s2_center")) != -1)
        SetShaderValue(g.shader, loc, &g.spheres[2].center, SHADER_UNIFORM_VEC3);
    if ((loc = GetShaderLocation(g.shader, "u_s2_radius")) != -1)
        SetShaderValue(g.shader, loc, &g.spheres[2].radius, SHADER_UNIFORM_FLOAT);
    colorVec = ColorToVec3(g.spheres[2].color);
    if ((loc = GetShaderLocation(g.shader, "u_s2_color")) != -1)
        SetShaderValue(g.shader, loc, &colorVec, SHADER_UNIFORM_VEC3);
    if ((loc = GetShaderLocation(g.shader, "u_s2_material")) != -1)
        SetShaderValue(g.shader, loc, &g.spheres[2].material, SHADER_UNIFORM_INT);

    // Sphere 3
    if ((loc = GetShaderLocation(g.shader, "u_s3_center")) != -1)
        SetShaderValue(g.shader, loc, &g.spheres[3].center, SHADER_UNIFORM_VEC3);
    if ((loc = GetShaderLocation(g.shader, "u_s3_radius")) != -1)
        SetShaderValue(g.shader, loc, &g.spheres[3].radius, SHADER_UNIFORM_FLOAT);
    colorVec = ColorToVec3(g.spheres[3].color);
    if ((loc = GetShaderLocation(g.shader, "u_s3_color")) != -1)
        SetShaderValue(g.shader, loc, &colorVec, SHADER_UNIFORM_VEC3);
    if ((loc = GetShaderLocation(g.shader, "u_s3_material")) != -1)
        SetShaderValue(g.shader, loc, &g.spheres[3].material, SHADER_UNIFORM_INT);
}

static void InitApp(void) {
    InitWindow(SCREEN_WIDTH, SCREEN_HEIGHT, "Raylib Web - Raytracing Shader");
    SetTargetFPS(60);

    g.camera = (Camera3D){0};
    g.camera.position = (Vector3){0.0f, 2.0f, 4.0f};
    g.camera.target = (Vector3){0.0f, 0.0f, 0.0f};
    g.camera.up = (Vector3){0.0f, 1.0f, 0.0f};
    g.camera.fovy = 45.0f;
    g.camera.projection = CAMERA_PERSPECTIVE;

    g.spheres[0] = (Sphere){ (Vector3){0.0f, 0.0f, -1.0f}, 0.9f, DARKGREEN, 1 };
    g.spheres[1] = (Sphere){ (Vector3){0.0f, -100.5f, -1.0f}, 100.0f, DARKPURPLE, 1 };
    g.spheres[2] = (Sphere){ (Vector3){2.0f, 0.3f, 5.0f}, 0.8f, DARKBROWN, 1 };
    g.spheres[3] = (Sphere){ (Vector3){5.0f, 0.1f, 2.0f}, 0.8f, RED, 1 };

    g.shader = LoadShader(0, FRAGMENT_SHADER_PATH_WEB);
    g.locTime = GetShaderLocation(g.shader, "time");
    g.locSphereCount = GetShaderLocation(g.shader, "sphereCount");
    g.camPosLoc = GetShaderLocation(g.shader, "cameraPosition");
    g.invVpLoc = GetShaderLocation(g.shader, "invViewProj");

    SetSceneUniforms();

    g.targetTexture = LoadRenderTexture(SCREEN_WIDTH, SCREEN_HEIGHT);
}

static void UpdateDrawFrame(void) {
    UpdateCamera(&g.camera, CAMERA_ORBITAL);

    float t = (float)GetTime();
    if (g.locTime != -1) SetShaderValue(g.shader, g.locTime, &t, SHADER_UNIFORM_FLOAT);

    BeginTextureMode(g.targetTexture);
        ClearBackground(LIGHTGRAY);
        BeginMode3D(g.camera);
            for (int i = 0; i < SPHERE_COUNT; i++) {
                DrawSphere(g.spheres[i].center, g.spheres[i].radius, g.spheres[i].color);
            }
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
        DrawText("Raylib Web (WebGL2) - Raytracing", 10, 40, 20, LIME);
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


