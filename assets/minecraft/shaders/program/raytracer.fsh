#version 150

const float PI = 3.141592654;
const float EPSILON = 0.001;
const int MAX_STEPS = 100;
const int MAX_BOUNCES = 40;
const vec3 SKY_COLOR = vec3(0.4, 0.6, 1);
const vec3 SUN = normalize(vec3(1, 3, 2));
const float AREA_SIZE = 60;

uniform sampler2D DiffuseSampler;
uniform sampler2D AtlasSampler;
uniform sampler2D IORSampler;
uniform vec2 OutSize;

in vec2 texCoord;
in vec2 oneTexel;
in vec3 sunDir;
in float near;
in float far;
in mat4 projMat;
in mat4 modelViewMat;
in mat3 cameraMatrix;
in vec3 chunkOffset;
in float fov;

out vec4 fragColor;

struct Ray {
    // Index of the block the ray is in.
    vec3 currentBlock;
    // Position of the ray inside the block.
    vec3 blockPosition;
    // The direction of the ray
    vec3 direction;
};

struct Hit {
    float t;
    vec3 block;
    vec3 blockPosition;
    vec3 normal;
    vec4 voxelData;
    vec2 texCoord;
};

// No moj_import here

vec2 pixelToTexCoord(vec2 pixel, vec2 screenSize) {
    return pixel / (screenSize - 1);
}

vec2 blockToPixel(vec3 position) {
    // The block data is split into layers. Each layer is 60x60 blocks and represents a single y height.
    // Therefore the position inside a layer is just the position of the block on the xz plane relative to the player.
    vec2 inLayerPos = position.xz + AREA_SIZE / 2;
    // There are 60 layers, we store them in an 8x8 area.
    vec2 layerStart = vec2(mod(position.y + AREA_SIZE / 2, 8), floor((position.y + AREA_SIZE / 2) / 8)) * AREA_SIZE;
    return layerStart + inLayerPos + vec2(0, 1);
}

vec4 getBlock(vec3 position) {
    if (any(greaterThan(abs(position), vec3(AREA_SIZE / 2 - 1)))) {
        return vec4(1);
    }
    vec2 texCoord = pixelToTexCoord(blockToPixel(position), OutSize);
    return texture(DiffuseSampler, texCoord);
}

int decodeInt(vec3 ivec) {
    ivec *= 255.0;
    int s = ivec.b >= 128.0 ? -1 : 1;
    return s * (int(ivec.r) + int(ivec.g) * 256 + (int(ivec.b) - 64 + s * 64) * 256 * 256);
}

vec2 getControl(int index, vec2 screenSize) {
    return vec2(floor(screenSize.x / 2.0) + float(index) * 2.0 + 0.5, 0.5) / screenSize;
}

Hit trace(Ray ray, int maxSteps) {
    float totalT = 0;
    // Cap the amount of steps we take to make sure no ifinite loop happens.
    for (int i = 0; i < maxSteps; i++) {
        // The world is divided into blocks, so we can use a simplified tracing algorithm where we always go to the
        // nearest block boundary. This can be very easily calculated by dividing the signed distance to the six walls
        // of the current block by the signed components of the ray's direction. This way we get the size of the step
        // we need to take to reach a wall in that direction. This could be faster by precomputing 1 divided by the
        // components of the ray's direction, but I'll keep it simple here. Faster algorithms also exist.

        // The steps in each direction:
        vec3 normalizedDirection = ray.direction / abs(ray.direction);
        ivec3 iNormalizedDirection = ivec3(int(round(normalizedDirection.x)), int(round(normalizedDirection.y)), int(round(normalizedDirection.z)));
        vec3 steps = ((normalizedDirection + 1) / 2 - ray.blockPosition) / ray.direction;
        float t = min(min(steps.x, steps.y), steps.z);

        ray.blockPosition += t * ray.direction;
        totalT += t;

        // We select the smallest of the steps and update the current block and block position.
        vec3 normal;
        vec2 texCoord;
        if (abs(t - steps.x) < EPSILON) {
            normal = vec3(-normalizedDirection.x, 0, 0);
            ray.currentBlock.x += iNormalizedDirection.x;
            ray.blockPosition.x = (1 - iNormalizedDirection.x) / 2;
            texCoord = ray.blockPosition.zy;
        } else if (abs(t - steps.y) < EPSILON) {
            normal = vec3(0, -normalizedDirection.y, 0);
            ray.currentBlock.y += iNormalizedDirection.y;
            ray.blockPosition.y = (1 - iNormalizedDirection.y) / 2;
            texCoord = ray.blockPosition.xz;
        } else {
            normal = vec3(0, 0, -normalizedDirection.z);
            ray.currentBlock.z += iNormalizedDirection.z;
            ray.blockPosition.z = (1 - iNormalizedDirection.z) / 2;
            texCoord = ray.blockPosition.xy;
        }
        // We can now query if there's a block at the current position.
        vec4 voxelData = getBlock(ray.currentBlock);
        // If it's a block (it's not white), we stop and draw to the screen.
        if (length(voxelData - 1) > EPSILON) {
            return Hit(totalT, ray.currentBlock, ray.blockPosition, normal, voxelData, texCoord);
        }
    }
    Hit hit;
    hit.t = -1;
    return hit;
}

vec3 fresnel(vec3 F0, float cosTheta) {
    return F0 + (1 - F0) * pow(max(1 - cosTheta, 0), 5);
}

void main() {
    // Set the pixel to black in case we don'steps hit anything.
    fragColor = vec4(SKY_COLOR, 1);

    // Define the ray we need to trace. The origin is always 0, since the blockdata is relative to the player.
    Ray ray = Ray(
        vec3(-1, -1, -1),
        1 - chunkOffset,
        normalize(vec3((texCoord * 2 - 1) * OutSize / OutSize.y, tan(2 * fov)) * cameraMatrix)
    );

    Hit hit = trace(ray, MAX_STEPS);
    vec3 weight = vec3(1);
    for (int i = 0; i < MAX_BOUNCES; i++) {

        if (hit.t < 0) {
            fragColor.rgb = SKY_COLOR * weight;
            break;
        }
        int data = decodeInt(hit.voxelData.rgb);

        vec2 texCoord = (vec2(data >> 6, data & 63) + hit.texCoord) / 64;
        vec3 F0 = texture(IORSampler, texCoord).rgb;
        // Probably should be replaced by metallicity
        if (dot(F0, F0) > 0) {
            // Metallic
            if (i == MAX_BOUNCES - 1) {
                // If we reached the end, just draw the reflectance factor
                // Not that elegant, but works
                fragColor.rgb = F0 * weight;
            } else {
                // Otherwise bounce the ray back
                weight *= fresnel(F0, dot(-ray.direction, hit.normal));
                ray = Ray(hit.block, hit.blockPosition, reflect(ray.direction, hit.normal));
                hit = trace(ray, MAX_STEPS);
            }
        } else {
            // Diffuse
            // Self shadow with the minecraft numbers
            float diffuse = max(dot(hit.normal, SUN), 0) * 0.6 + 0.4;
            // Shadow ray
            Hit shadowHit = trace(Ray(hit.block, hit.blockPosition, SUN), MAX_STEPS);
            if (shadowHit.t > 0) {
                diffuse = 0.4;
            }
            fragColor = vec4(texture(AtlasSampler, texCoord).rgb * weight * diffuse, 1);
            break;
        }
    }

    //fragColor = mix(fragColor, texture(DiffuseSampler, texCoord), 0.5);
}
