#version 150

// I'm targeting anything beyond 1024x768, without the taskbar, that let's us use 1024x705 pixels
// This should just barely fit 8, 88 deep layers (8 * 88 + 1 control line = 705)
// I want to keep the stored layers square, therefore I only use 88 * 11 = 968 pixels horizontally
const vec2 VOXEL_STORAGE_RESOLUTION = vec2(1024, 705);
const float LAYER_SIZE = 88;

const float EPSILON = 0.01;
const float FPRECISION = 4000000.0;
const float NUMCONTROLS = 200;
const float THRESH = 0.5;
const float PROJNEAR = 0.05;

const vec2 STORAGE_DIMENSIONS = floor(VOXEL_STORAGE_RESOLUTION / LAYER_SIZE);

int imod(int val, int m) {
    return val - val / m * m;
}

vec2 pixelToTexCoord(vec2 pixel) {
    return pixel / (VOXEL_STORAGE_RESOLUTION - 1);
}

vec2 blockToPixel(vec3 position) {
    // The block data is split into layers. Each layer is 60x60 blocks and represents a single y height.
    // Therefore the position inside a layer is just the position of the block on the xz plane relative to the player.
    vec2 inLayerPos = position.xz + LAYER_SIZE / 2;
    // There are 60 layers, we store them in an 8x8 area.
    vec2 layerStart = vec2(mod(position.y + LAYER_SIZE / 2, STORAGE_DIMENSIONS.x), floor((position.y + LAYER_SIZE / 2) / STORAGE_DIMENSIONS.x)) * LAYER_SIZE;
    // We offset it by 1 pixel in the y direction, because we store the matrices there
    return layerStart + inLayerPos + vec2(0, 1);
}

vec2 blockToTexCoord(vec3 position) {
    return pixelToTexCoord(blockToPixel(position));
}

vec3 encodeInt(int i) {
    int s = int(i < 0) * 128;
    i = abs(i);
    int r = imod(i, 256);
    i = i / 256;
    int g = imod(i, 256);
    i = i / 256;
    int b = imod(i, 128);
    return vec3(float(r) / 255.0, float(g) / 255.0, float(b + s) / 255.0);
}

int decodeInt(vec3 ivec) {
    ivec *= 255.0;
    int s = ivec.b >= 128.0 ? -1 : 1;
    return s * (int(ivec.r) + int(ivec.g) * 256 + (int(ivec.b) - 64 + s * 64) * 256 * 256);
}

vec3 encodeFloat(float i) {
    return encodeInt(int(i * FPRECISION));
}

float decodeFloat(vec3 ivec) {
    return decodeInt(ivec) / FPRECISION;
}

// returns control pixel index or -1 if not control
int inControl(vec2 screenCoord, float screenWidth) {
    if (screenCoord.y < 1) {
        float index = floor(screenWidth / 2.0) + THRESH / 2.0;
        index = (screenCoord.x - index) / 2.0;
        if (fract(index) < THRESH && index < NUMCONTROLS && index >= 0) {
            return int(index);
        }
    }
    return -1;
}

int inControl(vec2 screenCoord, vec4 glpos) {
    if (screenCoord.y < 1.0) {
        float screenWidth = round(screenCoord.x * 2.0 / (glpos.x / glpos.w + 1.0));
        float index = floor(screenWidth / 2.0) + THRESH / 2.0;
        index = (screenCoord.x - index) / 2.0;
        if (fract(index) < THRESH && index < NUMCONTROLS && index >= 0) {
            return int(index);
        }
    }
    return -1;
}