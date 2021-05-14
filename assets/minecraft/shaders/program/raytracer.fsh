#version 150

const float PI = 3.141592654;
const float EPSILON = 0.00001;
const int MAX_STEPS = 100;
const int MAX_BOUNCES = 40;
const vec3 SUN_COLOR = 1.0 * vec3(1.0, 0.95, 0.8);
const vec3 SKY_COLOR = 0.5 * vec3(0.2, 0.35, 0.5);
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
uniform sampler2D IORSampler;
uniform sampler2D SteveSampler;
uniform sampler2D EmissionSampler;
uniform sampler2D PreviousFrameSampler;
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

    blockData.type = 1;
    blockData.blockTexCoord = (vec2(data >> 6, data & 63) + texCoord) / 64;
    blockData.albedo = texture(AtlasSampler, blockData.blockTexCoord).rgb;
    blockData.F0 = texture(IORSampler, blockData.blockTexCoord).rgb;
    blockData.emission = texture(EmissionSampler, blockData.blockTexCoord);
    return blockData;
}

vec2 getControl(int index, vec2 screenSize) {
    return vec2(floor(screenSize.x / 2.0) + float(index) * 2.0 + 0.5, 0.5) / screenSize;
}

float intersectCircle(vec2 origin, vec2 direction, vec2 center, float radius) {
    float a = dot(direction, direction);
    float b = 2 * dot(origin, direction) - 2 * dot(center, direction);
    float c = dot(origin, origin) + dot(center, center) - 2 * dot(origin, center) - radius * radius;

    float disc = b * b - 4 * a * c;
    if (disc < 0) {
        return -1;
    }

    float t1 = (-b + sqrt(disc)) / 2 / a;
    float t2 = (-b - sqrt(disc)) / 2 / a;

    if (t1 <= 0 && t2 <= 0) {
        return -1;
    } else if (t2 <= 0) {
        return t1;
    } else if (t1 <= 0) {
        return t2;
    } else {
        return min(t1, t2);
    }
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

vec3 fresnel(vec3 F0, float cosTheta) {
    return F0 + (1 - F0) * pow(max(1 - cosTheta, 0), 5);
}

Hit trace(Ray ray, int maxSteps, bool reflected) {
    float totalT = 0;
    vec3 signedDirection = sign(ray.direction);
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
                hit.texCoord = vec2(
                    (length(thingHitPos.xz) + 0.56) * 1.8 / 2,
                    0.10 - (thingHitPos.y) / 2
                );

                vec3 thingColor = texture(SteveSampler, hit.texCoord).rgb;
                if (thingColor.x + thingColor.y + thingColor.z > 0) {
                    return hit;
                }
            }
        }


        vec3 steps = (signedDirection * 0.5 + 0.5 - ray.blockPosition) / ray.direction;
        // The steps in each direction:
        float t = min(min(steps.x, steps.y), steps.z);

        ray.blockPosition += t * ray.direction;
        totalT += t;

        // We select the smallest of the steps and update the current block and block position.
        vec3 normal;
        vec2 texCoord;
        if (steps.x - t < EPSILON) {
            normal = vec3(-signedDirection.x, 0, 0);
            ray.currentBlock.x += signedDirection.x;
            ray.blockPosition.x = (1 - signedDirection.x) / 2;
            texCoord = ray.blockPosition.zy;
        } else if (steps.y - t < EPSILON) {
            normal = vec3(0, -signedDirection.y, 0);
            ray.currentBlock.y += signedDirection.y;
            ray.blockPosition.y = (1 - signedDirection.y) / 2;
            texCoord = ray.blockPosition.xz;
        } else {
            normal = vec3(0, 0, -signedDirection.z);
            ray.currentBlock.z += signedDirection.z;
            ray.blockPosition.z = (1 - signedDirection.z) / 2;
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

BounceHit traceBounces(Ray ray, int maxBounces, int maxStepPerBounce, vec3 skyColor, out float depth) {
    vec3 weight = vec3(1);
    BounceHit res;
    res.color = vec3(0);

    Hit hit = trace(ray, maxStepPerBounce, false);
    depth = hit.t;
    for (int i = 0; i < maxBounces; i++) {
        if (hit.t > 900) {
            res.color += texture(SteveSampler, hit.texCoord).rgb * weight;
            res.finalDirection = ray.direction;
            res.t = hit.t;
            return res;
        } else if (hit.t < 0) {
            res.color += skyColor * weight;
            res.finalDirection = ray.direction;
            res.t = hit.t;
            return res;
        }

        vec3 F0 = hit.blockData.F0;
        // Probably should be replaced by metallicity
        if (dot(F0, F0) > 0) {
            // Metallic
            if (i == maxBounces - 1) {
                // If we reached the end, just draw the reflectance factor
                // Not that elegant, but works
                res.color += F0 * weight;
                res.finalDirection = ray.direction;
                res.t = hit.t;
                res.block = hit.block;
                res.blockPosition = hit.blockPosition;
                res.normal = hit.normal;
                return res;
            } else {
                // Otherwise bounce the ray back
                weight *= fresnel(F0, dot(-ray.direction, hit.normal));
                ray = Ray(hit.block, hit.blockPosition, reflect(ray.direction, hit.normal));
                hit = trace(ray, maxStepPerBounce, true);
            }
        } else {
            // Diffuse
            res.color += hit.blockData.albedo * weight;
            res.finalDirection = ray.direction;
            res.t = hit.t;
            res.block = hit.block;
            res.blockPosition = hit.blockPosition;
            res.normal = hit.normal;
            return res;
        }
    }
    res.finalDirection = ray.direction;
    res.t = hit.t;
    res.block = hit.block;
    res.blockPosition = hit.blockPosition;
    res.normal = hit.normal;
    return res;
}

vec3 randomDirection(vec2 coords, vec3 normal, float seed) {
    uvec3 p = uvec3(coords * 5000, (Time + seed) * 60);
    vec3 v = hash(p);
    float angle = 2 * PI * v.x;
    float u = 2 * v.y - 1;
    return normalize(normal + vec3(sqrt(1 - u * u) * vec2(cos(angle), sin(angle)), u));
}

vec3 traceScene(Ray ray, int maxBounces, int maxStepPerBounce, out float depth) {
    vec3 accumulated = vec3(0);
    vec3 weight = vec3(1);

    Hit hit;
    float totalT = 0;
    for (int step = 0; step < 3; step++) {
        hit = trace(ray, step == 0 ? maxStepPerBounce : 16, false);
        if (step == 0) {
            depth = hit.t;
        }
        if (hit.t < EPSILON) {
            accumulated += SKY_COLOR * weight;
            break;
        }
        totalT += hit.t;

        weight *= hit.blockData.albedo;

        if (hit.blockData.emission.a > 0) {
            accumulated += hit.blockData.emission.rgb * MAX_EMISSION_STRENGTH * weight;
        }

        // Sun contribution
        Hit sunShadowHit = trace(Ray(hit.block, hit.blockPosition, randomDirection(texCoord, sunDir * 50, 823.375)), maxStepPerBounce, false);
        accumulated += max(dot(sunDir, hit.normal), 0) * (sunShadowHit.t > EPSILON ? 0 : 1) * SUN_COLOR * weight;

        // ""Ambient""/sky contribution
        vec3 skyRayDirection = randomDirection(texCoord, hit.normal, float(step) + 7.41);
        Hit skyShadowHit = trace(Ray(hit.block, hit.blockPosition, skyRayDirection), maxStepPerBounce, false);
        accumulated += SKY_COLOR * (skyShadowHit.t > EPSILON ? 0.4 : 1) * weight;

        vec3 newDir = randomDirection(texCoord, hit.normal, float(step) * 754.54);
        ray = Ray(hit.block, hit.blockPosition, newDir);
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
    vec3 color = traceScene(ray, MAX_BOUNCES, MAX_STEPS, depth);

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

    vec4 prevFrameColor = texture(PreviousFrameSampler, texCoord);

    //fragColor = vec4(depth, texture( TranslucentDepthSampler, texCoord ).r, 0, 1);//vec4( texelAccum.rgb, 1.0 );
    //fragColor = vec4(mix(prevFrameColor.rgb, texelAccum.rgb, 0.05), 1.0);
    fragColor = vec4(texelAccum.rgb, 1);
}
