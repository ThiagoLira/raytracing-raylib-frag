// ============================================================
// Lesson 3: Random Numbers on the GPU
// ============================================================
//
// CPUs have rand() or mt19937. GPUs have nothing built-in.
// We need to BUILD our own random number generator.
//
// The trick: use a HASH FUNCTION that scrambles integers.
// Feed it (pixel_x, pixel_y, frame_number) and get back
// a different-looking number for every pixel, every frame.
//
// This lesson implements PCG (Permuted Congruential Generator),
// the same RNG used in the full raytracer.
//
// Modes:
//   1 — Raw noise: PCG hash output as grayscale
//   2 — Animated noise: changes every frame (time-varying seed)
//   3 — Random unit vectors shown as RGB colors

#ifdef GL_ES
precision highp float;
#endif

in vec2 fragTexCoord;
out vec4 finalColor;

uniform sampler2D texture0;
uniform vec2  resolution;
uniform int   mode;       // 0=static, 1=animated, 2=vectors
uniform int   frameCount;

// ============================================================
// PCG Hash — the heart of our GPU random number generator
// ============================================================
//
// PCG works by:
//   1. Multiply by a large prime (spreads bits)
//   2. XOR-shift (mixes high bits into low bits)
//   3. Multiply again (more spreading)
//   4. Final XOR-shift (removes remaining patterns)
//
// Input: any uint (our "seed")
// Output: a pseudorandom uint (looks random, but deterministic)
//
// CRITICAL PROPERTY: same input always gives same output.
// This is what makes it a HASH, not true randomness.
// For rendering, deterministic = good (reproducible results).

uint rngState;  // global state, updated after each call

uint pcgHash(uint v) {
    uint state = v * 747796405u + 2891336453u;   // LCG step
    uint word = ((state >> ((state >> 28u) + 4u)) ^ state) * 277803737u;
    return (word >> 22u) ^ word;                  // output permutation
}

// Convert the hash output to a float in [0, 1)
float randomFloat() {
    rngState = pcgHash(rngState);
    return float(rngState) / 4294967295.0;  // divide by max uint
}

// Random 3D vector with each component in [0, 1)
vec3 randomVec3() {
    return vec3(randomFloat(), randomFloat(), randomFloat());
}

// Random point on the unit sphere (rejection sampling)
// Keep generating random points in [-1,1]^3 until one
// falls inside the unit sphere, then normalize it.
vec3 randomUnitVec3() {
    vec3 v = vec3(
        randomFloat() * 2.0 - 1.0,
        randomFloat() * 2.0 - 1.0,
        randomFloat() * 2.0 - 1.0
    );
    float lenSq = dot(v, v);
    if (lenSq < 0.0001) return vec3(1, 0, 0); // avoid zero vector
    return v / sqrt(lenSq);
}

// ============================================================
// Color palette — maps [0,1] to a pleasant gradient
// ============================================================
vec3 palette(float t) {
    // Warm-to-cool gradient: amber → coral → violet → blue
    vec3 a = vec3(0.5, 0.5, 0.5);
    vec3 b = vec3(0.5, 0.5, 0.5);
    vec3 c = vec3(1.0, 1.0, 1.0);
    vec3 d = vec3(0.00, 0.33, 0.67);
    return a + b * cos(6.28318 * (c * t + d));
}

// ============================================================
// Main
// ============================================================
void main() {
    uvec2 px = uvec2(gl_FragCoord.xy);
    vec3 color;

    if (mode == 0) {
        // ── MODE 0: Static noise ──
        // Seed from pixel coordinates only.
        // Same pixel = same value every frame (deterministic!).
        rngState = px.x * 1973u + px.y * 9277u;
        randomFloat(); // warm up (first output can be correlated with seed)

        float r = randomFloat();
        color = palette(r);

    } else if (mode == 1) {
        // ── MODE 1: Animated noise ──
        // Add frameCount to the seed → different value each frame.
        // This is how the raytracer gets different random rays per frame.
        rngState = px.x * 1973u + px.y * 9277u + uint(frameCount) * 26699u;
        randomFloat();

        float r = randomFloat();
        color = palette(r);

    } else {
        // ── MODE 2: Random unit vectors as colors ──
        // Each pixel generates a random direction on the unit sphere.
        // We map (x,y,z) → (r,g,b) by remapping [-1,1] → [0,1].
        // You should see a smooth, colorful noise pattern.
        rngState = px.x * 1973u + px.y * 9277u + uint(frameCount) * 26699u;
        randomFloat();

        vec3 v = randomUnitVec3();
        color = v * 0.5 + 0.5; // remap [-1,1] to [0,1] for display
    }

    // No gamma needed — we're showing raw data values
    finalColor = vec4(color, 1.0);
}
