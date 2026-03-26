#include "raylib.h"
#include "raymath.h"
#include "rlgl.h"

#if defined(PLATFORM_WEB)
#include <emscripten/emscripten.h>
#endif

#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <math.h>

#define SCREEN_WIDTH 1280
#define SCREEN_HEIGHT 720
#define MAX_PRIMS 64
#define MAX_LIGHTS 8

// Must match shader defines — 8-wide horizontal layout
#define SCENE_TEX_WIDTH 8
#define LIGHT_ROW_BASE MAX_PRIMS   // lights start at row 64
#define SCENE_TEX_HEIGHT (MAX_PRIMS + MAX_LIGHTS) // 72 rows

// Primitive types
#define PRIM_SPHERE   0
#define PRIM_QUAD     1
#define PRIM_TRIANGLE 2

// Materials: 0 = Lambertian, 1 = Metal, 2 = Emissive, 3 = Dielectric
typedef struct Primitive {
    int primType;
    Color color;
    int material;
    Vector3 emission;
    float emissionStrength;
    float ior, roughness, specular, shininess;
    float geom[16]; // 4 x vec4 type-specific geometry
} Primitive;

// type: 0 = directional, 1 = point
typedef struct Light {
    int type;
    Vector3 direction;
    Vector3 position;
    Vector3 color;
    float intensity;
    float radius;
} Light;

// Scene presets
#define SCENE_DEFAULT   0
#define SCENE_CORNELL   1
#define SCENE_MATERIALS 2
#define NUM_SCENES      3

typedef struct AppState {
    Camera3D camera;
    Shader shader;
    Shader displayShader;
    RenderTexture2D targetTexture;
    // Raytrace shader locations
    int locTime, locPrimCount, locLightCount, locEmissiveCount, locEmissiveIndices, locSPP;
    int camPosLoc, invVpLoc;
    int locKLinear, locKQuadratic;
    int locAORadius, locAOStrength;
    int locFrameCount, locAccumTexture, locResolution, locSceneData;
    // Display shader locations
    int locDisplayToneMap, locDisplayExposure;
    // Environment map
    int locEnvMap, locUseEnvMap, locEnvIntensity, locEnvRotation;
    Texture2D envMapTex;
    int useEnvMap;       // 0=gradient, 1=HDR texture, 2=procedural sky
    float envIntensity;
    float envRotation;
    // Scene data texture
    Texture2D sceneDataTex;
    float sceneDataBuf[SCENE_TEX_HEIGHT * SCENE_TEX_WIDTH * 4];
    // Scene
    Primitive prims[MAX_PRIMS];
    int primCount;
    Light lights[MAX_LIGHTS];
    int lightCount;
    int selectedSphere; // selected prim index
    bool isDragging;
    int currentScene;
    // Camera orbit
    float cameraAngleH, cameraAngleV, cameraDistance;
    Vector3 cameraTarget;
    // Rendering
    float aoRadius, aoStrength, exposure;
    int toneMapMode, samplesPerFrame, uncapFPS;
    // Accumulation
    RenderTexture2D accumTexture[2];
    int accumIndex, frameCount;
    Vector3 prevCamPos;
} AppState;

static AppState g;

// Forward declarations
static void UpdateCameraFromAngles(void);

// ============================================================
// Primitive constructors
// ============================================================

static void SetSphereGeom(Primitive *p, Vector3 center, float radius) {
    p->primType = PRIM_SPHERE;
    memset(p->geom, 0, sizeof(p->geom));
    p->geom[0] = center.x; p->geom[1] = center.y; p->geom[2] = center.z;
    p->geom[3] = radius;
}

static void SetQuadGeom(Primitive *p, Vector3 Q, Vector3 u, Vector3 v) {
    p->primType = PRIM_QUAD;
    memset(p->geom, 0, sizeof(p->geom));
    p->geom[0] = Q.x; p->geom[1] = Q.y; p->geom[2] = Q.z;
    p->geom[4] = u.x; p->geom[5] = u.y; p->geom[6] = u.z;
    p->geom[8] = v.x; p->geom[9] = v.y; p->geom[10] = v.z;
}

static void SetMaterial(Primitive *p, Color col, int mat,
                        Vector3 em, float emStr,
                        float ior, float rough, float spec, float shine) {
    p->color = col; p->material = mat;
    p->emission = em; p->emissionStrength = emStr;
    p->ior = ior; p->roughness = rough;
    p->specular = spec; p->shininess = shine;
}

static Primitive MakeLambertianSphere(Vector3 pos, float r, Color col) {
    Primitive p = {0};
    SetSphereGeom(&p, pos, r);
    SetMaterial(&p, col, 0, (Vector3){0,0,0}, 0, 1.5f, 0.5f, 0.04f, 32);
    return p;
}

static Primitive MakeMetalSphere(Vector3 pos, float r, Color col, float rough) {
    Primitive p = {0};
    SetSphereGeom(&p, pos, r);
    SetMaterial(&p, col, 1, (Vector3){0,0,0}, 0, 1.5f, rough, 0.8f, 256);
    return p;
}

static Primitive MakeEmissiveSphere(Vector3 pos, float r, Color col, Vector3 emCol, float emStr) {
    Primitive p = {0};
    SetSphereGeom(&p, pos, r);
    SetMaterial(&p, col, 2, emCol, emStr, 1.5f, 0, 0, 0);
    return p;
}

static Primitive MakeGlassSphere(Vector3 pos, float r, Color tint, float ior) {
    Primitive p = {0};
    SetSphereGeom(&p, pos, r);
    SetMaterial(&p, tint, 3, (Vector3){0,0,0}, 0, ior, 0, 0.5f, 128);
    return p;
}

static Primitive MakeLambertianQuad(Vector3 Q, Vector3 u, Vector3 v, Color col) {
    Primitive p = {0};
    SetQuadGeom(&p, Q, u, v);
    SetMaterial(&p, col, 0, (Vector3){0,0,0}, 0, 1.5f, 0.5f, 0.04f, 32);
    return p;
}

