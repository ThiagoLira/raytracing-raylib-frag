// distance_darkener.fs
#version 330 core

// Texture coordinates passed from Raylib’s default post-process vertex shader
in vec2 fragTexCoord;

// Full-screen colour buffer from the first render pass
uniform sampler2D texture0;

uniform vec3 cameraPosition;
uniform mat4 invViewProj;

// Number of spheres in the scene
uniform int sphereCount;

struct Sphere {
    vec3 center;
    float radius;
    vec3 color;
    int material; // 0 = lambertian, 1 = metal, 2=glass
};

// hardcoded for all glass surfaces now
float REFRACTION_INDEX = 1.33;

// Array of spheres
uniform Sphere spheres[10];

// time is used to generate random numbers like a seed
uniform float time;
float seed = gl_FragCoord.x * 0.123 + gl_FragCoord.y * 0.456 + time;

// Output colour
// will be written to the default framebuffer
out vec4 fragColor;

// STRUCTS

struct Ray
{
    vec3 origin;
    vec3 direction;
    // ray is at origin + t*dir
    // int t;
};
struct HitRecord
{
    float t;
    vec3 hitPoint;
    vec3 normal;
    bool isHit;
};
struct DirectionalLight
{
    vec3 direction; // Direction of the light
    vec3 color; // Color of the light
    float intensity; // Intensity of the light
};
// LIGHTS
DirectionalLight dirlight1 = DirectionalLight(vec3(0.0, 0.0, -1.0), vec3(0.6, 0.05, 0.05), 0.9);

// FUNCTIONS

float randomDouble(inout float currentSeed)
{
    // Update the seed and generate a random number in the range [0, 1)
    currentSeed = fract(sin(currentSeed * 12.9898) * 43758.5453);
    return currentSeed; // Return the generated random number
}

vec3 randomVec3(inout float currentSeed)
{
    // Generate a random vector with components in the range [0, 1)
    float rX = randomDouble(currentSeed); // seed is updated
    float rY = randomDouble(currentSeed); // seed is updated again
    float rZ = randomDouble(currentSeed); // seed is updated again
    return vec3(rX, rY, rZ);
}

vec3 randomVec3(in float minVal, in float maxVal, inout float currentSeed)
{
    // Generate a random vector with components in the range [0, 1) first
    float rX = randomDouble(currentSeed);
    float rY = randomDouble(currentSeed);
    float rZ = randomDouble(currentSeed);

    // Scale to the range [minVal, maxVal)
    return mix(vec3(minVal), vec3(maxVal), vec3(rX, rY, rZ));
}
vec3 randomUnitVec3(inout float currentSeed)
{
    // Generate random components in the range [-1, 1)
    float rX = randomDouble(currentSeed) * 2.0 - 1.0;
    float rY = randomDouble(currentSeed) * 2.0 - 1.0;
    float rZ = randomDouble(currentSeed) * 2.0 - 1.0;

    vec3 v = vec3(rX, rY, rZ);
    float lenSq = dot(v, v);

    // Handle the unlikely case of a zero vector
    if (lenSq == 0.0) {
        return vec3(1.0, 0.0, 0.0); // Return an arbitrary unit vector
    }
    return v / sqrt(lenSq); // Normalize the vector
}

vec3 randomOnHemisphere(in vec3 normal, inout float currentSeed)
{
    // Generate a random unit vector (distributed over the whole sphere)
    vec3 unitVec = randomUnitVec3(currentSeed); // Uses the improved randomUnitVec3 above

    // Ensure it's on the same hemisphere as the normal
    if (dot(unitVec, normal) < 0.0) {
        unitVec = -unitVec;
    }
    return unitVec;
}

vec3 clampColor(vec3 color) {
    // Clamp the color values to the range [0, 1]
    return vec3(clamp(color.r, 0.0, 1.0), clamp(color.g, 0.0, 1.0), clamp(color.b, 0.0, 1.0));
}

