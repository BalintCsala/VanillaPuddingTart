#version 150

// I'm targeting anything beyond 1024x768, without the taskbar, that let's us use 1024x705 pixels
// This should just barely fit 8, 88 deep layers vertically (8 * 88 + 1 control line = 705)
// I want to keep the stored layers square, therefore I only use 88 * 11 = 968 pixels horizontally
const vec2 VOXEL_STORAGE_RESOLUTION = vec2(1024, 705);
const float LAYER_SIZE = 88;

// Block types
#define AIR             0u
#define CUBE_COLUMN     1u
#define LEAVES          3u
#define CROSS           16u
#define GRASS_BLOCK     117u
#define CUBE_ALL        131u

const float PI = 3.14159265;
const float PHI = 1.61803398;
const float SQRT_2 = 1.4142135;
const float EPSILON = 0.00001;

const float GAMMA_CORRECTION = 2.2;
const int MAX_STEPS = 100;
const int MAX_GLOBAL_ILLUMINATION_STEPS = 10;
const int MAX_GLOBAL_ILLUMINATION_BOUNCES = 3;
const int MAX_REFLECTION_BOUNCES = 10;
const vec3 SUN_COLOR = pow(1.0 * vec3(1.0, 0.95, 0.8), vec3(GAMMA_CORRECTION));
const vec3 MOON_COLOR = pow(0.5 * vec3(0.8, 0.8, 0.9), vec3(GAMMA_CORRECTION));
const float SKY_INTENSITY = 2.0;
const float SUN_ANGULAR_SIZE = 0.01;
const float MAX_EMISSION_STRENGTH = 5;

const vec2 STORAGE_DIMENSIONS = floor(VOXEL_STORAGE_RESOLUTION / LAYER_SIZE);

uniform sampler2D DiffuseSampler;
uniform sampler2D AtlasSampler;
uniform sampler2D SteveSampler;
// Blue noise from http://momentsingraphics.de/BlueNoise.html
uniform sampler2D NoiseSampler;
uniform sampler2D AtmosphereSampler;

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
    uint type;
    vec2 blockTexCoord;
    vec3 albedo;
    vec3 F0;
    vec4 emission;
    float roughness;
    vec3 normal;
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

BlockData air() {
    BlockData res;
    res.type = AIR;
    return res;
}

// Sorts the input hits so that the first is the first hit
// Returns if either of them were successful
bool combine(inout Hit hit1, inout Hit hit2) {

    if (hit1.traceLength < EPSILON && hit2.traceLength < EPSILON)
        return false;

    // If they aren't in the right order, we swap them
    if (!((hit1.traceLength > EPSILON && hit1.traceLength < hit2.traceLength) || hit2.traceLength < EPSILON)) {
        Hit temp = hit1;
        hit1 = hit2;
        hit2 = temp;
    }

    return true;
}

// Calculates the intersection distance between a ray and a face
float raytraceFace(vec3 center, inout vec3 normal, vec3 up, vec2 size, vec3 rayOrigin, vec3 rayDirection, out vec2 texCoord) {
    // Distance to the plane the face is in
    float t = dot(center - rayOrigin, normal) / dot(rayDirection, normal);
    // If this is negative, we're facing away from it, therefore no hit
    if (t < EPSILON)
        return -1.0;

    // We can then calculate the hit position and adjust normal based on whether it's facing towards the camera
    vec3 hitPos = rayOrigin + rayDirection * t;
    if (dot(normal, rayOrigin - hitPos) < 0)
        normal = -normal;

    // We calculate the relative x and y axis of the plane the face is in
    // xAxis, yAxis and normal should all be 90deg apart from each other
    vec3 xAxis = cross(up, normal);
    vec3 yAxis = cross(xAxis, normal);

    // texCoord can then be calculated with dot products and scaled to fit the size
    texCoord = vec2(dot(hitPos - center, xAxis), dot(hitPos - center, yAxis)) / size;

    // If texCoord.x or texCoord.y is outside of the [-0.5, 0.5] range, the hit position is outside of the face
    if (any(greaterThan(abs(texCoord), vec2(0.5))))
        return -1.0;

    texCoord += 0.5;

    // Otherwise we return the hit
    return t;
}