static Primitive MakeEmissiveQuad(Vector3 Q, Vector3 u, Vector3 v, Color col, Vector3 emCol, float emStr) {
    Primitive p = {0};
    SetQuadGeom(&p, Q, u, v);
    SetMaterial(&p, col, 2, emCol, emStr, 1.5f, 0, 0, 0);
    return p;
}

// Build a box from two corners — adds 6 quads to prims[], returns count added
static int AddBox(Primitive *prims, int startIdx, Vector3 a, Vector3 b, Color col, int mat) {
    float x0 = fminf(a.x, b.x), x1 = fmaxf(a.x, b.x);
    float y0 = fminf(a.y, b.y), y1 = fmaxf(a.y, b.y);
    float z0 = fminf(a.z, b.z), z1 = fmaxf(a.z, b.z);
    Vector3 dx = {x1-x0, 0, 0}, dy = {0, y1-y0, 0}, dz = {0, 0, z1-z0};
    Vector3 ndx = {-(x1-x0), 0, 0}, ndy = {0, -(y1-y0), 0}, ndz = {0, 0, -(z1-z0)};

    // Front (+Z), Right (+X), Back (-Z), Left (-X), Top (+Y), Bottom (-Y)
    Vector3 corners[6] = {
        {x0, y0, z1}, {x1, y0, z1}, {x1, y0, z0},
        {x0, y0, z0}, {x0, y1, z1}, {x0, y0, z0}
    };
    Vector3 us[6] = { dx, ndz, ndx, dz, dx, dx };
    Vector3 vs[6] = { dy, dy, dy, dy, ndz, dz };

    for (int i = 0; i < 6; i++) {
        prims[startIdx + i] = MakeLambertianQuad(corners[i], us[i], vs[i], col);
        prims[startIdx + i].material = mat;
    }
    return 6;
}

// ============================================================
// Scene presets
// ============================================================

static void LoadDefaultScene(void) {
    int n = 0;

    // Ground: dark mirror floor — catches all the colored reflections
    g.prims[n++] = MakeMetalSphere((Vector3){0, -100.5f, -2.0f}, 100.0f, (Color){18, 18, 22, 255}, 0.35f);

    // === HERO TRIANGLE — three spheres in tight composition ===

    // Center hero: large hollow glass orb — the protagonist
    g.prims[n++] = MakeGlassSphere((Vector3){0, 0.55f, -2.2f}, 1.05f, (Color){245, 248, 255, 255}, 1.52f);
    g.prims[n++] = MakeGlassSphere((Vector3){0, 0.55f, -2.2f}, 0.92f, WHITE, 1.0f / 1.52f);

    // Left hero: mirror chrome — reflects the golden hour sky
    g.prims[n++] = MakeMetalSphere((Vector3){-1.8f, 0.05f, -1.3f}, 0.55f, (Color){240, 238, 235, 255}, 0.005f);

    // Right hero: polished gold — warm contrast
    g.prims[n++] = MakeMetalSphere((Vector3){1.6f, 0.0f, -1.0f}, 0.5f, (Color){255, 195, 55, 255}, 0.02f);

    // === SUPPORTING CAST ===

    // Deep behind: large dark copper — anchors the depth
    g.prims[n++] = MakeMetalSphere((Vector3){-0.8f, 0.2f, -4.5f}, 0.7f, (Color){180, 100, 80, 255}, 0.2f);

    // Mid-right: small brushed silver
    g.prims[n++] = MakeMetalSphere((Vector3){2.8f, -0.15f, -2.5f}, 0.35f, (Color){220, 220, 225, 255}, 0.12f);

    // Far left: matte obsidian
    g.prims[n] = MakeLambertianSphere((Vector3){-3.0f, -0.1f, -3.0f}, 0.4f, (Color){25, 25, 30, 255});
    g.prims[n].roughness = 0.95f; n++;

    // === EMISSIVE ACCENTS — deliberate, not scattered ===

    // Warm amber glow — just above and behind the glass hero (backlight halo)
    g.prims[n++] = MakeEmissiveSphere((Vector3){0.3f, 2.2f, -4.0f}, 0.3f,
        (Color){255, 170, 70, 255}, (Vector3){1.0f, 0.65f, 0.2f}, 10.0f);

    // Cool cyan accent — off to the left, low, creates floor reflection
    g.prims[n++] = MakeEmissiveSphere((Vector3){-2.5f, 0.3f, -0.5f}, 0.12f,
        (Color){60, 200, 255, 255}, (Vector3){0.15f, 0.7f, 1.0f}, 20.0f);

    // Subtle magenta — far right, high, rim-lights the gold sphere
    g.prims[n++] = MakeEmissiveSphere((Vector3){3.5f, 1.8f, -3.0f}, 0.15f,
        (Color){255, 60, 160, 255}, (Vector3){1.0f, 0.15f, 0.55f}, 14.0f);

    // === FOREGROUND DETAIL ===

    // Small glass bead — catches light in the foreground, adds depth
    g.prims[n++] = MakeGlassSphere((Vector3){0.7f, -0.38f, -0.4f}, 0.12f, (Color){255, 240, 230, 255}, 1.8f);

    // Tiny dark metal — foreground left, gives scale
    g.prims[n++] = MakeMetalSphere((Vector3){-0.5f, -0.4f, -0.2f}, 0.1f, (Color){40, 40, 45, 255}, 0.08f);

    // === METAL ROUGHNESS GRADIENT — subtle, in the background ===
    {
        Color metalColors[] = {
            {200, 170, 140, 255},  // warm silver
            {190, 165, 135, 255},
            {180, 155, 130, 255},
            {170, 145, 120, 255},
            {160, 135, 115, 255},
        };
        for (int i = 0; i < 5; i++) {
            float x = -2.0f + i * 1.0f;
            float rough = 0.02f + (float)i * 0.08f;
            g.prims[n++] = MakeMetalSphere((Vector3){x, -0.32f, -5.5f}, 0.18f, metalColors[i], rough);
        }
    }

    g.primCount = n;

    // === CINEMATIC 3-POINT LIGHTING ===
    g.lightCount = 3;

    // Key: warm directional from the right — golden hour angle
    g.lights[0] = (Light){ .type = 0, .direction = {0.5f, -0.4f, -0.6f},
        .color = {1.0f, 0.82f, 0.55f}, .intensity = 0.7f };

    // Fill: cool blue from left — subtle, just enough to open the shadows
    g.lights[1] = (Light){ .type = 1, .position = {-5.0f, 3.0f, 1.0f},
        .color = {0.25f, 0.35f, 0.7f}, .intensity = 0.8f, .radius = 1.2f };

    // Rim: warm backlight — separates subjects from background
    g.lights[2] = (Light){ .type = 1, .position = {0.5f, 3.5f, -8.0f},
        .color = {1.0f, 0.7f, 0.35f}, .intensity = 1.5f, .radius = 0.8f };

    // Camera: low angle, slightly off-center — hero shot
    g.cameraTarget = (Vector3){0.0f, 0.3f, -2.0f};
    g.cameraDistance = 5.5f;
    g.cameraAngleH = 0.18f;
    g.cameraAngleV = 0.12f;  // low angle — looking slightly up at the spheres
}

