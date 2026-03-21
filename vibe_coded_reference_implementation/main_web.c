#include "raylib.h"
#include "raymath.h"

#if defined(PLATFORM_WEB)
#include <emscripten/emscripten.h>
#endif

#include <stdio.h>
#include <string.h>

static const char *FRAGMENT_SHADER_PATH_WEB = "shaders/distance_web.glsl";

#define SCREEN_WIDTH 1280
#define SCREEN_HEIGHT 720
#define MAX_SPHERES 10
#define MAX_LIGHTS 4

// Materials: 0 = Lambertian, 1 = Metal, 2 = Emissive, 3 = Dielectric (glass)
typedef struct Sphere {
    Vector3 center;
    float radius;
    Color color;
    int material;
    // Emissive properties
    Vector3 emission;
    float emissionStrength;
    // Dielectric properties
    float ior;
    // Metal properties
    float roughness;
    // Blinn-Phong specular
    float specular;
    float shininess;
} Sphere;

// type: 0 = directional, 1 = point
typedef struct Light {
    int type;
    Vector3 direction;
    Vector3 position;
    Vector3 color;
    float intensity;
    float radius; // for soft shadows / area lights
} Light;

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
    int locKLinear;
    int locKQuadratic;
    int locAORadius;
    int locAOStrength;
    int locToneMapMode;
    Sphere spheres[MAX_SPHERES];
    int sphereCount;
    Light lights[MAX_LIGHTS];
    int lightCount;
    int selectedSphere;
    bool isDragging;
    float cameraAngleH;
    float cameraAngleV;
    float cameraDistance;
    Vector3 cameraTarget;
    // Rendering params
    float aoRadius;
    float aoStrength;
    int toneMapMode;
    // Temporal accumulation
    RenderTexture2D accumTexture[2];
    int accumIndex;
    int frameCount;
    int locFrameCount;
    int locAccumTexture;
    int locResolution;
    Vector3 prevCamPos;
} AppState;

static AppState g;

static void SetSceneUniforms(void) {
    g.frameCount = 0;  // reset accumulation on scene change
    if (g.locSphereCount != -1)
        SetShaderValue(g.shader, g.locSphereCount, &g.sphereCount, SHADER_UNIFORM_INT);

    char name[64];
    for (int i = 0; i < MAX_SPHERES; i++) {
        int loc;
        // Geometry
        sprintf(name, "u_s%d_center", i);
        if ((loc = GetShaderLocation(g.shader, name)) != -1)
            SetShaderValue(g.shader, loc, &g.spheres[i].center, SHADER_UNIFORM_VEC3);
        sprintf(name, "u_s%d_radius", i);
        if ((loc = GetShaderLocation(g.shader, name)) != -1)
            SetShaderValue(g.shader, loc, &g.spheres[i].radius, SHADER_UNIFORM_FLOAT);
        // Base material
        sprintf(name, "u_s%d_color", i);
        Vector3 colorVec = ColorToVec3(g.spheres[i].color);
        if ((loc = GetShaderLocation(g.shader, name)) != -1)
            SetShaderValue(g.shader, loc, &colorVec, SHADER_UNIFORM_VEC3);
        sprintf(name, "u_s%d_material", i);
        if ((loc = GetShaderLocation(g.shader, name)) != -1)
            SetShaderValue(g.shader, loc, &g.spheres[i].material, SHADER_UNIFORM_INT);
        // Emission
        sprintf(name, "u_s%d_emission", i);
        if ((loc = GetShaderLocation(g.shader, name)) != -1)
            SetShaderValue(g.shader, loc, &g.spheres[i].emission, SHADER_UNIFORM_VEC3);
        sprintf(name, "u_s%d_emissionStrength", i);
        if ((loc = GetShaderLocation(g.shader, name)) != -1)
            SetShaderValue(g.shader, loc, &g.spheres[i].emissionStrength, SHADER_UNIFORM_FLOAT);
        // IOR
        sprintf(name, "u_s%d_ior", i);
        if ((loc = GetShaderLocation(g.shader, name)) != -1)
            SetShaderValue(g.shader, loc, &g.spheres[i].ior, SHADER_UNIFORM_FLOAT);
        // Roughness
        sprintf(name, "u_s%d_roughness", i);
        if ((loc = GetShaderLocation(g.shader, name)) != -1)
            SetShaderValue(g.shader, loc, &g.spheres[i].roughness, SHADER_UNIFORM_FLOAT);
        // Specular
        sprintf(name, "u_s%d_specular", i);
        if ((loc = GetShaderLocation(g.shader, name)) != -1)
            SetShaderValue(g.shader, loc, &g.spheres[i].specular, SHADER_UNIFORM_FLOAT);
        sprintf(name, "u_s%d_shininess", i);
        if ((loc = GetShaderLocation(g.shader, name)) != -1)
            SetShaderValue(g.shader, loc, &g.spheres[i].shininess, SHADER_UNIFORM_FLOAT);
    }
}

