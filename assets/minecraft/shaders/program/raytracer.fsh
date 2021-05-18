#version 150

const float PI = 3.141592654;
const float EPSILON = 0.00001;
const int MAX_STEPS = 100;
const int MAX_GLOBAL_ILLUMINATION_STEPS = 10;
const int MAX_GLOBAL_ILLUMINATION_BOUNCES = 3;
const int MAX_REFLECTION_BOUNCES = 10;
const vec3 SUN_COLOR = 1.0 * vec3(1.0, 0.95, 0.8);
const vec3 SKY_COLOR = 1 * vec3(0.2, 0.35, 0.5);
const float MAX_EMISSION_STRENGTH = 5;
// I'm targeting anything beyond 1024x768, without the taskbar, that let's us use 1024x705 pixels
// This should just barely fit 8, 88 deep layers vertically (8 * 88 + 1 control line = 705)
// I want to keep the stored layers square, therefore I only use 88 * 11 = 968 pixels horizontally
const vec2 VOXEL_STORAGE_RESOLUTION = vec2(1024, 705);
const float LAYER_SIZE = 88;
const vec2 STORAGE_DIMENSIONS = vec2(11, 8);

uniform sampler2D DiffuseSampler;
uniform sampler2D DiffuseDepthSampler;
uniform sampler2D TranslucentSampler;
uniform sampler2D TranslucentDepthSampler;
uniform sampler2D ItemEntitySampler;
uniform sampler2D ItemEntityDepthSampler;
uniform sampler2D ParticlesSampler;
uniform sampler2D ParticlesDepthSampler;
uniform sampler2D WeatherSampler;
uniform sampler2D WeatherDepthSampler;
uniform sampler2D CloudsSampler;
uniform sampler2D CloudsDepthSampler;
uniform sampler2D AtlasSampler;
uniform sampler2D SteveSampler;
//uniform sampler2D PreviousFrameSampler;
uniform vec2 OutSize;
uniform float Time;

in vec2 texCoord;
in vec2 oneTexel;
in vec3 sunDir;
in mat4 projMat;
in mat4 modelViewMat;
in mat4 projInv;
in vec3 chunkOffset;
in vec3 rayDir;
in vec3 facingDirection;
in float near;
in float far;

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
};

struct Hit {
    float t;
    vec3 block;
    vec3 blockPosition;
    vec3 normal;
    BlockData blockData;
    vec2 texCoord;
};

struct BounceHit {
    float t;
    vec3 block;
    vec3 blockPosition;
    vec3 color;
    vec3 normal;
    vec3 finalDirection;
};

// No moj_import here

vec2 pixelToTexCoord(vec2 pixel) {
    return pixel / (VOXEL_STORAGE_RESOLUTION - 1);
}

vec2 blockToPixel(vec3 position) {
    // The block data is split into layers. Each layer is 60x60 blocks and represents a single y height.
    // Therefore the position inside a layer is just the position of the block on the xz plane relative to the player.
    vec2 inLayerPos = position.xz + LAYER_SIZE / 2;
    // There are 60 layers, we store them in an 8x8 area.
    vec2 layerStart = vec2(mod(position.y + LAYER_SIZE / 2, STORAGE_DIMENSIONS.y), floor((position.y + LAYER_SIZE / 2) / STORAGE_DIMENSIONS.y)) * LAYER_SIZE;
    // The 0.5 offset is to read the center of the "pixels", the +1 offset on the y is to not interfere with the control line
    return layerStart + inLayerPos + vec2(0.5, 1.5);
}

int decodeInt(vec3 ivec) {
    ivec *= 255.0;
    int s = int(sign(127.9 - ivec.b));
    return s * (int(ivec.r) + int(ivec.g) * 256 + (int(ivec.b) - 64 + s * 64) * 256 * 256);
}