static void LoadCornellBoxScene(void) {
    int n = 0;
    Color white = {200, 200, 200, 255};
    Color red   = {180, 30, 30, 255};
    Color green = {30, 180, 30, 255};
    float S = 2.0f; // half-size

    // Back wall (white)
    g.prims[n++] = MakeLambertianQuad(
        (Vector3){-S, 0, -S*2}, (Vector3){S*2, 0, 0}, (Vector3){0, S*2, 0}, white);
    // Floor (white)
    g.prims[n++] = MakeLambertianQuad(
        (Vector3){-S, 0, -S*2}, (Vector3){S*2, 0, 0}, (Vector3){0, 0, S*2}, white);
    // Ceiling (white)
    g.prims[n++] = MakeLambertianQuad(
        (Vector3){-S, S*2, 0}, (Vector3){S*2, 0, 0}, (Vector3){0, 0, -S*2}, white);
    // Left wall (red)
    g.prims[n++] = MakeLambertianQuad(
        (Vector3){-S, 0, 0}, (Vector3){0, 0, -S*2}, (Vector3){0, S*2, 0}, red);
    // Right wall (green)
    g.prims[n++] = MakeLambertianQuad(
        (Vector3){S, 0, -S*2}, (Vector3){0, 0, S*2}, (Vector3){0, S*2, 0}, green);

    // Ceiling light (emissive quad)
    g.prims[n++] = MakeEmissiveQuad(
        (Vector3){-0.5f, S*2 - 0.01f, -S + 0.5f},
        (Vector3){1.0f, 0, 0}, (Vector3){0, 0, -1.0f},
        WHITE, (Vector3){1.0f, 0.95f, 0.85f}, 8.0f);

    // Tall box (white, 6 quads)
    n += AddBox(g.prims, n,
        (Vector3){0.4f, 0.0f, -3.0f}, (Vector3){1.4f, 2.6f, -2.0f},
        white, 0);

    // Short box (white, 6 quads)
    n += AddBox(g.prims, n,
        (Vector3){-1.4f, 0.0f, -2.0f}, (Vector3){-0.4f, 1.3f, -1.0f},
        white, 0);

    g.primCount = n;

    // Point light near ceiling for direct illumination
    g.lightCount = 1;
    g.lights[0] = (Light){ .type = 1, .position = {0.0f, S*2 - 0.2f, -S},
        .color = {1.0f, 0.95f, 0.85f}, .intensity = 2.0f, .radius = 0.5f };

    g.cameraTarget = (Vector3){0.0f, S, -S};
    g.cameraDistance = 6.0f;
    g.cameraAngleH = 0.0f;
    g.cameraAngleV = 0.15f;
}

// ============================================================
// Scene data packing
// ============================================================

static void PackSceneData(void) {
    memset(g.sceneDataBuf, 0, sizeof(g.sceneDataBuf));

    // Row stride = SCENE_TEX_WIDTH * 4 floats = 32 floats per row
    const int rowStride = SCENE_TEX_WIDTH * 4;

    for (int i = 0; i < g.primCount; i++) {
        float *row = &g.sceneDataBuf[i * rowStride];
        // Col 0: primType
        row[0] = (float)g.prims[i].primType;
        // Col 1: color.rgb, material
        row[4] = (float)g.prims[i].color.r / 255.0f;
        row[5] = (float)g.prims[i].color.g / 255.0f;
        row[6] = (float)g.prims[i].color.b / 255.0f;
        row[7] = (float)g.prims[i].material;
        // Col 2: emission.rgb, emStr
        row[8]  = g.prims[i].emission.x;
        row[9]  = g.prims[i].emission.y;
        row[10] = g.prims[i].emission.z;
        row[11] = g.prims[i].emissionStrength;
        // Col 3: ior, roughness, specular, shininess
        row[12] = g.prims[i].ior;
        row[13] = g.prims[i].roughness;
        row[14] = g.prims[i].specular;
        row[15] = g.prims[i].shininess;
        // Col 4-6: geometry (copy 12 floats = 3 vec4s)
        memcpy(&row[16], g.prims[i].geom, 12 * sizeof(float));

        // Col 7: bounding sphere [center.xyz, radius]
        float *bs = &row[28];
        int pt = g.prims[i].primType;
        float *gm = g.prims[i].geom;
        if (pt == PRIM_SPHERE) {
            bs[0] = gm[0]; bs[1] = gm[1]; bs[2] = gm[2]; bs[3] = gm[3];
        } else if (pt == PRIM_QUAD) {
            // center = Q + 0.5*(u+v), radius = 0.5 * max(|u+v|, |u-v|)
            float ux = gm[4], uy = gm[5], uz = gm[6];
            float vx = gm[8], vy = gm[9], vz = gm[10];
            bs[0] = gm[0] + 0.5f*(ux+vx);
            bs[1] = gm[1] + 0.5f*(uy+vy);
            bs[2] = gm[2] + 0.5f*(uz+vz);
            float d1x=ux+vx, d1y=uy+vy, d1z=uz+vz;
            float d2x=ux-vx, d2y=uy-vy, d2z=uz-vz;
            float len1 = sqrtf(d1x*d1x + d1y*d1y + d1z*d1z);
            float len2 = sqrtf(d2x*d2x + d2y*d2y + d2z*d2z);
            bs[3] = 0.5f * fmaxf(len1, len2);
        } else if (pt == PRIM_TRIANGLE) {
            float cx = (gm[0]+gm[4]+gm[8])/3.0f;
            float cy = (gm[1]+gm[5]+gm[9])/3.0f;
            float cz = (gm[2]+gm[6]+gm[10])/3.0f;
            float r = 0.0f;
            for (int k = 0; k < 3; k++) {
                float dx = gm[k*4]-cx, dy = gm[k*4+1]-cy, dz = gm[k*4+2]-cz;
                float d = sqrtf(dx*dx+dy*dy+dz*dz);
                if (d > r) r = d;
            }
            bs[0] = cx; bs[1] = cy; bs[2] = cz; bs[3] = r;
        }
    }

    // Lights: row LIGHT_ROW_BASE + j, cols 0-2
    for (int j = 0; j < g.lightCount; j++) {
        float *row = &g.sceneDataBuf[(LIGHT_ROW_BASE + j) * rowStride];
        // Col 0: type, dir.xyz
        row[0] = (float)g.lights[j].type;
        row[1] = g.lights[j].direction.x;
        row[2] = g.lights[j].direction.y;
        row[3] = g.lights[j].direction.z;
        // Col 1: pos.xyz, intensity
        row[4] = g.lights[j].position.x;
        row[5] = g.lights[j].position.y;
        row[6] = g.lights[j].position.z;
        row[7] = g.lights[j].intensity;
        // Col 2: color.rgb, radius
        row[8]  = g.lights[j].color.x;
        row[9]  = g.lights[j].color.y;
        row[10] = g.lights[j].color.z;
        row[11] = g.lights[j].radius;
    }
}