static void SetLightUniforms(void) {
    g.frameCount = 0;  // reset accumulation on light change
    if (g.locLightCount != -1)
        SetShaderValue(g.shader, g.locLightCount, &g.lightCount, SHADER_UNIFORM_INT);

    char name[64];
    for (int i = 0; i < MAX_LIGHTS; i++) {
        int loc;
        sprintf(name, "u_l%d_type", i);
        if ((loc = GetShaderLocation(g.shader, name)) != -1)
            SetShaderValue(g.shader, loc, &g.lights[i].type, SHADER_UNIFORM_INT);
        sprintf(name, "u_l%d_direction", i);
        if ((loc = GetShaderLocation(g.shader, name)) != -1)
            SetShaderValue(g.shader, loc, &g.lights[i].direction, SHADER_UNIFORM_VEC3);
        sprintf(name, "u_l%d_position", i);
        if ((loc = GetShaderLocation(g.shader, name)) != -1)
            SetShaderValue(g.shader, loc, &g.lights[i].position, SHADER_UNIFORM_VEC3);
        sprintf(name, "u_l%d_color", i);
        if ((loc = GetShaderLocation(g.shader, name)) != -1)
            SetShaderValue(g.shader, loc, &g.lights[i].color, SHADER_UNIFORM_VEC3);
        sprintf(name, "u_l%d_intensity", i);
        if ((loc = GetShaderLocation(g.shader, name)) != -1)
            SetShaderValue(g.shader, loc, &g.lights[i].intensity, SHADER_UNIFORM_FLOAT);
        sprintf(name, "u_l%d_radius", i);
        if ((loc = GetShaderLocation(g.shader, name)) != -1)
            SetShaderValue(g.shader, loc, &g.lights[i].radius, SHADER_UNIFORM_FLOAT);
    }
}

static void SetRenderUniforms(void) {
    g.frameCount = 0;  // reset accumulation on render setting change
    if (g.locAORadius != -1)
        SetShaderValue(g.shader, g.locAORadius, &g.aoRadius, SHADER_UNIFORM_FLOAT);
    if (g.locAOStrength != -1)
        SetShaderValue(g.shader, g.locAOStrength, &g.aoStrength, SHADER_UNIFORM_FLOAT);
    if (g.locToneMapMode != -1)
        SetShaderValue(g.shader, g.locToneMapMode, &g.toneMapMode, SHADER_UNIFORM_INT);
}

// === Emscripten JS API ===

#ifdef PLATFORM_WEB