BlockData getBlock(vec3 position, vec2 texCoord) {
    BlockData blockData;
    vec3 rawData = texture(DiffuseSampler, pixelToTexCoord(blockToPixel(position))).rgb;
    if (any(greaterThan(abs(position), vec3(LAYER_SIZE / 2 - 1)))) {
        blockData.type = -99;
        return blockData;
    } else if (3 - rawData.x - rawData.y - rawData.z < EPSILON) {
        blockData.type = -1;
        return blockData;
    }
    int data = decodeInt(rawData);

    vec2 blockTexCoord = (vec2(data >> 6, data & 63) + texCoord) / 64;
    blockData.type = 1;
    blockData.blockTexCoord = blockTexCoord;
    blockData.albedo = texture(AtlasSampler, blockTexCoord / 2).rgb;
    blockData.F0 = texture(AtlasSampler, blockTexCoord / 2 + vec2(0, 0.5)).rgb;
    blockData.emission = texture(AtlasSampler, blockTexCoord / 2 + vec2(0.5, 0));
    blockData.metallicity = texture(AtlasSampler, blockTexCoord / 2 + 0.5).r;
    return blockData;
}

vec2 getControl(int index, vec2 screenSize) {
    return vec2(floor(screenSize.x / 2.0) + float(index) * 2.0 + 0.5, 0.5) / screenSize;
}

float intersectPlane(vec3 origin, vec3 direction, vec3 normal) {
    return dot(-origin, normal) / dot(direction, normal);
}

// By Inigo Quilez - https://www.shadertoy.com/view/XlXcW4
const uint k = 1103515245U;

vec3 hash(uvec3 x) {
    x = ((x >> 8U) ^ x.yzx) * k;
    x = ((x >> 8U) ^ x.yzx) * k;
    x = ((x >> 8U) ^ x.yzx) * k;

    return vec3(x) * (1.0 / float(0xffffffffU));
}

vec3 randomDirection(vec2 coords, vec3 normal, float seed) {
    uvec3 p = uvec3(coords * 5000, (Time * 32.46432 + seed) * 60);
    vec3 v = hash(p);
    float angle = 2 * PI * v.x;
    float u = 2 * v.y - 1;
    return normalize(normal + vec3(sqrt(1 - u * u) * vec2(cos(angle), sin(angle)), u));
}

vec3 fresnel(vec3 F0, float cosTheta) {
    return F0 + (1 - F0) * pow(max(1 - cosTheta, 0), 5);
}