static void UploadSceneData(void) {
    PackSceneData();
    rlUpdateTexture(g.sceneDataTex.id, 0, 0, g.sceneDataTex.width,
                    g.sceneDataTex.height, RL_PIXELFORMAT_UNCOMPRESSED_R32G32B32A32,
                    g.sceneDataBuf);
}

static void OnSceneChanged(void) {
    g.frameCount = 0;
    UploadSceneData();
    if (g.locPrimCount != -1)
        SetShaderValue(g.shader, g.locPrimCount, &g.primCount, SHADER_UNIFORM_INT);
    if (g.locLightCount != -1)
        SetShaderValue(g.shader, g.locLightCount, &g.lightCount, SHADER_UNIFORM_INT);

    // Scan for emissive primitives and upload their indices
    int emissiveIndices[16] = {0};
    int emissiveCount = 0;
    for (int i = 0; i < g.primCount && emissiveCount < 16; i++) {
        if (g.prims[i].material == 2 && g.prims[i].emissionStrength > 0.0f) {
            emissiveIndices[emissiveCount++] = i;
        }
    }
    if (g.locEmissiveCount != -1)
        SetShaderValue(g.shader, g.locEmissiveCount, &emissiveCount, SHADER_UNIFORM_INT);
    if (g.locEmissiveIndices != -1)
        SetShaderValueV(g.shader, g.locEmissiveIndices, emissiveIndices, SHADER_UNIFORM_INT, emissiveCount > 0 ? emissiveCount : 1);
}

static void OnRenderSettingsChanged(void) {
    g.frameCount = 0;
    if (g.locAORadius != -1)
        SetShaderValue(g.shader, g.locAORadius, &g.aoRadius, SHADER_UNIFORM_FLOAT);
    if (g.locAOStrength != -1)
        SetShaderValue(g.shader, g.locAOStrength, &g.aoStrength, SHADER_UNIFORM_FLOAT);
    if (g.locDisplayToneMap != -1)
        SetShaderValue(g.displayShader, g.locDisplayToneMap, &g.toneMapMode, SHADER_UNIFORM_INT);
    if (g.locDisplayExposure != -1)
        SetShaderValue(g.displayShader, g.locDisplayExposure, &g.exposure, SHADER_UNIFORM_FLOAT);
    if (g.locSPP != -1)
        SetShaderValue(g.shader, g.locSPP, &g.samplesPerFrame, SHADER_UNIFORM_INT);
    if (g.locUseEnvMap != -1)
        SetShaderValue(g.shader, g.locUseEnvMap, &g.useEnvMap, SHADER_UNIFORM_INT);
    if (g.locEnvIntensity != -1)
        SetShaderValue(g.shader, g.locEnvIntensity, &g.envIntensity, SHADER_UNIFORM_FLOAT);
    if (g.locEnvRotation != -1)
        SetShaderValue(g.shader, g.locEnvRotation, &g.envRotation, SHADER_UNIFORM_FLOAT);
}

// Helper: get sphere center from geom for picking/dragging
static Vector3 GetPrimCenter(int i) {
    if (g.prims[i].primType == PRIM_SPHERE)
        return (Vector3){ g.prims[i].geom[0], g.prims[i].geom[1], g.prims[i].geom[2] };
    // For quads/tris: return center of first geometry vector
    return (Vector3){ g.prims[i].geom[0], g.prims[i].geom[1], g.prims[i].geom[2] };
}

static float GetPrimRadius(int i) {
    if (g.prims[i].primType == PRIM_SPHERE) return g.prims[i].geom[3];
    return 0.5f; // approximate for picking
}

// === Emscripten JS API ===
// Note: kept as "Sphere" names for backward compat with shell.html

#ifdef PLATFORM_WEB

