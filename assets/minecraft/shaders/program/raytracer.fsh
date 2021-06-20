#version 150

// I'm targeting anything beyond 1024x768, without the taskbar, that let's us use 1024x705 pixels
// This should just barely fit 8, 88 deep layers vertically (8 * 88 + 1 control line = 705)
// I want to keep the stored layers square, therefore I only use 88 * 11 = 968 pixels horizontally
const vec2 VOXEL_STORAGE_RESOLUTION = vec2(1024, 705);
const float LAYER_SIZE = 88;

// Block types
#define CUBE_COLUMN     1u
#define GRASS_BLOCK     117u

const float PI = 3.141592654;
const float PHI = 1.618033988749894848204586;
const float EPSILON = 0.00001;

const float GAMMA_CORRECTION = 2.2;
const int MAX_STEPS = 100;
const int MAX_GLOBAL_ILLUMINATION_STEPS = 10;
const int MAX_GLOBAL_ILLUMINATION_BOUNCES = 3;
const int MAX_REFLECTION_BOUNCES = 10;
const vec3 SUN_COLOR = pow(1.0 * vec3(1.0, 0.95, 0.8), vec3(GAMMA_CORRECTION));
const vec3 SKY_COLOR = pow(2.0 * vec3(0.2, 0.35, 0.5), vec3(GAMMA_CORRECTION));
const float SUN_ANGULAR_SIZE = 0.01;
const float MAX_EMISSION_STRENGTH = 5;

const vec2 STORAGE_DIMENSIONS = floor(VOXEL_STORAGE_RESOLUTION / LAYER_SIZE);

uniform sampler2D DiffuseSampler;
uniform sampler2D AtlasSampler;
uniform sampler2D SteveSampler;
// Blue noise from http://momentsingraphics.de/BlueNoise.html
uniform sampler2D NoiseSampler;
uniform sampler2D DistanceSampler;

uniform vec2 OutSize;
uniform float Time;

in vec2 texCoord;
in vec3 sunDir;
in mat4 projMat;
in mat4 modelViewMat;
in vec3 chunkOffset;
in vec3 rayDir;
in vec3 facingDirection;
in vec2 horizontalFacingDirection;
in float near;
in float far;
in float steveCoordOffset;

out vec4 fragColor;

struct Ray {
    // Index of the block the ray is in.
    vec3 currentBlock;
    // Position of the ray inside the block.
    vec3 blockPosition;
    // The direction of the ray
    vec3 direction;
};

struct BlockData {
    int type;
    vec2 blockTexCoord;
    vec3 albedo;
    vec3 F0;
    vec4 emission;
    float metallicity;
    float roughness;
};

struct Hit {
    float traceLength;
    vec3 block;
    vec3 blockPosition;
    vec3 normal;
    BlockData blockData;
    vec2 texCoord;
};

Hit noHit() {
    Hit res;
    res.traceLength = -1;
    return res;
}

// Combines two hit datas into a single hit.
// Returns the first hit and provides the second hit in an out
Hit combine(Hit hit1, Hit hit2, out Hit secondHit) {
    // 5 options
    //  - t1 <= 0, t2 <= 0 -> noHit, doesn't matter what we return, so we'll return hit1
    //  - t1 > 0, t2 <= 0 -> hit1
    //  - t1 > 0, t2 > 0, t1 <= t2 -> hit1
    if ((hit1.traceLength > EPSILON && hit1.traceLength < hit2.traceLength) || hit2.traceLength < EPSILON) { 
        secondHit = hit2;
        return hit1;
    }

    //  - t1 <= 0, t2 > 0 -> hit2
    //  - t1 > 0, t2 > 0, t1 > t2 -> hit2
    secondHit = hit1;
    return hit2; 
}

// Calculates the hit point of a ray and a rectangular, arbitarily rotated face
Hit raytraceFace(vec3 center, vec3 normal, vec3 up, vec2 size, Ray ray) {
    // Distance to the plane the face is in
    float t = dot(ray.blockPosition - center, normal) / dot(ray.direction, normal);
    // If this is negative, we're facing away from it, therefore no hit
    if (t < EPSILON)
        return noHit();

    // We can then calculate the hit position and adjust normal based on whether it's facing towards the camera
    vec3 hitPos = ray.blockPosition + ray.direction * t;
    if (dot(normal, ray.blockPosition - hitPos) < 0)
        normal = -normal;

    // We calculate the relative x and y axis of the plane the face is in
    // xAxis, yAxis and normal should all be 90deg apart from each other
    vec3 xAxis = cross(normal, up);
    vec3 yAxis = cross(xAxis, normal);

    // texCoord can then be calculated with dot products and scaled to fit the size
    vec2 texCoord = vec2(dot(hitPos - center, xAxis), dot(hitPos - center, yAxis)) / size;

    // If texCoord.x or texCoord.y is outside of the [-0.5, 0.5] range, the hit position is outside of the face
    if (any(greaterThan(abs(texCoord), vec2(0.5))))
        return noHit();

    // Otherwise we return the hit
    BlockData blockData;
    return Hit(t, ray.currentBlock, hitPos, normal, blockData, texCoord + 0.5);
}