Hit trace(Ray ray, int maxSteps, bool reflected) {
    float totalT = 0;
    vec3 signedDirection = sign(ray.direction);
    vec3 steps = (signedDirection * 0.5 + 0.5 - ray.blockPosition) / ray.direction;
    // Cap the amount of steps we take to make sure no ifinite loop happens.
    for (int i = 0; i < maxSteps; i++) {
        // The world is divided into blocks, so we can use a simplified tracing algorithm where we always go to the
        // nearest block boundary. This can be very easily calculated by dividing the signed distance to the six walls
        // of the current block by the signed components of the ray's direction. This way we get the size of the step
        // we need to take to reach a wall in that direction. This could be faster by precomputing 1 divided by the
        // components of the ray's direction, but I'll keep it simple here. Faster algorithms also exist.

        if (reflected && abs(ray.currentBlock.x + 1) <= 1 && abs(ray.currentBlock.z + 1) <= 1 && abs(ray.currentBlock.y +2) <= 1 ) {
            vec3 rayActualPos = ray.currentBlock + ray.blockPosition + chunkOffset;
            float t = intersectPlane(rayActualPos, ray.direction, vec3(facingDirection.x, 0, facingDirection.z));
            vec3 thingHitPos = rayActualPos + ray.direction * t;
            // Let's check whether the ray will intersect a cylinder
            if (t > 0 && abs(0.70 + thingHitPos.y) < 1 && length(thingHitPos.xz) < 0.5) {
                Hit hit;
                hit.t = 999;
                hit.texCoord = vec2((length(thingHitPos.xz) + 0.56) * 1.8 / 2, 0.10 - (thingHitPos.y) / 2);

                vec3 thingColor = texture(SteveSampler, hit.texCoord).rgb;
                if (thingColor.x + thingColor.y + thingColor.z > 0) {
                    hit.blockData.albedo = thingColor;
                    return hit;
                }
            }
        }

        // The steps in each direction:
        float t = min(min(steps.x, steps.y), steps.z);

        ray.blockPosition += t * ray.direction;
        steps -= t;
        totalT += t;

        // We select the smallest of the steps and update the current block and block position.
        vec3 normal;
        vec2 texCoord;
        if (steps.x < EPSILON) {
            normal = vec3(-signedDirection.x, 0, 0);
            ray.currentBlock.x += signedDirection.x;
            ray.blockPosition.x = (1 - signedDirection.x) / 2;
            steps.x = signedDirection.x / ray.direction.x;
            texCoord = ray.blockPosition.zy;
        } else if (steps.y < EPSILON) {
            normal = vec3(0, -signedDirection.y, 0);
            ray.currentBlock.y += signedDirection.y;
            ray.blockPosition.y = (1 - signedDirection.y) / 2;
            steps.y = signedDirection.y / ray.direction.y;
            texCoord = ray.blockPosition.xz;
        } else {
            normal = vec3(0, 0, -signedDirection.z);
            ray.currentBlock.z += signedDirection.z;
            ray.blockPosition.z = (1 - signedDirection.z) / 2;
            steps.z = signedDirection.z / ray.direction.z;
            texCoord = ray.blockPosition.xy;
        }
        // We can now query if there's a block at the current position.
        BlockData blockData = getBlock(ray.currentBlock, texCoord);

        if (blockData.type < -90) {
            // We're outside of the known world, there will be dragons. Let's stop
            break;
        }

        // If it's a block (type is non negative), we stop and draw to the screen.
        if (blockData.type > 0) {
            return Hit(totalT, ray.currentBlock, ray.blockPosition, normal, blockData, texCoord);
        }
    }
    Hit hit;
    hit.t = -1;
    return hit;
}

vec3 traceGlobalIllumination(Ray ray, out float depth, float traceSeed, bool reflected) {
    vec3 accumulated = vec3(0);
    vec3 weight = vec3(1);

    Hit hit;
    float totalT = 0;
    for (int steps = 0; steps < MAX_GLOBAL_ILLUMINATION_BOUNCES; steps++) {
        hit = trace(ray, steps == 0 ? MAX_STEPS : MAX_GLOBAL_ILLUMINATION_STEPS, steps > 0 || reflected);
        if (steps == 0) {
            depth = hit.t;
        }
        if (hit.t < EPSILON) {
            accumulated += SKY_COLOR * weight;
            break;
        }
        totalT += hit.t;

        weight *= hit.blockData.albedo * (1 - fresnel(hit.blockData.F0, 1 - dot(ray.direction, hit.normal)));

        if (hit.blockData.emission.a > 0) {
            accumulated += hit.blockData.emission.rgb * MAX_EMISSION_STRENGTH * weight;
        }

        // Sun contribution
        vec3 sunCheckDir = randomDirection(texCoord, sunDir * 50, float(steps) + 823.375 + traceSeed);
        Ray sunRay = Ray(hit.block, hit.blockPosition, sunCheckDir);
        Hit sunShadowHit = trace(sunRay, MAX_STEPS, true);
        accumulated += max(dot(sunDir, hit.normal), 0) * (sunShadowHit.t > EPSILON ? 0 : 1) * SUN_COLOR * weight;

        // ""Ambient""/sky contribution
        vec3 skyRayDirection = randomDirection(texCoord, hit.normal, float(steps) + 7.41 + traceSeed);
        Ray skyRay = Ray(hit.block, hit.blockPosition, skyRayDirection);
        Hit skyShadowHit = trace(skyRay, MAX_STEPS, true);
        accumulated += SKY_COLOR * (skyShadowHit.t > EPSILON ? 0.4 : 1) * weight;

        vec3 newDir = randomDirection(texCoord, hit.normal, float(steps) * 754.54 + traceSeed);
        ray = Ray(hit.block, hit.blockPosition, newDir);
    }

    return accumulated;
}

