#version 420

#include<post/renderscale.glsl>

const float PROJNEAR = 0.05;
const float FPRECISION = 4000000.0;

in vec4 Position;

uniform vec2 InSize;
uniform sampler2D DataSampler;

out vec2 texCoord;
out float renderScale;
out float near;
out float far;

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

vec4[] OFFSETS = vec4[](
    vec4(-1, -1, 0, 1),
    vec4(1, -1, 0, 1),
    vec4(1, 1, 0, 1),
    vec4(-1, 1, 0, 1)
);

void main() {
    renderScale = getRenderScale(DataSampler);
    vec4 outPos = OFFSETS[gl_VertexID];
    gl_Position = scaleClipPos(outPos, renderScale);
    texCoord = outPos.xy * 0.5 + 0.5;

    //simply decoding all the control data and constructing the sunDir, ProjMat, ModelViewMat
    vec2 dataTextureSize = textureSize(DataSampler, 0);
    vec2 start = getControl(0, dataTextureSize);
    vec2 inc = vec2(2.0 / dataTextureSize.x, 0.0);

    // ProjMat constructed assuming no translation or rotation matrices applied (aka no view bobbing).
    mat4 projMat = mat4(
        tan(decodeFloat(texture(DataSampler, start + 3.0 * inc).xyz)), decodeFloat(texture(DataSampler, start + 6.0 * inc).xyz), 0.0, 0.0,
        decodeFloat(texture(DataSampler, start + 5.0 * inc).xyz), tan(decodeFloat(texture(DataSampler, start + 4.0 * inc).xyz)), decodeFloat(texture(DataSampler, start + 7.0 * inc).xyz), decodeFloat(texture(DataSampler, start + 8.0 * inc).xyz),
        decodeFloat(texture(DataSampler, start + 9.0 * inc).xyz), decodeFloat(texture(DataSampler, start + 10.0 * inc).xyz), decodeFloat(texture(DataSampler, start + 11.0 * inc).xyz),  decodeFloat(texture(DataSampler, start + 12.0 * inc).xyz),
        decodeFloat(texture(DataSampler, start + 13.0 * inc).xyz), decodeFloat(texture(DataSampler, start + 14.0 * inc).xyz), decodeFloat(texture(DataSampler, start + 15.0 * inc).xyz), 0.0
    );

    near = PROJNEAR;
    far = projMat[3][2] * near / (projMat[3][2] + 2.0 * near);
}