void intersectSphere(in Ray r, in vec3 sphereCenter, in float sphereRadius, inout HitRecord hitRecord)
{
    if (hitRecord.isHit) return; // already hit something nearer

    vec3 O = r.origin;
    vec3 D = r.direction;
    vec3 oc = O - sphereCenter; // vector from sphere centre to ray origin

    // Quadratic coefficients for |O + tD − C|² = r²
    float a = dot(D, D); // = 1 if D is normalised
    float b = dot(D, oc); // half of the usual 2b term
    float c = dot(oc, oc) - sphereRadius * sphereRadius;

    float discriminant = b * b - c; // (½-b form for numerical stability)
    if (discriminant < 0.0) return; // ray misses the sphere

    float t = (-b - sqrt(discriminant)); // nearest intersection
    if (t > 0.0) { // only count hits in front of the camera
        hitRecord.isHit = true;
        hitRecord.t = t;
        // is it O + tD or tD?
        hitRecord.hitPoint = r.origin + t * D; // calculate the hit point

        vec3 nNormal = normalize(hitRecord.hitPoint - sphereCenter);
        hitRecord.normal = nNormal; // calculate the normal at the hit point
    }
}


vec3 colorRayIterative(in Ray initialRay, out vec3 outColor, in int maxDepth) {
    outColor = vec3(0.0, 0.0, 0.0);
    vec3 accumulatedColor = vec3(1.0, 1.0, 1.0); // Start with full contribution
    Ray currentRay = initialRay;

    for (int depth = 0; depth < maxDepth; depth++) {
        HitRecord closestHitRecord = HitRecord(0, vec3(0.0), vec3(0.0), false);
        closestHitRecord.t = 1e38; // A very large number (effectively infinity)
        int hitSphereIndex = -1;

        // Find the closest intersection among all spheres
        for (int s = 0; s < sphereCount; s++) {
            HitRecord currentSphereHitRecord = HitRecord(0, vec3(0.0), vec3(0.0), false);
            intersectSphere(currentRay, spheres[s].center, spheres[s].radius, currentSphereHitRecord);
            if (currentSphereHitRecord.isHit && currentSphereHitRecord.t < closestHitRecord.t) {
                closestHitRecord = currentSphereHitRecord;
                hitSphereIndex = s;
            }
        }

        if (hitSphereIndex != -1) { // If we hit a sphere

            bool isFrontFace = dot(currentRay.direction, closestHitRecord.normal) > 0.0;

            // Simulate diffuse lighting
            //switch case for material type
            if (spheres[hitSphereIndex].material == 1) { // Metal
                // For metal, we can assume perfect reflection, so we just continue the ray in the reflected direction
                // v - 2*dot(v,n)*n;
                vec3 reflectedDir = reflect(currentRay.direction, closestHitRecord.normal);
                currentRay = Ray(closestHitRecord.hitPoint + closestHitRecord.normal * 0.0001, reflectedDir); // Offset hitPoint to avoid self-intersection
                // Add the color of the hit sphere, modulated by the accumulated color
                outColor += accumulatedColor * spheres[hitSphereIndex].color;
                // clamp the color to avoid overflow
                outColor = clampColor(outColor);
            } else if (spheres[hitSphereIndex].material == 0) { // Lambertian
                // For lambertian, we need to scatter the ray in a random direction on the hemisphere defined by the normal

                // A more robust random/hash function might be needed here.
                vec3 randomDir = randomOnHemisphere(closestHitRecord.normal, seed);

                // Add the color of the hit sphere, modulated by the accumulated color
                outColor += accumulatedColor * spheres[hitSphereIndex].color;
                // clamp the color to avoid overflow
                outColor = clampColor(outColor);
                currentRay = Ray(closestHitRecord.hitPoint + closestHitRecord.normal * 0.0001, randomDir); // Offset hitPoint to avoid self-intersection
            } else if (spheres[hitSphereIndex].material == 2) { // Glass
                // is front of sphere
                float ri = 0.0;
                if (isFrontFace) 
                    ri = 1.0/REFRACTION_INDEX;
                else 
                    ri = REFRACTION_INDEX;

                vec3 refractedDir = refract(normalize(currentRay.direction), closestHitRecord.normal, ri );
                
                float cos_theta = min(dot(-normalize(currentRay.direction), closestHitRecord.normal),1.0);
                float sin_theta = sqrt(1.0 - cos_theta*cos_theta);
                bool cannot_refract = ri * sin_theta > 1.0;
                // Check for Total Internal Reflection
                if (cannot_refract) {
                    // Handle TIR with a reflection
                    vec3 reflectedDir = reflect(normalize(currentRay.direction), closestHitRecord.normal);
                    outColor += accumulatedColor * spheres[hitSphereIndex].color;
                    outColor = clampColor(outColor);
                    currentRay = Ray(closestHitRecord.hitPoint + closestHitRecord.normal * 0.0001, reflectedDir);
                } else {
                    // No TIR, so refract the ray
                    outColor += accumulatedColor * spheres[hitSphereIndex].color;
                    outColor = clampColor(outColor);
                    currentRay = Ray(closestHitRecord.hitPoint - closestHitRecord.normal * 0.0001, refractedDir); // Note the offset direction
                }            
            }


            // Attenuate the accumulated color for the next bounce (e.g., by material properties or a fixed factor)
            accumulatedColor = accumulatedColor * 0.5 *spheres[hitSphereIndex].color; 

            // Update the ray for the next bounce
        } else {
            vec3 unitDir = normalize(currentRay.direction);
            float a = 0.5 * (unitDir.y + 1.0); // Simple sky gradient based on direction
            outColor += accumulatedColor * mix(vec3(0.3, 0.5, 0.8), vec3(1.0, 1.0, 1.0), a);
            break; // Exit the loop as the ray hit nothing
        }
    }
    // now add contribution from the directional light
    vec3 lightDir = normalize(dirlight1.direction);
    float lightIntensity = max(dot(lightDir, normalize(currentRay.direction)), dirlight1.intensity); // Lambertian reflectance
    outColor += lightIntensity * dirlight1.color * accumulatedColor; // Add light contribution
    return outColor; // Return the accumulated color after all bounces
}