// Overload for when up = (0, 1, 0)
Hit raytraceFace(vec3 center, vec3 normal, vec2 size, Ray ray) {
    return raytraceFace(center, normal, vec3(0, 1, 0), size, ray);
}

// Converts block coordinates to texture coordinates for voxel lookup
vec2 blockToTexCoord(vec3 position) {
    // We offset everything by LAYER_SIZE / 2 to make sure it's positive
    position += LAYER_SIZE / 2;
    // We store the blocks in layers
    vec2 inLayerPos = position.xz;
    vec2 layerStart = vec2(mod(position.y, STORAGE_DIMENSIONS.y), floor(position.y / STORAGE_DIMENSIONS.y)) * LAYER_SIZE;
    return (layerStart + inLayerPos + vec2(0.5, 1.5)) / (VOXEL_STORAGE_RESOLUTION - 1);
}

// Decodes stored rgb values into a uint value
uint decodeUint(vec3 ivec) {
    ivec *= 255.0;
    return uint(ivec.r) * 256u * 256u + uint(ivec.g) * 256u + uint(ivec.b);
}

// Returns the block data for the block at the specified position
BlockData getBlock(vec3 currentBlock, vec2 texCoord, vec3 normal) {
    vec3 rawData = texture(DiffuseSampler, blockToTexCoord(currentBlock)).rgb;
    BlockData blockData;
    uint data = decodeUint(rawData);

    uint type = (data >> 4u) & 255u;

    vec2 blockTexCoord = (vec2((data >> 18u) & 63u, (data >> 12u) & 63u) + texCoord);

    switch (type) {
        case GRASS_BLOCK:
            blockTexCoord.x += 2 - max(dot(normal, vec3(0, 1, 0)), 0) - max(dot(normal, vec3(0, -1, 0)), 0) * 2;
            break;
        case CUBE_COLUMN:
            blockTexCoord.x += 1 - abs(dot(normal, vec3(0, 1, 0)));
            break;
    }

    blockTexCoord /= 64;

    blockData.type = 1;
    blockData.blockTexCoord = blockTexCoord;
    blockData.albedo = pow(texture(AtlasSampler, blockTexCoord / 2).rgb, vec3(GAMMA_CORRECTION));
    blockData.F0 = texture(AtlasSampler, blockTexCoord / 2 + vec2(0, 0.5)).rgb;
    blockData.emission = pow(texture(AtlasSampler, blockTexCoord / 2 + vec2(0.5, 0)), vec4(vec3(GAMMA_CORRECTION), 1.0));

    vec4 combined = texture(AtlasSampler, blockTexCoord / 2 + 0.5);
    blockData.metallicity = combined.r;
    blockData.roughness = combined.g;
    return blockData;
}

// By Inigo Quilez - https://www.shadertoy.com/view/XlXcW4
const uint k = 1103515245U;

vec3 hash(uvec3 x) {
    x = ((x >> 8U) ^ x.yzx) * k;
    x = ((x >> 8U) ^ x.yzx) * k;
    x = ((x >> 8U) ^ x.yzx) * k;

    return vec3(x) * (1.0 / float(0xffffffffU));
}

// Returns a noise value for the current fragment using the specified seed
vec3 noise(float seed) {
    uvec3 p = uvec3(gl_FragCoord.xy, (Time * 32.46432 + seed) * 60);
    vec3 offset = hash(p) * PHI;
    return mod(texture(NoiseSampler, gl_FragCoord.xy / textureSize(NoiseSampler, 0)).rgb + offset, 1);
}

// Chooses a random direction using cosine weighted hemisphere sampling
vec3 randomDirection(vec2 coords, vec3 normal, float seed, float deviateFactor) {
    vec3 v = noise(seed);
    float angle = 2 * PI * v.x;
    float u = 2 * v.y - 1;

    vec3 directionOffset = vec3(sqrt(1 - u * u) * vec2(cos(angle), sin(angle)), u);
    return normalize(normal + directionOffset * deviateFactor);
}

// Calculates the fresnel factor based on angle and F0
vec3 fresnel(vec3 F0, float cosTheta) {
    return F0 + (1 - F0) * pow(max(1 - cosTheta, 0), 5);
}