// --- Sphere getters ---
EMSCRIPTEN_KEEPALIVE int GetSphereCount(void) { return g.sphereCount; }
EMSCRIPTEN_KEEPALIVE int GetSelectedSphere(void) { return g.selectedSphere; }
EMSCRIPTEN_KEEPALIVE int GetSphereColorR(int i) { return (i >= 0 && i < g.sphereCount) ? g.spheres[i].color.r : 0; }
EMSCRIPTEN_KEEPALIVE int GetSphereColorG(int i) { return (i >= 0 && i < g.sphereCount) ? g.spheres[i].color.g : 0; }
EMSCRIPTEN_KEEPALIVE int GetSphereColorB(int i) { return (i >= 0 && i < g.sphereCount) ? g.spheres[i].color.b : 0; }
EMSCRIPTEN_KEEPALIVE int GetSphereMaterial(int i) { return (i >= 0 && i < g.sphereCount) ? g.spheres[i].material : 0; }
EMSCRIPTEN_KEEPALIVE float GetSphereRadius(int i) { return (i >= 0 && i < g.sphereCount) ? g.spheres[i].radius : 0; }
EMSCRIPTEN_KEEPALIVE float GetSphereEmissionR(int i) { return (i >= 0 && i < g.sphereCount) ? g.spheres[i].emission.x : 0; }
EMSCRIPTEN_KEEPALIVE float GetSphereEmissionG(int i) { return (i >= 0 && i < g.sphereCount) ? g.spheres[i].emission.y : 0; }
EMSCRIPTEN_KEEPALIVE float GetSphereEmissionB(int i) { return (i >= 0 && i < g.sphereCount) ? g.spheres[i].emission.z : 0; }
EMSCRIPTEN_KEEPALIVE float GetSphereEmissionStrength(int i) { return (i >= 0 && i < g.sphereCount) ? g.spheres[i].emissionStrength : 0; }
EMSCRIPTEN_KEEPALIVE float GetSphereIOR(int i) { return (i >= 0 && i < g.sphereCount) ? g.spheres[i].ior : 1.5f; }
EMSCRIPTEN_KEEPALIVE float GetSphereRoughness(int i) { return (i >= 0 && i < g.sphereCount) ? g.spheres[i].roughness : 0; }
EMSCRIPTEN_KEEPALIVE float GetSphereSpecular(int i) { return (i >= 0 && i < g.sphereCount) ? g.spheres[i].specular : 0; }
EMSCRIPTEN_KEEPALIVE float GetSphereShininess(int i) { return (i >= 0 && i < g.sphereCount) ? g.spheres[i].shininess : 32; }

// --- Sphere setters ---
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

EMSCRIPTEN_KEEPALIVE void SetSphereEmission(int i, float r, float gr, float b) {
    if (i < 0 || i >= g.sphereCount) return;
    g.spheres[i].emission = (Vector3){ r, gr, b };
    SetSceneUniforms();
}

EMSCRIPTEN_KEEPALIVE void SetSphereEmissionStrength(int i, float val) {
    if (i < 0 || i >= g.sphereCount) return;
    g.spheres[i].emissionStrength = val;
    SetSceneUniforms();
}

EMSCRIPTEN_KEEPALIVE void SetSphereIOR(int i, float val) {
    if (i < 0 || i >= g.sphereCount) return;
    g.spheres[i].ior = val;
    SetSceneUniforms();
}

EMSCRIPTEN_KEEPALIVE void SetSphereRoughness(int i, float val) {
    if (i < 0 || i >= g.sphereCount) return;
    g.spheres[i].roughness = val;
    SetSceneUniforms();
}

EMSCRIPTEN_KEEPALIVE void SetSphereSpecular(int i, float val) {
    if (i < 0 || i >= g.sphereCount) return;
    g.spheres[i].specular = val;
    SetSceneUniforms();
}

EMSCRIPTEN_KEEPALIVE void SetSphereShininess(int i, float val) {
    if (i < 0 || i >= g.sphereCount) return;
    g.spheres[i].shininess = val;
    SetSceneUniforms();
}