EMSCRIPTEN_KEEPALIVE int GetSphereCount(void) { return g.primCount; }
EMSCRIPTEN_KEEPALIVE int GetSelectedSphere(void) { return g.selectedSphere; }
EMSCRIPTEN_KEEPALIVE int GetSphereColorR(int i) { return (i >= 0 && i < g.primCount) ? g.prims[i].color.r : 0; }
EMSCRIPTEN_KEEPALIVE int GetSphereColorG(int i) { return (i >= 0 && i < g.primCount) ? g.prims[i].color.g : 0; }
EMSCRIPTEN_KEEPALIVE int GetSphereColorB(int i) { return (i >= 0 && i < g.primCount) ? g.prims[i].color.b : 0; }
EMSCRIPTEN_KEEPALIVE int GetSphereMaterial(int i) { return (i >= 0 && i < g.primCount) ? g.prims[i].material : 0; }
EMSCRIPTEN_KEEPALIVE float GetSphereRadius(int i) { return (i >= 0 && i < g.primCount) ? GetPrimRadius(i) : 0; }
EMSCRIPTEN_KEEPALIVE float GetSphereEmissionR(int i) { return (i >= 0 && i < g.primCount) ? g.prims[i].emission.x : 0; }
EMSCRIPTEN_KEEPALIVE float GetSphereEmissionG(int i) { return (i >= 0 && i < g.primCount) ? g.prims[i].emission.y : 0; }
EMSCRIPTEN_KEEPALIVE float GetSphereEmissionB(int i) { return (i >= 0 && i < g.primCount) ? g.prims[i].emission.z : 0; }
EMSCRIPTEN_KEEPALIVE float GetSphereEmissionStrength(int i) { return (i >= 0 && i < g.primCount) ? g.prims[i].emissionStrength : 0; }
EMSCRIPTEN_KEEPALIVE float GetSphereIOR(int i) { return (i >= 0 && i < g.primCount) ? g.prims[i].ior : 1.5f; }
EMSCRIPTEN_KEEPALIVE float GetSphereRoughness(int i) { return (i >= 0 && i < g.primCount) ? g.prims[i].roughness : 0; }
EMSCRIPTEN_KEEPALIVE float GetSphereSpecular(int i) { return (i >= 0 && i < g.primCount) ? g.prims[i].specular : 0; }
EMSCRIPTEN_KEEPALIVE float GetSphereShininess(int i) { return (i >= 0 && i < g.primCount) ? g.prims[i].shininess : 32; }

EMSCRIPTEN_KEEPALIVE void SelectSphere(int i) {
    g.selectedSphere = (i >= 0 && i < g.primCount) ? i : -1;
}

EMSCRIPTEN_KEEPALIVE void SetSphereColor(int i, int r, int gr, int b) {
    if (i < 0 || i >= g.primCount) return;
    g.prims[i].color = (Color){ (unsigned char)r, (unsigned char)gr, (unsigned char)b, 255 };
    OnSceneChanged();
}

EMSCRIPTEN_KEEPALIVE void SetSphereMaterial(int i, int mat) {
    if (i < 0 || i >= g.primCount) return;
    g.prims[i].material = mat;
    OnSceneChanged();
}

EMSCRIPTEN_KEEPALIVE void SetSphereRadius(int i, float r) {
    if (i < 0 || i >= g.primCount) return;
    if (g.prims[i].primType == PRIM_SPHERE) g.prims[i].geom[3] = r;
    OnSceneChanged();
}

EMSCRIPTEN_KEEPALIVE void SetSphereEmission(int i, float r, float gr, float b) {
    if (i < 0 || i >= g.primCount) return;
    g.prims[i].emission = (Vector3){ r, gr, b };
    OnSceneChanged();
}

EMSCRIPTEN_KEEPALIVE void SetSphereEmissionStrength(int i, float val) {
    if (i < 0 || i >= g.primCount) return;
    g.prims[i].emissionStrength = val;
    OnSceneChanged();
}

EMSCRIPTEN_KEEPALIVE void SetSphereIOR(int i, float val) {
    if (i < 0 || i >= g.primCount) return;
    g.prims[i].ior = val;
    OnSceneChanged();
}

EMSCRIPTEN_KEEPALIVE void SetSphereRoughness(int i, float val) {
    if (i < 0 || i >= g.primCount) return;
    g.prims[i].roughness = val;
    OnSceneChanged();
}

EMSCRIPTEN_KEEPALIVE void SetSphereSpecular(int i, float val) {
    if (i < 0 || i >= g.primCount) return;
    g.prims[i].specular = val;
    OnSceneChanged();
}

EMSCRIPTEN_KEEPALIVE void SetSphereShininess(int i, float val) {
    if (i < 0 || i >= g.primCount) return;
    g.prims[i].shininess = val;
    OnSceneChanged();
}

EMSCRIPTEN_KEEPALIVE void AddSphere(void) {
    if (g.primCount >= MAX_PRIMS) return;
    g.prims[g.primCount] = MakeLambertianSphere(g.cameraTarget, 0.5f, GRAY);
    g.selectedSphere = g.primCount;
    g.primCount++;
    OnSceneChanged();
}

EMSCRIPTEN_KEEPALIVE void DeleteSelectedSphere(void) {
    if (g.selectedSphere < 0 || g.selectedSphere >= g.primCount) return;
    g.prims[g.selectedSphere] = g.prims[g.primCount - 1];
    memset(&g.prims[g.primCount - 1], 0, sizeof(Primitive));
    g.primCount--;
    g.selectedSphere = -1;
    OnSceneChanged();
}

// Light API
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

EMSCRIPTEN_KEEPALIVE void SetLightType(int i, int type) { if (i < 0 || i >= g.lightCount) return; g.lights[i].type = type; OnSceneChanged(); }
EMSCRIPTEN_KEEPALIVE void SetLightColor(int i, float r, float gr, float b) { if (i < 0 || i >= g.lightCount) return; g.lights[i].color = (Vector3){r,gr,b}; OnSceneChanged(); }
EMSCRIPTEN_KEEPALIVE void SetLightIntensity(int i, float val) { if (i < 0 || i >= g.lightCount) return; g.lights[i].intensity = val; OnSceneChanged(); }
EMSCRIPTEN_KEEPALIVE void SetLightDir(int i, float x, float y, float z) { if (i < 0 || i >= g.lightCount) return; g.lights[i].direction = (Vector3){x,y,z}; OnSceneChanged(); }
EMSCRIPTEN_KEEPALIVE void SetLightPos(int i, float x, float y, float z) { if (i < 0 || i >= g.lightCount) return; g.lights[i].position = (Vector3){x,y,z}; OnSceneChanged(); }
EMSCRIPTEN_KEEPALIVE void SetLightRadius(int i, float val) { if (i < 0 || i >= g.lightCount) return; g.lights[i].radius = val; OnSceneChanged(); }