// Traces a ray through the voxel field
Hit trace(Ray ray, int maxSteps) {
    // The world is divided into blocks, so we can use a simplified tracing algorithm where we always go to the
    // nearest block boundary. This can be very easily calculated by dividing the signed distance to the six walls
    // of the current block by the signed components of the ray's direction. This way we get the size of the step
    // we need to take to reach a wall in that direction.
    
    // We also use an SDF to skip checking the blocks for some of the positions

    float rayLength = 0;
    vec3 signedDirection = sign(ray.direction);
    
    // The steps in each direction:
    vec3 steps = (signedDirection * 0.5 + 0.5 - ray.blockPosition) / ray.direction;
    // Cap the amount of steps we take to make sure no ifinite loop happens.
    int voxelStep = 0;
    while (voxelStep < maxSteps) {
        vec3 nextBlock;
        while (true) {
            int distanceToClosest = int(round(texture(DistanceSampler, blockToTexCoord(ray.currentBlock)).r * 255));

            if (distanceToClosest == 0)
                break;

            for (int j = 0; j < distanceToClosest; j++) {
                float stepLength = min(min(steps.x, steps.y), steps.z);

                ray.blockPosition += stepLength * ray.direction;
                steps -= stepLength;
                rayLength += stepLength;

                // We select the smallest of the steps and update the current block and block position.
                nextBlock = step(steps, vec3(EPSILON));

                ray.currentBlock += signedDirection * nextBlock;
                ray.blockPosition = mix(ray.blockPosition, step(signedDirection, vec3(0.5)), nextBlock);
                steps += signedDirection / ray.direction * nextBlock;
                voxelStep++;
            }

            if (any(greaterThan(abs(ray.currentBlock), vec3(LAYER_SIZE / 2 - 1)))) {
                // We're outside of the known world, here be dragons. Let's stop
                return noHit();
            }
        }

    
        // We can now query the block at the current position.
        vec3 normal = -signedDirection * nextBlock;
        vec2 texCoord = mix((vec2(ray.blockPosition.x, 1.0 - ray.blockPosition.y) - 0.5) * vec2(abs(normal.y) + normal.z, 1.0),
                                (vec2(1.0 - ray.blockPosition.z, ray.blockPosition.z) - 0.5) * vec2(normal.x + normal.y), nextBlock.xy) + vec2(0.5);
        BlockData blockData = getBlock(ray.currentBlock, texCoord, normal);
        return Hit(rayLength, ray.currentBlock, ray.blockPosition, normal, blockData, texCoord);
        /* else if (distance(ray.currentBlock, vec3(-1.0, -2.0, -1.0)) < 1.8) {
            vec3 rayActualPos = ray.currentBlock + ray.blockPosition + chunkOffset;
            float steveDistance = intersectPlane(rayActualPos, ray.direction, vec3(facingDirection.x, EPSILON, facingDirection.z));
            vec3 thingHitPos = rayActualPos + ray.direction * steveDistance;
            float nextStepLength = min(min(steps.x, steps.y), steps.z);
            // Let's check whether the ray will intersect a cylinder
            if (abs(2.0 * steveDistance - nextStepLength) < nextStepLength && abs(0.70 + thingHitPos.y) < 1 && length(thingHitPos.xz) < 0.5) {
                Hit hit;
                hit.traceLength = 999;

                hit.texCoord = vec2((dot(thingHitPos.xz, vec2(-horizontalFacingDirection.y, horizontalFacingDirection.x)) + 0.5) / 6 + steveCoordOffset,
                                    0.10 - thingHitPos.y / 2);

                vec3 thingColor = texture(SteveSampler, hit.texCoord).rgb;
                if (thingColor.x + thingColor.y + thingColor.z > EPSILON) {
                    hit.blockData.albedo = pow(thingColor, vec3(GAMMA_CORRECTION));
                    return hit;
                }
            }
        }*/
    }
    return noHit();
}

// Calculates the global illumination at a hit position
vec3 globalIllumination(Hit hit, Ray ray, float traceSeed) {
    vec3 accumulated = vec3(0.0);
    vec3 weight = vec3(1.0);

    Ray sunRay;
    Hit sunlightHit;
    for (int steps = 0; steps < MAX_GLOBAL_ILLUMINATION_BOUNCES; steps++) {
        // After each bounce, change the base color
        weight *= hit.blockData.albedo * (1 - fresnel(hit.blockData.F0, 1 - dot(ray.direction, hit.normal)));

        // Summon rays
        vec3 direction = randomDirection(texCoord, hit.normal, float(steps) * 754.54 + traceSeed, 1.0);
        vec3 sunDirection = randomDirection(texCoord, sunDir, float(steps) + 823.375 + traceSeed, SUN_ANGULAR_SIZE);
        float NdotL = max(dot(sunDir, hit.normal), 0.0);

        ray = Ray(hit.block, hit.blockPosition, direction);
        sunRay = Ray(hit.block, hit.blockPosition, sunDirection);

        // Path tracing
        hit = trace(ray, MAX_STEPS);
        sunlightHit = trace(sunRay, MAX_STEPS);

        accumulated += hit.blockData.emission.rgb * MAX_EMISSION_STRENGTH * hit.blockData.emission.a * weight;
        accumulated += sqrt(NdotL) * step(sunlightHit.traceLength, EPSILON) * SUN_COLOR * weight;

        if (hit.traceLength < EPSILON) {
            // Didn't hit a block, we'll draw the sky
            accumulated += SKY_COLOR * weight;
            break;
        }
    }

    return accumulated;
}

