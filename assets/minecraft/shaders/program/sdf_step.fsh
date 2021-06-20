#version 150

const vec2 VOXEL_STORAGE_RESOLUTION = vec2(1024, 705);
const float LAYER_SIZE = 88;
const vec2 STORAGE_DIMENSIONS = floor(VOXEL_STORAGE_RESOLUTION / LAYER_SIZE);

in vec2 texCoord;

uniform sampler2D DiffuseSampler;

out vec4 fragColor;

vec2 blockToTexCoord(vec3 position) {
    position += LAYER_SIZE / 2;
    vec2 inLayerPos = position.xz;
    vec2 layerStart = vec2(mod(position.y, STORAGE_DIMENSIONS.y), floor(position.y / STORAGE_DIMENSIONS.y)) * LAYER_SIZE;
    return (layerStart + inLayerPos + vec2(0.5, 1.5)) / (VOXEL_STORAGE_RESOLUTION - 1);
}

vec3 texCoordToBlock(vec2 texCoord) {
    vec3 position = vec3(0);

    texCoord = texCoord * (VOXEL_STORAGE_RESOLUTION - 1) - vec2(0.5, 1.5);

    position.xz = mod(texCoord, vec2(LAYER_SIZE));
    vec2 startPos = floor(texCoord / LAYER_SIZE);
    position.y = startPos.y * STORAGE_DIMENSIONS.y + startPos.x;

    return position - LAYER_SIZE / 2;
}

void main() {
    vec2 uv = (floor(texCoord * (VOXEL_STORAGE_RESOLUTION - 1)) + 0.5) / (VOXEL_STORAGE_RESOLUTION - 1);
    vec3 blockPos = texCoordToBlock(uv);

    float newVal =       texture(DiffuseSampler, blockToTexCoord(blockPos + vec3( 0,  0,  0))).r - 1 / 255.0;
    newVal = min(newVal, texture(DiffuseSampler, blockToTexCoord(blockPos + vec3( 1,  0,  0))).r);
    newVal = min(newVal, texture(DiffuseSampler, blockToTexCoord(blockPos + vec3(-1,  0,  0))).r);
    newVal = min(newVal, texture(DiffuseSampler, blockToTexCoord(blockPos + vec3( 0,  1,  0))).r);
    newVal = min(newVal, texture(DiffuseSampler, blockToTexCoord(blockPos + vec3( 0, -1,  0))).r);
    newVal = min(newVal, texture(DiffuseSampler, blockToTexCoord(blockPos + vec3( 0,  0,  1))).r);
    newVal = min(newVal, texture(DiffuseSampler, blockToTexCoord(blockPos + vec3( 0,  0, -1))).r);
    fragColor = vec4(newVal + 1 / 255.0, 0, 0, 1);
}