EMSCRIPTEN_KEEPALIVE float GetAOStrength(void) { return g.aoStrength; }
EMSCRIPTEN_KEEPALIVE float GetAORadius(void) { return g.aoRadius; }
EMSCRIPTEN_KEEPALIVE int   GetToneMapMode(void) { return g.toneMapMode; }

EMSCRIPTEN_KEEPALIVE void SetAOStrength(float val) { g.aoStrength = val; OnRenderSettingsChanged(); }
EMSCRIPTEN_KEEPALIVE void SetAORadius(float val) { g.aoRadius = val; OnRenderSettingsChanged(); }
EMSCRIPTEN_KEEPALIVE void SetToneMapMode(int mode) { g.toneMapMode = mode; OnRenderSettingsChanged(); }
EMSCRIPTEN_KEEPALIVE float GetExposure(void) { return g.exposure; }
EMSCRIPTEN_KEEPALIVE void SetExposure(float val) { g.exposure = val; OnRenderSettingsChanged(); }
EMSCRIPTEN_KEEPALIVE int GetSPP(void) { return g.samplesPerFrame; }
EMSCRIPTEN_KEEPALIVE void SetSPP(int val) { g.samplesPerFrame = val > 0 ? val : 1; OnRenderSettingsChanged(); }
EMSCRIPTEN_KEEPALIVE int GetFPSValue(void) { return GetFPS(); }
EMSCRIPTEN_KEEPALIVE int GetUncapFPS(void) { return g.uncapFPS; }
EMSCRIPTEN_KEEPALIVE void SetUncapFPS(int val) {
    g.uncapFPS = val;
    SetTargetFPS(val ? 0 : 60);
}

EMSCRIPTEN_KEEPALIVE int GetEnvMode(void) { return g.useEnvMap; }
EMSCRIPTEN_KEEPALIVE float GetEnvIntensity(void) { return g.envIntensity; }
EMSCRIPTEN_KEEPALIVE float GetEnvRotation(void) { return g.envRotation; }
EMSCRIPTEN_KEEPALIVE void SetEnvMode(int mode) { g.useEnvMap = mode; OnRenderSettingsChanged(); }
EMSCRIPTEN_KEEPALIVE void SetEnvIntensity(float val) { g.envIntensity = val; OnRenderSettingsChanged(); }
EMSCRIPTEN_KEEPALIVE void SetEnvRotation(float val) { g.envRotation = val; OnRenderSettingsChanged(); }

EMSCRIPTEN_KEEPALIVE int GetCurrentScene(void) { return g.currentScene; }
EMSCRIPTEN_KEEPALIVE void SetScene(int scene) {
    g.selectedSphere = -1;
    g.currentScene = scene;
    memset(g.prims, 0, sizeof(g.prims));
    memset(g.lights, 0, sizeof(g.lights));
    if (scene == SCENE_CORNELL) {
        LoadCornellBoxScene();
        g.useEnvMap = 0; // gradient for enclosed scene
    } else {
        LoadDefaultScene();
        g.useEnvMap = 2; // procedural sky
    }
    OnSceneChanged();
    OnRenderSettingsChanged();
    UpdateCameraFromAngles();
}

#endif // PLATFORM_WEB

// Ray-sphere for mouse picking
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

static Shader LoadShaderWithVersion(const char *path) {
    char *fragCode = LoadFileText(path);
    if (!fragCode) { printf("ERROR: Could not load %s\n", path); return (Shader){0}; }
    int fragLen = (int)strlen(fragCode);
    char *fullFrag = (char *)RL_MALLOC(fragLen + 64);
#if defined(PLATFORM_WEB)
    sprintf(fullFrag, "#version 300 es\n%s", fragCode);
#else
    sprintf(fullFrag, "#version 330\n%s", fragCode);
#endif
    UnloadFileText(fragCode);
    Shader shader = LoadShaderFromMemory(NULL, fullFrag);
    RL_FREE(fullFrag);
    return shader;
}

static Texture2D CreateSceneDataTexture(void) {
    unsigned int texId = rlLoadTexture(NULL, SCENE_TEX_WIDTH, SCENE_TEX_HEIGHT,
                                       RL_PIXELFORMAT_UNCOMPRESSED_R32G32B32A32, 1);
    rlTextureParameters(texId, RL_TEXTURE_MAG_FILTER, RL_TEXTURE_FILTER_NEAREST);
    rlTextureParameters(texId, RL_TEXTURE_MIN_FILTER, RL_TEXTURE_FILTER_NEAREST);
    rlTextureParameters(texId, RL_TEXTURE_WRAP_S, RL_TEXTURE_WRAP_CLAMP);
    rlTextureParameters(texId, RL_TEXTURE_WRAP_T, RL_TEXTURE_WRAP_CLAMP);
    return (Texture2D){ .id = texId, .width = SCENE_TEX_WIDTH, .height = SCENE_TEX_HEIGHT,
                        .format = PIXELFORMAT_UNCOMPRESSED_R32G32B32A32, .mipmaps = 1 };
}

