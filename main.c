#include "raylib.h"
#include "raymath.h" // Required for matrix functions
#include <stdio.h>   // For printf (used for error messages)
#include <stdlib.h>  // For exit (in case of fatal errors)

// Shader path (make sure this file exists in this relative path or provide an
// absolute path)
const char *FRAGMENT_SHADER_PATH = "shaders/distance.glsl";

// Helper function to convert Color to a Vector3 (normalized float values)
Vector3 ColorToVec3(Color c) {
  return (Vector3){(float)c.r / 255.0f, (float)c.g / 255.0f,
                   (float)c.b / 255.0f};
}

int main(void) {
  // Constants for screen dimensions
  const int SCREEN_WIDTH = 800;
  const int SCREEN_HEIGHT = 600;

  // Initialize Raylib and the window
  InitWindow(SCREEN_WIDTH, SCREEN_HEIGHT, "Raylib C - Funky Inverted Spheres");

  // Set target FPS
  SetTargetFPS(60);

  // Define the camera
  Camera3D camera = {0};
  camera.position = (Vector3){0.0f, 2.0f, 4.0f}; // Camera position (eye)
  camera.target = (Vector3){0.0f, 0.0f, 0.0f};    // Camera target (center)
  camera.up = (Vector3){0.0f, 1.0f, 0.0f};        // Camera up vector (rotation)
  camera.fovy = 45.0f;                            // Camera field-of-view Y
  camera.projection = CAMERA_PERSPECTIVE;         // Camera mode

  // Define sphere properties
  Vector3 sphere1Pos = {0.0f, 0.0f, -1.0f};
  float sphere1Radius = 0.5f;
  Color sphere1Color = DARKGREEN;

  Vector3 sphere2Pos = {0.0f, -100.5f, -1.0f};
  float sphere2Radius = 100.0f;
  Color sphere2Color = DARKPURPLE;

  Vector3 sphere3Pos = {2.0f, 0.5f, 5.0f};
  float sphere3Radius = 0.8f;
  Color sphere3Color = DARKBROWN;

  // Load the fragment shader
  // Raylib's LoadShader will print a warning if FRAGMENT_SHADER_PATH is not
  // found and will return a default shader in that case.
  Shader shader = LoadShader(0, FRAGMENT_SHADER_PATH);

  if (shader.id == 0) {
    // This would mean a more fundamental issue with shader loading,
    // beyond just not finding the file (as LoadShader usually returns a default
    // shader).
    printf("WARN: Shader ID is 0 after LoadShader. This is unexpected and "
           "might indicate a severe issue.\n");
    // The program will continue, but BeginShaderMode might not work as
    // expected.
  } else {
    printf("INFO: Shader loaded. ID: %u. Check console for Raylib warnings if "
           "'%s' was not found.\n",
           shader.id, FRAGMENT_SHADER_PATH);
  }

  // Get shader locations
  int locTime = GetShaderLocation(shader, "time");
  int locRadii = GetShaderLocation(shader, "sphereRadii");
  int locLocii = GetShaderLocation(shader, "sphereLocii");
  int locColors = GetShaderLocation(shader, "sphereColors");
  int camPosLoc = GetShaderLocation(shader, "cameraPosition");
  int invVpLoc = GetShaderLocation(shader, "invViewProj");

  // Set shader uniform values
  // 1. Radii
  float radii[3] = {sphere1Radius, sphere2Radius, sphere3Radius};
  // The third argument to SetShaderValueV is the value pointer,
  // the fourth is the uniform type, and the fifth is the number of elements of
  // that type. If sphereRadii is "float sphereRadii[3];" in GLSL, this is fine.
  // If it's "vec3 sphereRadii;" or similar, this needs adjustment. Assuming
  // float[3] for now. For sending 3 floats:
  if (locRadii != -1)
    SetShaderValueV(shader, locRadii, radii, SHADER_UNIFORM_FLOAT, 3);

  // 3. Colors
  Vector3 sphere1ColorVec = ColorToVec3(sphere1Color);
  Vector3 sphere2ColorVec = ColorToVec3(sphere2Color);
  Vector3 sphere3ColorVec = ColorToVec3(sphere3Color);
  float colors[9] = {
      sphere1ColorVec.x, sphere1ColorVec.y, sphere1ColorVec.z,
      sphere2ColorVec.x, sphere2ColorVec.y, sphere2ColorVec.z,
      sphere3ColorVec.x, sphere3ColorVec.y, sphere3ColorVec.z,
  };
  // If "sphereColors" is "vec3 sphereColors[3];" in GLSL:
  if (locColors != -1)
    SetShaderValueV(shader, locColors, colors, SHADER_UNIFORM_VEC3, 3);
  // If "sphereColors" is "float sphereColors[9];" in GLSL:
  // if (locColors != -1) SetShaderValueV(shader, locColors, colors,
  // SHADER_UNIFORM_FLOAT, 9);

  // Set the time uniform to current time (or 0.0f for static effect)
  float time = (float)GetTime(); // Get current time in seconds
  if (locTime != -1) {
    SetShaderValue(shader, locTime, &time, SHADER_UNIFORM_FLOAT);
  } else {
    printf("WARN: Shader location for 'time' is -1, uniform not set.\n");
  }


  // Create a render texture to draw the 3D scene into.
  RenderTexture2D targetTexture =
      LoadRenderTexture(SCREEN_WIDTH, SCREEN_HEIGHT);
  if (targetTexture.id == 0) {
    printf("FATAL: Failed to create render texture. FBO ID is 0.\n");
    if (shader.id != 0)
      UnloadShader(shader); // Clean up loaded shader before exiting
    CloseWindow();
    exit(EXIT_FAILURE);
  }

  // Main game loop
  while (!WindowShouldClose()) {
    // --- Update ---
    UpdateCamera(&camera, CAMERA_ORBITAL); // Example camera control

    // --- Draw 3D scene to Render Texture ---
    BeginTextureMode(targetTexture);
    ClearBackground(LIGHTGRAY); // Clear the texture's background

    BeginMode3D(camera);
    DrawSphere(sphere1Pos, sphere1Radius, sphere1Color);
    DrawSphere(sphere2Pos, sphere2Radius, sphere2Color);
    DrawSphere(sphere3Pos, sphere3Radius, sphere3Color);
    DrawGrid(10, 1.0f);
    EndMode3D();
    EndTextureMode();

    // --- Draw Render Texture to Screen with Shader ---
    BeginDrawing();
    ClearBackground(BLACK); // Clear the main window background

    // Attempt to use the shader if its ID is not 0.
    // If FRAGMENT_SHADER_PATH failed to load, Raylib's LoadShader would have
    // returned a default shader (with a non-zero ID), and printed a warning.
    // In that case, BeginShaderMode will use the default shader, and the custom
    // effect won't apply.
    // 2. Centers (locii)
    float locii[9] = {
        sphere1Pos.x, sphere1Pos.y, sphere1Pos.z, sphere2Pos.x, sphere2Pos.y,
        sphere2Pos.z, sphere3Pos.x, sphere3Pos.y, sphere3Pos.z,
    };
    // If "sphereLocii" is "vec3 sphereLocii[3];" in GLSL:
    if (locLocii != -1)
      SetShaderValueV(shader, locLocii, locii, SHADER_UNIFORM_VEC3, 3);
    // Calculate view and projection matrices
    Matrix view = GetCameraMatrix(camera);
    float aspect = (float)SCREEN_WIDTH / (float)SCREEN_HEIGHT;
    Matrix proj =
        MatrixPerspective(camera.fovy * DEG2RAD, aspect, 0.1f, 100.0f);
    Matrix viewProj = MatrixMultiply(view, proj);
    Matrix invViewProj = MatrixInvert(viewProj);
    // Set camera position and inverse view-projection matrix
    if (camPosLoc != -1)
      SetShaderValue(shader, camPosLoc, &camera.position, SHADER_UNIFORM_VEC3);
    if (invVpLoc != -1)
      SetShaderValueMatrix(shader, invVpLoc, invViewProj);
    // If "sphereLocii" is "float sphereLocii[9];" in GLSL:
    // if (locLocii != -1) SetShaderValueV(shader, locLocii, locii,
    // SHADER_UNIFORM_FLOAT, 9);
    if (shader.id != 0) {
      BeginShaderMode(shader);
      // Draw the render texture covering the whole screen.
      // RenderTexture textures are flipped vertically by default in OpenGL.
      // Draw with a negative height in the source rectangle to correct this.
      DrawTextureRec(
          targetTexture.texture,
          (Rectangle){0, 0, (float)targetTexture.texture.width,
                      (float)-targetTexture.texture
                          .height}, // Source rect, negative height to flip
          (Vector2){0, 0},          // Position on screen
          WHITE                     // Tint (white = no change)
      );
      EndShaderMode();
    } else {
      // This block would execute if shader.id was 0, indicating a more severe
      // loading failure.
      DrawTextureRec(targetTexture.texture,
                     (Rectangle){0, 0, (float)targetTexture.texture.width,
                                 (float)-targetTexture.texture.height},
                     (Vector2){0, 0}, WHITE);
      DrawText("ERROR: Shader ID is 0, cannot apply shader.", 10, 70, 10, RED);
    }

    DrawFPS(10, 10);
    DrawText("My awesome ray tracing shader (C Version)", 10, 40, 20, LIME);
    EndDrawing();
  }

  // Unload resources
  if (shader.id != 0)
    UnloadShader(shader); // Unload shader only if it was potentially loaded
  UnloadRenderTexture(targetTexture);

  // Close window and OpenGL context
  CloseWindow();

  return 0;
}