// Overload for voxel-based tracing
Hit raytraceFace(vec3 center, vec3 normal, vec3 up, vec2 size, Ray ray) {
    vec2 texCoord;
    float t = raytraceFace(center, normal, up, size, ray.blockPosition, ray.direction, texCoord);
    
    if (t < EPSILON)
        return noHit();

    vec3 hitPos = ray.blockPosition + ray.direction * t;

    // Otherwise we return the hit
    BlockData blockData;
    return Hit(t, ray.currentBlock, hitPos, normal, blockData, texCoord);
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
    vec2 layerStart = vec2(mod(position.y, STORAGE_DIMENSIONS.x), floor(position.y / STORAGE_DIMENSIONS.x)) * LAYER_SIZE;
    return (layerStart + inLayerPos + vec2(0.5, 1.5)) / (VOXEL_STORAGE_RESOLUTION - 1);
}

// Decodes stored rgb values into a uint value
uint decodeUint(vec3 ivec) {
    ivec *= 255.0;
    return (uint(ivec.r) << 16) | (uint(ivec.g) << 8) | uint(ivec.b);
}

const vec3 PREDETERMINED_F0[] = vec3[](
    vec3(0.53123, 0.51236, 0.49583), // Iron
    vec3(0.94423, 0.77610, 0.37340), // Gold
    vec3(0.91230, 0.91385, 0.91968), // Aluminium
    vec3(0.55560, 0.55454, 0.55478), // Chrome
    vec3(0.92595, 0.72090, 0.50415), // Copper
    vec3(0.63248, 0.62594, 0.64148), // Lead
    vec3(0.67885, 0.64240, 0.58841), // Platinum
    vec3(0.96200, 0.94947, 0.92212)  // Silver
);

vec3 decodeF0(float stored, vec3 albedo) {
    if (stored < 230.0 / 255)
        return vec3(stored / 255); 
    
    if (stored > 254.0 / 255)
        return albedo;
    
    int index = int(stored * 255) - 230;
    return PREDETERMINED_F0[index];
}

vec3 skyColor(vec3 direction) {
    vec2 texcoord = vec2(
        dot(direction, vec3(0, 1, 0)) * 0.5 + 0.5,
        dot(sunDir, vec3(0, 1, 0)) * 0.5 + 0.5
    ) * 0.999;
    return pow(texture(AtmosphereSampler, texcoord).rgb * SKY_INTENSITY, vec3(GAMMA_CORRECTION));
}