static void InitApp(void) {
    InitWindow(SCREEN_WIDTH, SCREEN_HEIGHT, "Raytracer — Full Lighting Reference");
    SetTargetFPS(60);

    g.camera = (Camera3D){0};
    g.camera.up = (Vector3){0.0f, 1.0f, 0.0f};
    g.camera.fovy = 45.0f;
    g.camera.projection = CAMERA_PERSPECTIVE;

    g.selectedSphere = -1;
    g.isDragging = false;
    g.aoRadius = 0.5f;
    g.aoStrength = 0.5f;
    g.toneMapMode = 3; // AgX by default
    g.exposure = 0.0f;
    g.samplesPerFrame = 16;
    g.uncapFPS = 0;
    g.useEnvMap = 0;       // gradient by default
    g.envIntensity = 1.0f;
    g.envRotation = 0.0f;

    // Load default scene
    g.currentScene = SCENE_DEFAULT;
    g.useEnvMap = 2; // procedural sky
    LoadDefaultScene();
    UpdateCameraFromAngles();

    // Load shaders
    g.shader = LoadShaderWithVersion("shaders/raytrace.glsl");
    g.displayShader = LoadShaderWithVersion("shaders/display.glsl");

    // Raytrace shader locations
    g.locTime = GetShaderLocation(g.shader, "time");
    g.locPrimCount = GetShaderLocation(g.shader, "primCount");
    g.locLightCount = GetShaderLocation(g.shader, "lightCount");
    g.camPosLoc = GetShaderLocation(g.shader, "cameraPosition");
    g.invVpLoc = GetShaderLocation(g.shader, "invViewProj");
    g.locKLinear = GetShaderLocation(g.shader, "k_linear");
    g.locKQuadratic = GetShaderLocation(g.shader, "k_quadratic");
    g.locAORadius = GetShaderLocation(g.shader, "aoRadius");
    g.locAOStrength = GetShaderLocation(g.shader, "aoStrength");
    g.locFrameCount = GetShaderLocation(g.shader, "frameCount");
    g.locAccumTexture = GetShaderLocation(g.shader, "accumTexture");
    g.locResolution = GetShaderLocation(g.shader, "resolution");
    g.locSceneData = GetShaderLocation(g.shader, "sceneData");
    g.locEmissiveCount = GetShaderLocation(g.shader, "emissiveCount");
    g.locEmissiveIndices = GetShaderLocation(g.shader, "emissiveIndices");
    g.locSPP = GetShaderLocation(g.shader, "samplesPerFrame");
    g.locEnvMap = GetShaderLocation(g.shader, "envMap");
    g.locUseEnvMap = GetShaderLocation(g.shader, "useEnvMap");
    g.locEnvIntensity = GetShaderLocation(g.shader, "envIntensity");
    g.locEnvRotation = GetShaderLocation(g.shader, "envRotation");

    // Display shader locations
    g.locDisplayToneMap = GetShaderLocation(g.displayShader, "toneMapMode");
    g.locDisplayExposure = GetShaderLocation(g.displayShader, "exposure");

    // Set static uniforms
    float kLinear = 0.09f, kQuadratic = 0.032f;
    if (g.locKLinear != -1) SetShaderValue(g.shader, g.locKLinear, &kLinear, SHADER_UNIFORM_FLOAT);
    if (g.locKQuadratic != -1) SetShaderValue(g.shader, g.locKQuadratic, &kQuadratic, SHADER_UNIFORM_FLOAT);
    float res[2] = {(float)SCREEN_WIDTH, (float)SCREEN_HEIGHT};
    if (g.locResolution != -1) SetShaderValue(g.shader, g.locResolution, res, SHADER_UNIFORM_VEC2);

    // Create scene data texture
    g.sceneDataTex = CreateSceneDataTexture();
    OnSceneChanged();
    OnRenderSettingsChanged();

    g.targetTexture = LoadRenderTexture(SCREEN_WIDTH, SCREEN_HEIGHT);

    // RGBA16F accumulation textures
    for (int i = 0; i < 2; i++) {
        g.accumTexture[i] = LoadRenderTexture(SCREEN_WIDTH, SCREEN_HEIGHT);
        unsigned int prevId = g.accumTexture[i].texture.id;
        unsigned int newTexId = rlLoadTexture(NULL, SCREEN_WIDTH, SCREEN_HEIGHT,
                                              RL_PIXELFORMAT_UNCOMPRESSED_R16G16B16A16, 1);
        rlTextureParameters(newTexId, RL_TEXTURE_MAG_FILTER, RL_TEXTURE_FILTER_BILINEAR);
        rlTextureParameters(newTexId, RL_TEXTURE_MIN_FILTER, RL_TEXTURE_FILTER_BILINEAR);
        rlTextureParameters(newTexId, RL_TEXTURE_WRAP_S, RL_TEXTURE_WRAP_CLAMP);
        rlTextureParameters(newTexId, RL_TEXTURE_WRAP_T, RL_TEXTURE_WRAP_CLAMP);
        rlFramebufferAttach(g.accumTexture[i].id, newTexId, RL_ATTACHMENT_COLOR_CHANNEL0,
                            RL_ATTACHMENT_TEXTURE2D, 0);
        rlUnloadTexture(prevId);
        g.accumTexture[i].texture.id = newTexId;
        g.accumTexture[i].texture.format = PIXELFORMAT_UNCOMPRESSED_R16G16B16A16;
    }

    g.accumIndex = 0;
    g.frameCount = 0;
    g.prevCamPos = g.camera.position;
}