// Main path tracing code
vec3 pathTrace(Ray ray, out float depth) {
    vec3 accumulated = vec3(0.0);
    vec3 weight = vec3(1.0);

    // Get direct world position
    Hit hit = trace(ray, MAX_STEPS);
    depth = hit.traceLength + near;

    if (hit.traceLength < EPSILON) {
        // We didn't hit anything
        depth = far;
        float sunFactor = smoothstep(0.9987, 0.999, dot(ray.direction, sunDir));
        return sunFactor * SUN_COLOR + (1 - sunFactor) * SKY_COLOR * weight;
    }

    // Global Illumination
    accumulated += hit.blockData.emission.rgb * MAX_EMISSION_STRENGTH * hit.blockData.emission.a;
    accumulated += globalIllumination(hit, ray, 31.43);

    // Reflection
    for (int steps = 0; steps < MAX_REFLECTION_BOUNCES; steps++) {
        weight *= fresnel(hit.blockData.F0, 1 - dot(ray.direction, hit.normal));
        if (dot(weight, weight) < EPSILON) {
            break;
        }

        vec3 direction = reflect(ray.direction, hit.normal);
        direction = randomDirection(texCoord, direction, float(steps) * 63.46103, hit.blockData.roughness);
        ray = Ray(hit.block, hit.blockPosition, direction);
        hit = trace(ray, MAX_STEPS);

        if (hit.traceLength < EPSILON) {
            // We didn't hit anything
            accumulated += SKY_COLOR * weight;
            float sunFactor = smoothstep(0.9987, 0.999, dot(ray.direction, sunDir));
            accumulated += (sunFactor * SUN_COLOR + (1 - sunFactor) * SKY_COLOR) * weight;
            break;
        }
        // Global Illumination in reflecton
        accumulated += globalIllumination(hit, ray, 456.56 * (float(steps) + 1)) * weight;
        accumulated += hit.blockData.emission.rgb * MAX_EMISSION_STRENGTH * hit.blockData.emission.a * weight;
    }

    return accumulated;
}

// Uchimura 2017, "HDR theory and practice"
// Math: https://www.desmos.com/calculator/gslcdxvipg
// Source: https://www.slideshare.net/nikuque/hdr-theory-and-practicce-jp
vec3 uchimura(vec3 x, float P, float a, float m, float l, float c, float b) {
    float l0 = ((P - m) * l) / a;
    float L0 = m - m / a;
    float L1 = m + (1.0 - m) / a;
    float S0 = m + l0;
    float S1 = m + a * l0;
    float C2 = (a * P) / (P - S1);
    float CP = -C2 / P;
    vec3 w0 = vec3(1.0 - smoothstep(0.0, m, x));
    vec3 w2 = vec3(step(m + l0, x));
    vec3 w1 = vec3(1.0 - w0 - w2);
    vec3 T = vec3(m * pow(x / m, vec3(c)) + b);
    vec3 S = vec3(P - (P - S1) * exp(CP * (x - S0)));
    vec3 L = vec3(m + a * (x - m));
    return T * w0 + L * w1 + S * w2;
}

vec3 uchimura(vec3 x) {
    const float P = 1.0;  // max display brightness
    const float a = 1.0;  // contrast
    const float m = 0.22; // linear section start
    const float l = 0.4;  // linear section length
    const float c = 1.33; // black
    const float b = 0.0;  // pedestal

    return uchimura(x, P, a, m, l, c, b);
}

void main() {
    // Set the pixel to black in case we don'steps hit anything.
    vec3 nRayDir = normalize(rayDir);
    Ray ray = Ray(vec3(-1), 1 - chunkOffset, nRayDir);

    float depth;
    vec3 color = pathTrace(ray, depth);
    if (depth < 0) depth = far;

    // HDR scaling
    color.rgb = uchimura(color.rgb);
    fragColor = vec4(pow(color, vec3(1.0 / GAMMA_CORRECTION)), 1);

    // We can set depth of the fragment so transparency.json can work correctly
    // Pretty much a copy of how you'd usually do it, position would be gl_Position
    vec4 position = projMat * modelViewMat * vec4(nRayDir * (depth - near), 1);
    float diffuseDepth = position.z / position.w;
    gl_FragDepth = (diffuseDepth + 1) / 2;
}