void main()
{
    /*
          1. Reconstruct the world-space position of this pixel
          ▸ Convert fragTexCoord (0‒1) to NDC (-1‒1)
          ▸ Push it to clip-space at z = -1 (near plane)
          ▸ Multiply by inverse VP and divide by w
        */
    vec2 ndc = fragTexCoord * 2.0 - 1.0;
    /*ndc.y = -ndc.y;*/ // flip Y because textures are upside-down
    vec4 clipPos = vec4(ndc, -1.0, 1.0); // near-plane clip position
    vec4 worldPos4 = invViewProj * clipPos;
    vec3 worldPos = worldPos4.xyz / worldPos4.w;

    int depth = 20;
    int samples_per_pixel = 20;
    vec3 outputColor = vec3(0.0, 0.0, 0.0); // initial color
    //colorRay(r, outputColor, depth);
    for (int i = 0; i < samples_per_pixel; i++) {
        // Generate a new ray for each sample
        Ray sampleRay = Ray(cameraPosition, normalize(worldPos - cameraPosition + randomVec3(-0.000000001, 0.0000000001, seed)));
        vec3 sampleColor = vec3(0.0, 0.0, 0.0);
        colorRayIterative(sampleRay, sampleColor, depth);
        outputColor += sampleColor; // accumulate color from each sample
    }
    outputColor /= float(samples_per_pixel); // average the color over samples
    fragColor = vec4(outputColor, 1.0); // set the output color with full opacity
}