EMSCRIPTEN_KEEPALIVE void AddSphere(void) {
    if (g.sphereCount >= MAX_SPHERES) return;
    g.spheres[g.sphereCount] = (Sphere){
        .center = g.cameraTarget,
        .radius = 0.5f,
        .color = GRAY,
        .material = 0,
        .emission = (Vector3){0,0,0},
        .emissionStrength = 0.0f,
        .ior = 1.5f,
        .roughness = 0.0f,
        .specular = 0.05f,
        .shininess = 32.0f,
    };
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

// --- Light getters ---
EMSCRIPTEN_KEEPALIVE int   GetLightType(int i)       { return (i >= 0 && i < g.lightCount) ? g.lights[i].type : 0; }
EMSCRIPTEN_KEEPALIVE float GetLightColorR(int i)     { return (i >= 0 && i < g.lightCount) ? g.lights[i].color.x : 0; }
EMSCRIPTEN_KEEPALIVE float GetLightColorG(int i)     { return (i >= 0 && i < g.lightCount) ? g.lights[i].color.y : 0; }
EMSCRIPTEN_KEEPALIVE float GetLightColorB(int i)     { return (i >= 0 && i < g.lightCount) ? g.lights[i].color.z : 0; }
EMSCRIPTEN_KEEPALIVE float GetLightIntensity(int i)  { return (i >= 0 && i < g.lightCount) ? g.lights[i].intensity : 0; }
EMSCRIPTEN_KEEPALIVE float GetLightDirX(int i)       { return (i >= 0 && i < g.lightCount) ? g.lights[i].direction.x : 0; }
EMSCRIPTEN_KEEPALIVE float GetLightDirY(int i)       { return (i >= 0 && i < g.lightCount) ? g.lights[i].direction.y : 0; }
EMSCRIPTEN_KEEPALIVE float GetLightDirZ(int i)       { return (i >= 0 && i < g.lightCount) ? g.lights[i].direction.z : 0; }
EMSCRIPTEN_KEEPALIVE float GetLightPosX(int i)       { return (i >= 0 && i < g.lightCount) ? g.lights[i].position.x : 0; }
EMSCRIPTEN_KEEPALIVE float GetLightPosY(int i)       { return (i >= 0 && i < g.lightCount) ? g.lights[i].position.y : 0; }
EMSCRIPTEN_KEEPALIVE float GetLightPosZ(int i)       { return (i >= 0 && i < g.lightCount) ? g.lights[i].position.z : 0; }
EMSCRIPTEN_KEEPALIVE float GetLightRadius(int i)     { return (i >= 0 && i < g.lightCount) ? g.lights[i].radius : 0; }

// --- Light setters ---
EMSCRIPTEN_KEEPALIVE void SetLightType(int i, int type) {
    if (i < 0 || i >= g.lightCount) return;
    g.lights[i].type = type;
    SetLightUniforms();
}

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

EMSCRIPTEN_KEEPALIVE void SetLightPos(int i, float x, float y, float z) {
    if (i < 0 || i >= g.lightCount) return;
    g.lights[i].position = (Vector3){ x, y, z };
    SetLightUniforms();
}

EMSCRIPTEN_KEEPALIVE void SetLightRadius(int i, float val) {
    if (i < 0 || i >= g.lightCount) return;
    g.lights[i].radius = val;
    SetLightUniforms();
}

// --- Render setting getters/setters ---
EMSCRIPTEN_KEEPALIVE float GetAOStrength(void) { return g.aoStrength; }
EMSCRIPTEN_KEEPALIVE float GetAORadius(void) { return g.aoRadius; }
EMSCRIPTEN_KEEPALIVE int   GetToneMapMode(void) { return g.toneMapMode; }

EMSCRIPTEN_KEEPALIVE void SetAOStrength(float val) {
    g.aoStrength = val;
    SetRenderUniforms();
}

EMSCRIPTEN_KEEPALIVE void SetAORadius(float val) {
    g.aoRadius = val;
    SetRenderUniforms();
}

EMSCRIPTEN_KEEPALIVE void SetToneMapMode(int mode) {
    g.toneMapMode = mode;
    SetRenderUniforms();
}

#endif // PLATFORM_WEB

// Ray-sphere intersection (for mouse picking on CPU side)
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

static Sphere MakeLambertian(Vector3 pos, float r, Color col) {
    return (Sphere){
        .center = pos, .radius = r, .color = col, .material = 0,
        .emission = {0,0,0}, .emissionStrength = 0,
        .ior = 1.5f, .roughness = 0,
        .specular = 0.05f, .shininess = 32,
    };
}

static Sphere MakeMetal(Vector3 pos, float r, Color col, float rough) {
    return (Sphere){
        .center = pos, .radius = r, .color = col, .material = 1,
        .emission = {0,0,0}, .emissionStrength = 0,
        .ior = 1.5f, .roughness = rough,
        .specular = 0.8f, .shininess = 256,
    };
}

static Sphere MakeEmissive(Vector3 pos, float r, Color col, Vector3 emCol, float emStr) {
    return (Sphere){
        .center = pos, .radius = r, .color = col, .material = 2,
        .emission = emCol, .emissionStrength = emStr,
        .ior = 1.5f, .roughness = 0,
        .specular = 0, .shininess = 0,
    };
}

static Sphere MakeGlass(Vector3 pos, float r, Color tint, float ior) {
    return (Sphere){
        .center = pos, .radius = r, .color = tint, .material = 3,
        .emission = {0,0,0}, .emissionStrength = 0,
        .ior = ior, .roughness = 0,
        .specular = 0.5f, .shininess = 128,
    };
}

static void InitApp(void) {
    InitWindow(SCREEN_WIDTH, SCREEN_HEIGHT, "Raytracer — Full Lighting Reference");
    SetTargetFPS(60);

    g.camera = (Camera3D){0};
    g.camera.up = (Vector3){0.0f, 1.0f, 0.0f};
    g.camera.fovy = 45.0f;
    g.camera.projection = CAMERA_PERSPECTIVE;

    g.cameraTarget = (Vector3){0.0f, 0.0f, -1.0f};
    g.cameraDistance = 5.0f;
    g.cameraAngleH = 0.4f;
    g.cameraAngleV = 0.35f;
    UpdateCameraFromAngles();

    // Demo scene showcasing all material types
    g.sphereCount = 5;
    g.spheres[0] = MakeLambertian((Vector3){0.0f, -100.5f, -1.0f}, 100.0f, (Color){140, 140, 160, 255}); // ground
    g.spheres[1] = MakeLambertian((Vector3){0.0f, 0.0f, -1.0f}, 0.5f, (Color){40, 80, 180, 255});        // blue diffuse
    g.spheres[2] = MakeMetal((Vector3){1.2f, 0.0f, -1.0f}, 0.5f, (Color){220, 180, 60, 255}, 0.05f);     // gold metal
    g.spheres[3] = MakeGlass((Vector3){-1.2f, 0.0f, -1.0f}, 0.5f, WHITE, 1.5f);                          // glass
    g.spheres[4] = MakeEmissive((Vector3){0.0f, 1.5f, -1.0f}, 0.25f,
                                (Color){255, 200, 80, 255},
                                (Vector3){1.0f, 0.8f, 0.3f}, 5.0f);                                       // glowing orb
    memset(&g.spheres[5], 0, sizeof(Sphere) * (MAX_SPHERES - 5));

    // Two lights: directional + point (with soft shadow radius)
    g.lightCount = 2;
    g.lights[0] = (Light){
        .type = 0,
        .direction = (Vector3){0.5f, -1.0f, -0.3f},
        .position  = (Vector3){0,0,0},
        .color     = (Vector3){0.9f, 0.85f, 0.7f},
        .intensity = 0.8f,
        .radius    = 0.0f, // hard shadow
    };
    g.lights[1] = (Light){
        .type = 1,
        .direction = (Vector3){0,0,0},
        .position  = (Vector3){-2.0f, 3.0f, 1.0f},
        .color     = (Vector3){0.4f, 0.5f, 0.9f},
        .intensity = 1.5f,
        .radius    = 0.3f, // soft shadow
    };
    memset(&g.lights[2], 0, sizeof(Light) * (MAX_LIGHTS - 2));

    g.selectedSphere = -1;
    g.isDragging = false;

    // Rendering defaults
    g.aoRadius = 0.5f;
    g.aoStrength = 0.5f;
    g.toneMapMode = 2; // ACES by default

    // Load shader and get uniform locations
    g.shader = LoadShader(0, FRAGMENT_SHADER_PATH_WEB);
    g.locTime = GetShaderLocation(g.shader, "time");
    g.locSphereCount = GetShaderLocation(g.shader, "sphereCount");
    g.locLightCount = GetShaderLocation(g.shader, "lightCount");
    g.camPosLoc = GetShaderLocation(g.shader, "cameraPosition");
    g.invVpLoc = GetShaderLocation(g.shader, "invViewProj");
    g.locKLinear = GetShaderLocation(g.shader, "k_linear");
    g.locKQuadratic = GetShaderLocation(g.shader, "k_quadratic");
    g.locAORadius = GetShaderLocation(g.shader, "aoRadius");
    g.locAOStrength = GetShaderLocation(g.shader, "aoStrength");
    g.locToneMapMode = GetShaderLocation(g.shader, "toneMapMode");

    // Attenuation defaults
    float kLinear = 0.09f;
    float kQuadratic = 0.032f;
    if (g.locKLinear != -1)
        SetShaderValue(g.shader, g.locKLinear, &kLinear, SHADER_UNIFORM_FLOAT);
    if (g.locKQuadratic != -1)
        SetShaderValue(g.shader, g.locKQuadratic, &kQuadratic, SHADER_UNIFORM_FLOAT);

    SetSceneUniforms();
    SetLightUniforms();
    SetRenderUniforms();

    g.targetTexture = LoadRenderTexture(SCREEN_WIDTH, SCREEN_HEIGHT);

    // Temporal accumulation setup
    g.locFrameCount = GetShaderLocation(g.shader, "frameCount");
    g.locAccumTexture = GetShaderLocation(g.shader, "accumTexture");
    g.locResolution = GetShaderLocation(g.shader, "resolution");
    float res[2] = {(float)SCREEN_WIDTH, (float)SCREEN_HEIGHT};
    if (g.locResolution != -1)
        SetShaderValue(g.shader, g.locResolution, res, SHADER_UNIFORM_VEC2);
    g.accumTexture[0] = LoadRenderTexture(SCREEN_WIDTH, SCREEN_HEIGHT);
    g.accumTexture[1] = LoadRenderTexture(SCREEN_WIDTH, SCREEN_HEIGHT);
    g.accumIndex = 0;
    g.frameCount = 0;
    g.prevCamPos = g.camera.position;
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

    // Detect camera change -> reset accumulation
    if (g.camera.position.x != g.prevCamPos.x ||
        g.camera.position.y != g.prevCamPos.y ||
        g.camera.position.z != g.prevCamPos.z) {
        g.frameCount = 0;
        g.prevCamPos = g.camera.position;
    }

    // Advance accumulation frame counter
    g.frameCount++;
    if (g.locFrameCount != -1)
        SetShaderValue(g.shader, g.locFrameCount, &g.frameCount, SHADER_UNIFORM_INT);

    float t = (float)GetTime();
    if (g.locTime != -1) SetShaderValue(g.shader, g.locTime, &t, SHADER_UNIFORM_FLOAT);

    // Rasterize geometry (used as quad source for the raytrace shader)
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

    // Set camera uniforms for the raytrace shader
    Matrix view = GetCameraMatrix(g.camera);
    float aspect = (float)SCREEN_WIDTH / (float)SCREEN_HEIGHT;
    Matrix proj = MatrixPerspective(g.camera.fovy * DEG2RAD, aspect, 0.1f, 100.0f);
    Matrix viewProj = MatrixMultiply(view, proj);
    Matrix invViewProj = MatrixInvert(viewProj);
    if (g.camPosLoc != -1) SetShaderValue(g.shader, g.camPosLoc, &g.camera.position, SHADER_UNIFORM_VEC3);
    if (g.invVpLoc != -1) SetShaderValueMatrix(g.shader, g.invVpLoc, invViewProj);

    // Raytrace into accumulation buffer (ping-pong)
    int readIdx = g.accumIndex;
    int writeIdx = 1 - g.accumIndex;

    BeginTextureMode(g.accumTexture[writeIdx]);
        ClearBackground(BLACK);
        BeginShaderMode(g.shader);
            if (g.frameCount > 1 && g.locAccumTexture != -1)
                SetShaderValueTexture(g.shader, g.locAccumTexture, g.accumTexture[readIdx].texture);
            DrawTextureRec(
                g.targetTexture.texture,
                (Rectangle){ 0, 0, (float)g.targetTexture.texture.width, (float)-g.targetTexture.texture.height },
                (Vector2){ 0, 0 },
                WHITE
            );
        EndShaderMode();
    EndTextureMode();

    g.accumIndex = writeIdx;

    // Display the accumulated result
    BeginDrawing();
        ClearBackground(BLACK);
        DrawTextureRec(
            g.accumTexture[g.accumIndex].texture,
            (Rectangle){ 0, 0, (float)g.accumTexture[g.accumIndex].texture.width,
                         (float)-g.accumTexture[g.accumIndex].texture.height },
            (Vector2){ 0, 0 },
            WHITE
        );
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
    UnloadRenderTexture(g.accumTexture[0]);
    UnloadRenderTexture(g.accumTexture[1]);
    CloseWindow();
#endif

    return 0;
}