vec3 traceReflections(Ray ray, out float depth) {
    vec3 accumulated = vec3(0);
    vec3 weight = vec3(1);

    vec3 diff = traceGlobalIllumination(ray, depth, 31.43, false);
    accumulated += weight * diff;

    Hit hit;
    for (int steps = 0; steps < MAX_REFLECTION_BOUNCES; steps++) {
        hit = trace(ray, MAX_STEPS, steps > 0);

        if (hit.t < EPSILON) {
            accumulated += SKY_COLOR * weight;
            break;
        }

        weight *= fresnel(hit.blockData.F0, 1 - dot(ray.direction, hit.normal));

        if (dot(weight, weight) < 0.001)
            break;

        ray = Ray(hit.block, hit.blockPosition, reflect(ray.direction, hit.normal));
        float _;
        vec3 diffuse = traceGlobalIllumination(ray, _, 456.56 * (float(steps) + 1), true);
        accumulated += weight * diffuse;

    }

    return accumulated;
}

const int NUM_LAYERS = 5;

vec4 color_layers[NUM_LAYERS];
float depth_layers[NUM_LAYERS];
int active_layers = 0;

void try_insert(vec4 color, float depth) {
    if (color.a == 0.0) {
        return;
    }

    color_layers[active_layers] = color;
    depth_layers[active_layers] = depth;

    int jj = active_layers++;
    int ii = jj - 1;
    while (jj > 0 && depth_layers[jj] > depth_layers[ii]) {
        float depthTemp = depth_layers[ii];
        depth_layers[ii] = depth_layers[jj];
        depth_layers[jj] = depthTemp;

        vec4 colorTemp = color_layers[ii];
        color_layers[ii] = color_layers[jj];
        color_layers[jj] = colorTemp;

        jj = ii--;
    }
}

vec3 blend( vec3 dst, vec4 src ) {
    return (dst * (1.0 - src.a)) + src.rgb;
}

float linearizeDepth(float depth) {
    return (2.0 * near * far) / (far + near - depth * (far - near));
}

void main() {
    // Set the pixel to black in case we don'steps hit anything.
    // Define the ray we need to trace. The origin is always 0, since the blockdata is relative to the player.
    Ray ray = Ray(vec3(-1), 1 - chunkOffset, normalize(rayDir));

    float depth;
    vec3 color = traceReflections(ray, depth);

    if (depth < 0) depth = far;

    vec4 position = projMat * modelViewMat * vec4(normalize(ray.direction) * depth, 1);
    float diffuseDepth = linearizeDepth(sqrt(position.z / position.w));

    color_layers[0] = vec4(color, 1);
    depth_layers[0] = diffuseDepth + 0.0005;
    active_layers = 1;

    try_insert(texture(TranslucentSampler, texCoord), linearizeDepth(texture(TranslucentDepthSampler, texCoord).r));
    try_insert(texture(ItemEntitySampler, texCoord), linearizeDepth(texture(ItemEntityDepthSampler, texCoord).r));
    try_insert(texture(CloudsSampler, texCoord), linearizeDepth(texture(CloudsDepthSampler, texCoord).r));
    try_insert(texture(ParticlesSampler, texCoord), linearizeDepth(texture(ParticlesDepthSampler, texCoord).r));

    vec3 texelAccum = color_layers[0].rgb;
    for ( int ii = 1; ii < active_layers; ++ii ) {
        texelAccum = blend(texelAccum, color_layers[ii]);
    }

    fragColor = vec4(texelAccum.rgb, 1);
}