// Returns the block data for the block at the specified position
BlockData getBlock(inout Ray ray, inout vec2 texCoord, inout vec3 normal, out float extraLength) {
    extraLength = 0;
    vec3 rawData = texture(DiffuseSampler, blockToTexCoord(ray.currentBlock)).rgb;

    if (rawData.x + rawData.y + rawData.z < EPSILON)
        return air();

    uint data = decodeUint(rawData);

    BlockData blockData;
    blockData.type = (data >> 4u) & 255u;
    blockData.blockTexCoord = (vec2((data >> 18u) & 63u, (data >> 12u) & 63u));

    switch (blockData.type) {
        case CUBE_COLUMN:
            blockData.blockTexCoord.x += 1 - abs(dot(normal, vec3(0, 1, 0)));
            break;
        case CROSS:
            Hit hit1 = raytraceFace(vec3(0.5), vec3(1, 0, 1) / SQRT_2, vec2(1), ray);
            Hit hit2 = raytraceFace(vec3(0.5), vec3(1, 0, -1) / SQRT_2, vec2(1), ray);

            bool success = combine(hit1, hit2);

            if (!success)
                return air();
            
            Hit hit = hit1;
            if (texture(AtlasSampler, (blockData.blockTexCoord + hit.texCoord) / 128).a < 0.5)
                hit = hit2;
            
            if (hit.traceLength < EPSILON)
                return air();

            extraLength = hit.traceLength;
            texCoord = hit.texCoord;
            normal = vec3(0, 1, 0);
            ray.currentBlock = hit.block;

            break;
        case GRASS_BLOCK:
            blockData.blockTexCoord.x += 2 - max(dot(normal, vec3(0, 1, 0)), 0) - max(dot(normal, vec3(0, -1, 0)), 0) * 2;
            break;

    }

    blockData.blockTexCoord = (blockData.blockTexCoord + texCoord) / 64;

    vec4 textureData = texture(AtlasSampler, blockData.blockTexCoord / 2);
    if (textureData.a < 1.0 / 255)
        return air();

    vec4 specularData = texture(AtlasSampler, blockData.blockTexCoord / 2 + vec2(0.5, 0));
    vec3 normalData = texture(AtlasSampler, blockData.blockTexCoord / 2 + vec2(0, 0.5)).rgb * 2 - 1;
    vec4 miscData = texture(AtlasSampler, blockData.blockTexCoord / 2 + vec2(0.5, 0.5));

    blockData.albedo = pow(textureData.rgb, vec3(GAMMA_CORRECTION));
    blockData.F0 = decodeF0(specularData.g, blockData.albedo);
    blockData.roughness = (1 - specularData.r) * (1 - specularData.r);
    blockData.emission = vec4(blockData.albedo, specularData.a);
    if (specularData.a > 254.0 / 255)
        blockData.emission.a = 0;
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
    
    
    float rayLength = 0;
    float extraLength;
    vec2 texCoord;
    vec3 normal;
    
    // Check the current block to see if we're already in one (self-shadows don't work otherwise)
    BlockData blockData = getBlock(ray, texCoord, normal, extraLength);
    if (blockData.type != AIR && extraLength > EPSILON)
        return Hit(rayLength + extraLength, ray.currentBlock, ray.blockPosition + ray.direction * extraLength, normal, blockData, texCoord);
    
    vec3 signedDirection = sign(ray.direction);
    
    // The steps in each direction:
    vec3 steps = (signedDirection * 0.5 + 0.5 - ray.blockPosition) / ray.direction;
    // Cap the amount of steps we take to make sure no ifinite loop happens.

    vec3 startWorldPosition = ray.currentBlock + ray.blockPosition;
    vec3 steveNormal = normalize(vec3(facingDirection.x, 0, facingDirection.z));
    vec2 steveTexCoord;
    float steveT = raytraceFace(vec3(0, -0.9, 0) - chunkOffset, steveNormal, vec3(0, 1, 0), vec2(1, 1.8), startWorldPosition, ray.direction, steveTexCoord);
    bool steveHit = steveT > EPSILON;

    for (int voxelStep = 0; voxelStep < maxSteps; voxelStep++) {

        vec3 startWorldPosition = ray.currentBlock + ray.blockPosition;
        float stepLength = min(min(steps.x, steps.y), steps.z);

        ray.blockPosition += stepLength * ray.direction;
        steps -= stepLength;
        rayLength += stepLength;

        if (steveHit && steveT < rayLength) {
            steveTexCoord.x = steveTexCoord.x / 6 + steveCoordOffset;
            vec4 color = texture(SteveSampler, steveTexCoord); 
            if (color.a > 0.5) {
                BlockData steveData;
                steveData.type = 255u;
                steveData.albedo = color.rgb;
                steveData.F0 = vec3(0);
                steveData.emission = vec4(0);
                steveData.roughness = 0.5;
                vec3 hitPos = startWorldPosition + steveT * ray.direction;
                return Hit(steveT, floor(hitPos), fract(hitPos), steveNormal, steveData, steveTexCoord);
            }
            // If we ever cross the plane Steve is in, we won't check it ever again
            steveHit = false;
        }

        // We select the smallest of the steps and update the current block and block position.
        vec3 nextBlock = step(steps, vec3(EPSILON));

        ray.currentBlock += signedDirection * nextBlock;

        if (any(greaterThan(abs(ray.currentBlock), vec3(LAYER_SIZE / 2)))) {
            // We're outside of the known world, here be dragons. Let's stop
            return noHit();
        }

        ray.blockPosition = mix(ray.blockPosition, step(signedDirection, vec3(0.5)), nextBlock);
        steps += signedDirection / ray.direction * nextBlock;

        // We can now query the block at the current position.
        normal = -signedDirection * nextBlock;
        texCoord = mix((vec2(ray.blockPosition.x, 1.0 - ray.blockPosition.y) - 0.5) * vec2(abs(normal.y) + normal.z, 1.0),
                                (vec2(1.0 - ray.blockPosition.z, ray.blockPosition.z) - 0.5) * vec2(normal.x + normal.y), nextBlock.xy) + vec2(0.5);
        
        blockData = getBlock(ray, texCoord, normal, extraLength);
        if (blockData.type != AIR)
            return Hit(rayLength + extraLength, ray.currentBlock, ray.blockPosition + ray.direction * extraLength, normal, blockData, texCoord);

    }
    return noHit();
}

