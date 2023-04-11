#version 420

#include<constants.glsl>
#include<post/renderscale.glsl>

const float PROJNEAR = 0.05;
const float FPRECISION = 4000000.0;

in vec4 Position;

uniform vec2 InSize;
uniform sampler2D DataSampler;
uniform sampler2D CounterSampler;
uniform sampler2D SunSampler;
uniform sampler2D Atlas;

out vec2 texCoord;
out vec3 sunDir;
out mat4 projMat;
out mat3 modelViewMat;
out vec3 chunkOffset;
out vec3 rayDir;
out float near;
out float far;
out mat4 projInv;
flat out uint frame;
out vec3 sunColor;
out float renderScale;
out vec3 steveDirection;
flat out ivec2 atlasSize;

uint readCounter() {
    uvec4 raw = uvec4(texelFetch(CounterSampler, ivec2(0), 0) * 255.0);
    return (raw.z << 16u) | (raw.y << 8u) | raw.x;
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

vec4[] OFFSETS = vec4[](
    vec4(-1, -1, 0, 1),
    vec4(1, -1, 0, 1),
    vec4(1, 1, 0, 1),
    vec4(-1, 1, 0, 1)
);

void main() {
    vec4 outPos = OFFSETS[gl_VertexID];
    texCoord = outPos.xy * 0.5 + 0.5;
    
    vec2 start = getControl(0, InSize);
    vec2 inc = vec2(2.0 / InSize.x, 0.0);
    
    renderScale = getRenderScale(DataSampler);
    gl_Position = scaleClipPos(outPos, renderScale);

    projMat = mat4(
        tan(decodeFloat(texture(DataSampler, start + 3.0 * inc).xyz)), decodeFloat(texture(DataSampler, start + 6.0 * inc).xyz), 0.0, 0.0,
        decodeFloat(texture(DataSampler, start + 5.0 * inc).xyz), tan(decodeFloat(texture(DataSampler, start + 4.0 * inc).xyz)), decodeFloat(texture(DataSampler, start + 7.0 * inc).xyz), decodeFloat(texture(DataSampler, start + 8.0 * inc).xyz),
        decodeFloat(texture(DataSampler, start + 9.0 * inc).xyz), decodeFloat(texture(DataSampler, start + 10.0 * inc).xyz), decodeFloat(texture(DataSampler, start + 11.0 * inc).xyz),  decodeFloat(texture(DataSampler, start + 12.0 * inc).xyz),
        decodeFloat(texture(DataSampler, start + 13.0 * inc).xyz), decodeFloat(texture(DataSampler, start + 14.0 * inc).xyz), decodeFloat(texture(DataSampler, start + 15.0 * inc).xyz), 0.0
    );

    modelViewMat = mat3(
        decodeFloat(texture(DataSampler, start + 16.0 * inc).xyz), decodeFloat(texture(DataSampler, start + 17.0 * inc).xyz), decodeFloat(texture(DataSampler, start + 18.0 * inc).xyz),
        decodeFloat(texture(DataSampler, start + 19.0 * inc).xyz), decodeFloat(texture(DataSampler, start + 20.0 * inc).xyz), decodeFloat(texture(DataSampler, start + 21.0 * inc).xyz),
        decodeFloat(texture(DataSampler, start + 22.0 * inc).xyz), decodeFloat(texture(DataSampler, start + 23.0 * inc).xyz), decodeFloat(texture(DataSampler, start + 24.0 * inc).xyz)
    );
    
    vec3 forward = transpose(modelViewMat)[2];
    vec3 up = transpose(modelViewMat)[1];
    if (forward.y > 0.99) {
        steveDirection = up;
    } else {
        steveDirection = normalize(vec3(forward.x, 0.0, forward.z));
    }

    near = PROJNEAR;
    far = projMat[3][2] * near / (projMat[3][2] + 2.0 * near);

    chunkOffset = vec3(
        decodeFloat(texelFetch(DataSampler, ivec2(0, 0), 0).xyz),
        decodeFloat(texelFetch(DataSampler, ivec2(1, 0), 0).xyz),
        decodeFloat(texelFetch(DataSampler, ivec2(2, 0), 0).xyz)
    ) * 16.0;

    sunDir = vec3(
        decodeFloat(texture(DataSampler, start).xyz),
        decodeFloat(texture(DataSampler, start + inc).xyz),
        decodeFloat(texture(DataSampler, start + 2.0 * inc).xyz)
    ) * mat3(modelViewMat);
    
    float time = atan(sunDir.y, sunDir.x) / PI / 2.0 - 1.0 / 24.0;
    sunColor = texture(SunSampler, vec2(time, 0.0)).rgb;

    sunDir = normalize(sunDir);

    projInv = inverse(projMat);
    rayDir = (projInv * vec4(outPos.xy * (far - near), far + near, far - near)).xyz;
    frame = readCounter();

    atlasSize = textureSize(Atlas, 0) / 2;
}