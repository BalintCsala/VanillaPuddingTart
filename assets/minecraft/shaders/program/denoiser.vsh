#version 150

const float PROJNEAR = 0.05;
const float FPRECISION = 4000000.0;
const float EPSILON = 0.001;

in vec4 Position;

uniform mat4 ProjMat;
uniform vec2 OutSize;
uniform sampler2D CurrentFrameDataSampler;
uniform sampler2D PreviousFrameDataSampler;

out vec2 texCoord;
out vec2 oneTexel;
out mat4 currProjMat;
out mat4 currModelViewMat;
out mat4 prevProjMat;
out mat4 prevModelViewMat;
out mat4 projInv;
out vec3 rayDir;
out float near;
out float far;
out vec3 prevPosition;

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
    oneTexel = 1.0 / OutSize;



    vec2 start = getControl(0, OutSize);
    vec2 inc = vec2(2.0 / OutSize.x, 0.0);

    currProjMat = mat4(
        tan(decodeFloat(texture(CurrentFrameDataSampler, start + 3.0 * inc).xyz)), decodeFloat(texture(CurrentFrameDataSampler, start + 6.0 * inc).xyz), 0.0, 0.0,
        decodeFloat(texture(CurrentFrameDataSampler, start + 5.0 * inc).xyz), tan(decodeFloat(texture(CurrentFrameDataSampler, start + 4.0 * inc).xyz)), decodeFloat(texture(CurrentFrameDataSampler, start + 7.0 * inc).xyz), decodeFloat(texture(CurrentFrameDataSampler, start + 8.0 * inc).xyz),
        decodeFloat(texture(CurrentFrameDataSampler, start + 9.0 * inc).xyz), decodeFloat(texture(CurrentFrameDataSampler, start + 10.0 * inc).xyz), decodeFloat(texture(CurrentFrameDataSampler, start + 11.0 * inc).xyz),  decodeFloat(texture(CurrentFrameDataSampler, start + 12.0 * inc).xyz),
        decodeFloat(texture(CurrentFrameDataSampler, start + 13.0 * inc).xyz), decodeFloat(texture(CurrentFrameDataSampler, start + 14.0 * inc).xyz), decodeFloat(texture(CurrentFrameDataSampler, start + 15.0 * inc).xyz), 0.0
    );

    currModelViewMat = mat4(
        decodeFloat(texture(CurrentFrameDataSampler, start + 16.0 * inc).xyz), decodeFloat(texture(CurrentFrameDataSampler, start + 17.0 * inc).xyz), decodeFloat(texture(CurrentFrameDataSampler, start + 18.0 * inc).xyz), 0.0,
        decodeFloat(texture(CurrentFrameDataSampler, start + 19.0 * inc).xyz), decodeFloat(texture(CurrentFrameDataSampler, start + 20.0 * inc).xyz), decodeFloat(texture(CurrentFrameDataSampler, start + 21.0 * inc).xyz), 0.0,
        decodeFloat(texture(CurrentFrameDataSampler, start + 22.0 * inc).xyz), decodeFloat(texture(CurrentFrameDataSampler, start + 23.0 * inc).xyz), decodeFloat(texture(CurrentFrameDataSampler, start + 24.0 * inc).xyz), 0.0,
        0.0, 0.0, 0.0, 1.0
    );

    prevProjMat = mat4(
        tan(decodeFloat(texture(PreviousFrameDataSampler, start + 3.0 * inc).xyz)), decodeFloat(texture(PreviousFrameDataSampler, start + 6.0 * inc).xyz), 0.0, 0.0,
        decodeFloat(texture(PreviousFrameDataSampler, start + 5.0 * inc).xyz), tan(decodeFloat(texture(PreviousFrameDataSampler, start + 4.0 * inc).xyz)), decodeFloat(texture(PreviousFrameDataSampler, start + 7.0 * inc).xyz), decodeFloat(texture(PreviousFrameDataSampler, start + 8.0 * inc).xyz),
        decodeFloat(texture(PreviousFrameDataSampler, start + 9.0 * inc).xyz), decodeFloat(texture(PreviousFrameDataSampler, start + 10.0 * inc).xyz), decodeFloat(texture(PreviousFrameDataSampler, start + 11.0 * inc).xyz),  decodeFloat(texture(PreviousFrameDataSampler, start + 12.0 * inc).xyz),
        decodeFloat(texture(PreviousFrameDataSampler, start + 13.0 * inc).xyz), decodeFloat(texture(PreviousFrameDataSampler, start + 14.0 * inc).xyz), decodeFloat(texture(PreviousFrameDataSampler, start + 15.0 * inc).xyz), 0.0
    );

    prevModelViewMat = mat4(
        decodeFloat(texture(PreviousFrameDataSampler, start + 16.0 * inc).xyz), decodeFloat(texture(PreviousFrameDataSampler, start + 17.0 * inc).xyz), decodeFloat(texture(PreviousFrameDataSampler, start + 18.0 * inc).xyz), 0.0,
        decodeFloat(texture(PreviousFrameDataSampler, start + 19.0 * inc).xyz), decodeFloat(texture(PreviousFrameDataSampler, start + 20.0 * inc).xyz), decodeFloat(texture(PreviousFrameDataSampler, start + 21.0 * inc).xyz), 0.0,
        decodeFloat(texture(PreviousFrameDataSampler, start + 22.0 * inc).xyz), decodeFloat(texture(PreviousFrameDataSampler, start + 23.0 * inc).xyz), decodeFloat(texture(PreviousFrameDataSampler, start + 24.0 * inc).xyz), 0.0,
        0.0, 0.0, 0.0, 1.0
    );

    near = PROJNEAR;
    far = currProjMat[3][2] * near / (currProjMat[3][2] + 2.0 * near);

    vec3 currChunkOffset = vec3(
        decodeFloat(texture(CurrentFrameDataSampler, start + 100 * inc).xyz),
        decodeFloat(texture(CurrentFrameDataSampler, start + 101 * inc).xyz),
        decodeFloat(texture(CurrentFrameDataSampler, start + 102 * inc).xyz)
    );

    vec3 prevChunkOffset = vec3(
        decodeFloat(texture(PreviousFrameDataSampler, start + 100 * inc).xyz),
        decodeFloat(texture(PreviousFrameDataSampler, start + 101 * inc).xyz),
        decodeFloat(texture(PreviousFrameDataSampler, start + 102 * inc).xyz)
    );

    prevPosition = mod(currChunkOffset - prevChunkOffset + 0.5, 1) - 0.5;

    float fov = atan(1 / currProjMat[1][1]);

    projInv = inverse(currProjMat * currModelViewMat);
    rayDir = (projInv * vec4(outPos.xy * (far - near), far + near, far - near)).xyz;

}