#version 150

const float PROJNEAR = 0.05;
const float FPRECISION = 4000000.0;
const float EPSILON = 0.001;
const vec2 VOXEL_STORAGE_RESOLUTION = vec2(1024, 705); 
const float LAYER_SIZE = 88;
const vec2 STORAGE_DIMENSIONS = floor(VOXEL_STORAGE_RESOLUTION / LAYER_SIZE);

in vec4 Position;

uniform mat4 ProjMat;
uniform vec2 OutSize;
uniform sampler2D DiffuseSampler;
uniform sampler2D PreviousFrameDataSampler;
uniform float Time;

out vec2 texCoord;
out vec3 sunDir;
out mat4 projMat;
out mat4 modelViewMat;
out vec3 chunkOffset;
out vec3 rayDir;
out vec3 facingDirection;
out vec2 horizontalFacingDirection;
out float near;
out float far;
out float steveCoordOffset;

vec2 pixelToTexCoord(vec2 pixel) {
    return pixel / (VOXEL_STORAGE_RESOLUTION - 1);
}

vec2 blockToPixel(vec3 position) {
    // The block data is split into layers. Each layer is 60x60 blocks and represents a single y height.
    // Therefore the position inside a layer is just the position of the block on the xz plane relative to the player.
    vec2 inLayerPos = position.xz + LAYER_SIZE / 2;
    // There are 60 layers, we store them in an 8x8 area.
    vec2 layerStart = vec2(mod(position.y + LAYER_SIZE / 2, STORAGE_DIMENSIONS.x), floor((position.y + LAYER_SIZE / 2) / STORAGE_DIMENSIONS.x)) * LAYER_SIZE;
    // The 0.5 offset is to read the center of the "pixels", the +1 offset on the y is to not interfere with the control line
    return layerStart + inLayerPos + vec2(0.5, 1.5);
}

int decodeInt(vec3 ivec) {
    ivec *= 255.0;
    int s = ivec.b >= 128.0 ? -1 : 1;
    return s * (int(ivec.r) + int(ivec.g) * 256 + (int(ivec.b) - 64 + s * 64) * 256 * 256);
}

float decodeFloat(vec3 ivec) {
    return decodeInt(ivec) / FPRECISION;
}

vec2 getControl(int index, vec2 screenSize) {
    return vec2(floor(screenSize.x / 2.0) + float(index) * 2.0 + 0.5, 0.5) / screenSize;
}

void main() {
    vec4 outPos = ProjMat * vec4(Position.xy, 0, 1.0);
    gl_Position = vec4(outPos.xy, 0.2, 1.0);
    texCoord = Position.xy / OutSize;

    //simply decoding all the control data and constructing the sunDir, ProjMat, ModelViewMat

    vec2 start = getControl(0, OutSize);
    vec2 inc = vec2(2.0 / OutSize.x, 0.0);


    // ProjMat constructed assuming no translation or rotation matrices applied (aka no view bobbing).
    projMat = mat4(tan(decodeFloat(texture(DiffuseSampler, start + 3.0 * inc).xyz)), decodeFloat(texture(DiffuseSampler, start + 6.0 * inc).xyz), 0.0, 0.0,
            decodeFloat(texture(DiffuseSampler, start + 5.0 * inc).xyz), tan(decodeFloat(texture(DiffuseSampler, start + 4.0 * inc).xyz)), decodeFloat(texture(DiffuseSampler, start + 7.0 * inc).xyz), decodeFloat(texture(DiffuseSampler, start + 8.0 * inc).xyz),
            decodeFloat(texture(DiffuseSampler, start + 9.0 * inc).xyz), decodeFloat(texture(DiffuseSampler, start + 10.0 * inc).xyz), decodeFloat(texture(DiffuseSampler, start + 11.0 * inc).xyz),  decodeFloat(texture(DiffuseSampler, start + 12.0 * inc).xyz),
            decodeFloat(texture(DiffuseSampler, start + 13.0 * inc).xyz), decodeFloat(texture(DiffuseSampler, start + 14.0 * inc).xyz), decodeFloat(texture(DiffuseSampler, start + 15.0 * inc).xyz), 0.0);

    modelViewMat = mat4(decodeFloat(texture(DiffuseSampler, start + 16.0 * inc).xyz), decodeFloat(texture(DiffuseSampler, start + 17.0 * inc).xyz), decodeFloat(texture(DiffuseSampler, start + 18.0 * inc).xyz), 0.0,
            decodeFloat(texture(DiffuseSampler, start + 19.0 * inc).xyz), decodeFloat(texture(DiffuseSampler, start + 20.0 * inc).xyz), decodeFloat(texture(DiffuseSampler, start + 21.0 * inc).xyz), 0.0,
            decodeFloat(texture(DiffuseSampler, start + 22.0 * inc).xyz), decodeFloat(texture(DiffuseSampler, start + 23.0 * inc).xyz), decodeFloat(texture(DiffuseSampler, start + 24.0 * inc).xyz), 0.0,
            0.0, 0.0, 0.0, 1.0);

    near = PROJNEAR;
    far = projMat[3][2] * near / (projMat[3][2] + 2.0 * near);

    chunkOffset = vec3(
            decodeFloat(texture(DiffuseSampler, start + 100 * inc).xyz),
            decodeFloat(texture(DiffuseSampler, start + 101 * inc).xyz),
            decodeFloat(texture(DiffuseSampler, start + 102 * inc).xyz)
    );

    vec3 prevChunkOffset = vec3(
        decodeFloat(texture(PreviousFrameDataSampler, start + 100 * inc).xyz),
        decodeFloat(texture(PreviousFrameDataSampler, start + 101 * inc).xyz),
        decodeFloat(texture(PreviousFrameDataSampler, start + 102 * inc).xyz)
    );

    vec3 movement = abs(chunkOffset - prevChunkOffset);

    float fov = atan(1 / projMat[1][1]);

    sunDir = normalize((inverse(modelViewMat) * vec4(
            decodeFloat(texture(DiffuseSampler, start).xyz),
            decodeFloat(texture(DiffuseSampler, start + inc).xyz),
            decodeFloat(texture(DiffuseSampler, start + 2.0 * inc).xyz),
            1)).xyz);

    mat4 projInv = inverse(projMat * modelViewMat);
    rayDir = (projInv * vec4(outPos.xy * (far - near), far + near, far - near)).xyz;
    facingDirection = (vec4(0, 0, -1, 0) * modelViewMat).xyz;
    horizontalFacingDirection = normalize(facingDirection.xz);

    steveCoordOffset = 0.0;
    if (movement.x + movement.z > EPSILON) {
        steveCoordOffset += (floor(fract(Time * 2) / 0.5) + 1) / 6;
    }
    if (chunkOffset.y > 0.7) {
        vec3 rawData = texture(DiffuseSampler, pixelToTexCoord(blockToPixel(vec3(-1, -3, -1)))).rgb;
        steveCoordOffset += 0.5 * step(rawData.x + rawData.y + rawData.z, 3.0 - EPSILON);
    }
}