#version 420

#include<post/renderscale.glsl>

const float FPRECISION = 4000000.0;

in vec4 Position;

uniform vec2 InSize;
uniform sampler2D DataSampler;
uniform sampler2D PrevDataSampler;

out vec2 texCoord;
out mat4 projInv;
out mat3 modelViewMat;
out vec3 cameraOffset;
out mat4 prevProjMat;
out mat3 prevModelViewMat;
out float renderScale;

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
    vec4 outPos = OFFSETS[gl_VertexID];
    renderScale = getRenderScale(DataSampler);
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
    
    prevProjMat = mat4(
        tan(decodeFloat(texture(PrevDataSampler, start + 3.0 * inc).xyz)), decodeFloat(texture(PrevDataSampler, start + 6.0 * inc).xyz), 0.0, 0.0,
        decodeFloat(texture(PrevDataSampler, start + 5.0 * inc).xyz), tan(decodeFloat(texture(PrevDataSampler, start + 4.0 * inc).xyz)), decodeFloat(texture(PrevDataSampler, start + 7.0 * inc).xyz), decodeFloat(texture(PrevDataSampler, start + 8.0 * inc).xyz),
        decodeFloat(texture(PrevDataSampler, start + 9.0 * inc).xyz), decodeFloat(texture(PrevDataSampler, start + 10.0 * inc).xyz), decodeFloat(texture(PrevDataSampler, start + 11.0 * inc).xyz),  decodeFloat(texture(PrevDataSampler, start + 12.0 * inc).xyz),
        decodeFloat(texture(PrevDataSampler, start + 13.0 * inc).xyz), decodeFloat(texture(PrevDataSampler, start + 14.0 * inc).xyz), decodeFloat(texture(PrevDataSampler, start + 15.0 * inc).xyz), 0.0
    );

    modelViewMat = mat3(
        decodeFloat(texture(DataSampler, start + 16.0 * inc).xyz), decodeFloat(texture(DataSampler, start + 17.0 * inc).xyz), decodeFloat(texture(DataSampler, start + 18.0 * inc).xyz),
        decodeFloat(texture(DataSampler, start + 19.0 * inc).xyz), decodeFloat(texture(DataSampler, start + 20.0 * inc).xyz), decodeFloat(texture(DataSampler, start + 21.0 * inc).xyz),
        decodeFloat(texture(DataSampler, start + 22.0 * inc).xyz), decodeFloat(texture(DataSampler, start + 23.0 * inc).xyz), decodeFloat(texture(DataSampler, start + 24.0 * inc).xyz)
    );

    prevModelViewMat = mat3(
        decodeFloat(texture(PrevDataSampler, start + 16.0 * inc).xyz), decodeFloat(texture(PrevDataSampler, start + 17.0 * inc).xyz), decodeFloat(texture(PrevDataSampler, start + 18.0 * inc).xyz),
        decodeFloat(texture(PrevDataSampler, start + 19.0 * inc).xyz), decodeFloat(texture(PrevDataSampler, start + 20.0 * inc).xyz), decodeFloat(texture(PrevDataSampler, start + 21.0 * inc).xyz),
        decodeFloat(texture(PrevDataSampler, start + 22.0 * inc).xyz), decodeFloat(texture(PrevDataSampler, start + 23.0 * inc).xyz), decodeFloat(texture(PrevDataSampler, start + 24.0 * inc).xyz)
    );

    vec3 chunkOffset = vec3(
        decodeFloat(texelFetch(DataSampler, ivec2(0, 0), 0).xyz),
        decodeFloat(texelFetch(DataSampler, ivec2(1, 0), 0).xyz),
        decodeFloat(texelFetch(DataSampler, ivec2(2, 0), 0).xyz)
    ) * 16.0;

    vec3 prevChunkOffset = vec3(
        decodeFloat(texelFetch(PrevDataSampler, ivec2(0, 0), 0).xyz),
        decodeFloat(texelFetch(PrevDataSampler, ivec2(1, 0), 0).xyz),
        decodeFloat(texelFetch(PrevDataSampler, ivec2(2, 0), 0).xyz)
    ) * 16.0;
    
    cameraOffset = mod(chunkOffset - prevChunkOffset + 24.0, 16.0) - 8.0;
    
    projInv = inverse(projMat);
}