static void UpdateDrawFrame(void) {
    // Camera orbit
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

    // Picking (only spheres for now)
    if (IsMouseButtonPressed(MOUSE_BUTTON_LEFT)) {
        Vector2 mouse = GetMousePosition();
        float nx = (2.0f * mouse.x / SCREEN_WIDTH) - 1.0f;
        float ny = 1.0f - (2.0f * mouse.y / SCREEN_HEIGHT);
        Matrix view = GetCameraMatrix(g.camera);
        float aspect = (float)SCREEN_WIDTH / (float)SCREEN_HEIGHT;
        Matrix proj = MatrixPerspective(g.camera.fovy * DEG2RAD, aspect, 0.1f, 100.0f);
        Matrix invVP = MatrixInvert(MatrixMultiply(view, proj));
        Vector4 nc = {nx, ny, -1.0f, 1.0f};
        Vector4 wn = {
            invVP.m0*nc.x + invVP.m4*nc.y + invVP.m8*nc.z + invVP.m12*nc.w,
            invVP.m1*nc.x + invVP.m5*nc.y + invVP.m9*nc.z + invVP.m13*nc.w,
            invVP.m2*nc.x + invVP.m6*nc.y + invVP.m10*nc.z + invVP.m14*nc.w,
            invVP.m3*nc.x + invVP.m7*nc.y + invVP.m11*nc.z + invVP.m15*nc.w,
        };
        Vector3 wp = {wn.x/wn.w, wn.y/wn.w, wn.z/wn.w};
        Vector3 rayDir = Vector3Normalize(Vector3Subtract(wp, g.camera.position));

        float closestT = 1e38f;
        int closestIdx = -1;
        for (int i = 0; i < g.primCount; i++) {
            if (g.prims[i].primType != PRIM_SPHERE) continue;
            Vector3 c = GetPrimCenter(i);
            float r = GetPrimRadius(i);
            float t = RaySphereIntersect(g.camera.position, rayDir, c, r);
            if (t > 0.0f && t < closestT) { closestT = t; closestIdx = i; }
        }
        g.selectedSphere = closestIdx;
        g.isDragging = (closestIdx != -1);
    }

    if (IsMouseButtonReleased(MOUSE_BUTTON_LEFT)) g.isDragging = false;

    if (g.isDragging && g.selectedSphere >= 0 && IsMouseButtonDown(MOUSE_BUTTON_LEFT)) {
        Vector2 delta = GetMouseDelta();
        if (delta.x != 0.0f || delta.y != 0.0f) {
            Vector3 forward = Vector3Normalize(Vector3Subtract(g.camera.target, g.camera.position));
            Vector3 right = Vector3Normalize(Vector3CrossProduct(forward, g.camera.up));
            Vector3 up = Vector3CrossProduct(right, forward);
            float mf = g.cameraDistance * 0.003f;
            // Only drag spheres
            if (g.prims[g.selectedSphere].primType == PRIM_SPHERE) {
                g.prims[g.selectedSphere].geom[0] += right.x * delta.x * mf + up.x * (-delta.y) * mf;
                g.prims[g.selectedSphere].geom[1] += right.y * delta.x * mf + up.y * (-delta.y) * mf;
                g.prims[g.selectedSphere].geom[2] += right.z * delta.x * mf + up.z * (-delta.y) * mf;
            }
            OnSceneChanged();
        }
    }

    // Camera change detection
    if (g.camera.position.x != g.prevCamPos.x ||
        g.camera.position.y != g.prevCamPos.y ||
        g.camera.position.z != g.prevCamPos.z) {
        g.frameCount = 0;
        g.prevCamPos = g.camera.position;
    }

    g.frameCount++;
    if (g.locFrameCount != -1)
        SetShaderValue(g.shader, g.locFrameCount, &g.frameCount, SHADER_UNIFORM_INT);
    float t = (float)GetTime();
    if (g.locTime != -1) SetShaderValue(g.shader, g.locTime, &t, SHADER_UNIFORM_FLOAT);

    // Rasterize (canvas for shader)
    BeginTextureMode(g.targetTexture);
        ClearBackground(LIGHTGRAY);
        BeginMode3D(g.camera);
            for (int i = 0; i < g.primCount; i++) {
                if (g.prims[i].primType == PRIM_SPHERE) {
                    Vector3 c = GetPrimCenter(i);
                    DrawSphere(c, GetPrimRadius(i), g.prims[i].color);
                }
            }
            if (g.selectedSphere >= 0 && g.selectedSphere < g.primCount &&
                g.prims[g.selectedSphere].primType == PRIM_SPHERE) {
                Vector3 c = GetPrimCenter(g.selectedSphere);
                DrawSphereWires(c, GetPrimRadius(g.selectedSphere) + 0.02f, 8, 8, YELLOW);
            }
            DrawGrid(10, 1.0f);
        EndMode3D();
    EndTextureMode();

    // Camera uniforms
    Matrix view = GetCameraMatrix(g.camera);
    float aspect = (float)SCREEN_WIDTH / (float)SCREEN_HEIGHT;
    Matrix proj = MatrixPerspective(g.camera.fovy * DEG2RAD, aspect, 0.1f, 100.0f);
    Matrix invViewProj = MatrixInvert(MatrixMultiply(view, proj));
    if (g.camPosLoc != -1) SetShaderValue(g.shader, g.camPosLoc, &g.camera.position, SHADER_UNIFORM_VEC3);
    if (g.invVpLoc != -1) SetShaderValueMatrix(g.shader, g.invVpLoc, invViewProj);

    // Raytrace pass
    int readIdx = g.accumIndex;
    int writeIdx = 1 - g.accumIndex;
    BeginTextureMode(g.accumTexture[writeIdx]);
        BeginShaderMode(g.shader);
            if (g.locSceneData != -1) SetShaderValueTexture(g.shader, g.locSceneData, g.sceneDataTex);
            if (g.locEnvMap != -1 && g.envMapTex.id > 0)
                SetShaderValueTexture(g.shader, g.locEnvMap, g.envMapTex);
            if (g.locAccumTexture != -1)
                SetShaderValueTexture(g.shader, g.locAccumTexture, g.accumTexture[readIdx].texture);
            DrawTextureRec(g.targetTexture.texture,
                (Rectangle){0, 0, (float)g.targetTexture.texture.width, (float)-g.targetTexture.texture.height},
                (Vector2){0, 0}, WHITE);
        EndShaderMode();
    EndTextureMode();
    g.accumIndex = writeIdx;

    // Display pass
    BeginDrawing();
        ClearBackground(BLACK);
        BeginShaderMode(g.displayShader);
            DrawTextureRec(g.accumTexture[g.accumIndex].texture,
                (Rectangle){0, 0, (float)g.accumTexture[g.accumIndex].texture.width,
                             (float)-g.accumTexture[g.accumIndex].texture.height},
                (Vector2){0, 0}, WHITE);
        EndShaderMode();
        DrawFPS(10, 10);
    EndDrawing();
}

int main(void) {
    InitApp();
#if defined(PLATFORM_WEB)
    emscripten_set_main_loop(UpdateDrawFrame, 0, 1);
#else
    while (!WindowShouldClose()) UpdateDrawFrame();
    if (g.shader.id != 0) UnloadShader(g.shader);
    if (g.displayShader.id != 0) UnloadShader(g.displayShader);
    UnloadRenderTexture(g.targetTexture);
    UnloadRenderTexture(g.accumTexture[0]);
    UnloadRenderTexture(g.accumTexture[1]);
    rlUnloadTexture(g.sceneDataTex.id);
    CloseWindow();
#endif
    return 0;
}
