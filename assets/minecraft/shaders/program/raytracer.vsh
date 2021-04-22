#version 150

const float PROJNEAR = 0.05;
const float FPRECISION = 4000000.0;
const float EPSILON = 0.001;

in vec4 Position;

uniform mat4 ProjMat;
uniform vec2 OutSize;
uniform sampler2D DiffuseSampler;

out vec2 texCoord;
out vec2 oneTexel;
out vec3 sunDir;
out float near;
out float far;
out mat4 projMat;
out mat4 modelViewMat;
out vec3 chunkOffset;
out vec3 rayDir;
out float fov;
out mat3 cameraMatrix;

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
    vec4 outPos = ProjMat * vec4(Position.xy, 0.0, 1.0);
    gl_Position = vec4(outPos.xy, 0.2, 1.0);
    texCoord = Position.xy / OutSize;
    oneTexel = 1.0 / OutSize;

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

    vec3 up = normalize(vec3(
        decodeFloat(texture(DiffuseSampler, start + 103 * inc).xyz),
        decodeFloat(texture(DiffuseSampler, start + 104 * inc).xyz),
        decodeFloat(texture(DiffuseSampler, start + 105 * inc).xyz)
    ));

    vec3 forward = normalize(vec3(
        decodeFloat(texture(DiffuseSampler, start + 106 * inc).xyz),
        decodeFloat(texture(DiffuseSampler, start + 107 * inc).xyz),
        decodeFloat(texture(DiffuseSampler, start + 108 * inc).xyz)
    ));

    vec3 right = normalize(cross(up, forward));

    cameraMatrix = mat3(right, up, forward);

    fov = decodeFloat(texture(DiffuseSampler, start + 109 * inc).xyz) * 3.141592654;

//    sunDir = normalize((inverse(ModeViewMat) * vec4(decodeFloat(texture(DiffuseSampler, start).xyz),
//            decodeFloat(texture(DiffuseSampler, start + inc).xyz),
//            decodeFloat(texture(DiffuseSampler, start + 2.0 * inc).xyz),
//            1.0)).xyz);
}