// Calculates the global illumination at a hit position
vec3 globalIllumination(Hit hit, Ray ray, float traceSeed) {
    vec3 accumulated = vec3(0.0);
    vec3 weight = vec3(1.0);

    Ray sunRay, moonRay;
    Hit sunlightHit, moonlightHit;
    for (int steps = 0; steps < MAX_GLOBAL_ILLUMINATION_BOUNCES; steps++) {
        // After each bounce, change the base color
        weight *= hit.blockData.albedo * (1 - fresnel(hit.blockData.F0, 1 - dot(ray.direction, hit.normal)));

        // Summon rays
        vec3 direction = randomDirection(texCoord, hit.normal, float(steps) * 754.54 + traceSeed, 1.0);
        vec3 sunDirection = randomDirection(texCoord, sunDir, float(steps) + 823.375 + traceSeed, SUN_ANGULAR_SIZE);
        float NdotL = dot(sunDir, hit.normal);
        float sunContrib = sqrt(max(NdotL, 0.0));
        float moonContrib = sqrt(max(-NdotL, 0.0));

        ray = Ray(hit.block, hit.blockPosition, direction);
        sunRay = Ray(hit.block, hit.blockPosition, sunDirection);
        moonRay = Ray(hit.block, hit.blockPosition, -sunDirection);

        // Path tracing
        hit = trace(ray, MAX_STEPS);
        sunlightHit = trace(sunRay, MAX_STEPS);
        moonlightHit = trace(moonRay, MAX_STEPS);

        accumulated += hit.blockData.emission.rgb * MAX_EMISSION_STRENGTH * hit.blockData.emission.a * weight;
        accumulated += sunContrib * step(sunlightHit.traceLength, EPSILON) * SUN_COLOR * weight;
        accumulated += moonContrib * step(moonlightHit.traceLength, EPSILON) * MOON_COLOR * weight;

        if (hit.traceLength < EPSILON) {
            // Didn't hit a block, we'll draw the sky
            accumulated += skyColor(ray.direction) * weight;
            break;
        }
    }

    return accumulated;
}

float getSunFactor(vec3 direction) {
    float fac = smoothstep(0.9991, 0.99995, dot(direction, sunDir));
    return fac * fac;
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
        float sunFactor = getSunFactor(ray.direction);
        return sunFactor * SUN_COLOR + (1 - sunFactor) * skyColor(ray.direction) * weight;
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
            vec3 skyCol = skyColor(ray.direction);
            accumulated += skyCol * weight;
            float sunFactor = getSunFactor(ray.direction);
            sunFactor *= sunFactor;
            accumulated += (sunFactor * SUN_COLOR + (1 - sunFactor) * skyCol) * weight;
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
