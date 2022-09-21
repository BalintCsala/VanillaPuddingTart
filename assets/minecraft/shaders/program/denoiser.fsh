#version 150

const float SQRT_2PI = 2.506628274631002;

in vec2 texCoord;

uniform vec2 InSize;
uniform sampler2D TAASampler;
uniform sampler2D DiffuseSampler;
uniform sampler2D DiffuseDepthSampler;
uniform sampler2D NormalsSampler;

out vec4 fragColor;

float gaussian(vec2 x, float sigma) {
    vec2 scaled = x / sigma;
    return exp(-0.5 * dot(scaled, scaled)) / sigma / SQRT_2PI;
}

vec4 encodeHDRColor(vec3 color) {
    uvec3 rawOutput = uvec3(round(color * 128.0)) << uvec3(0, 11, 22);
    uint result = rawOutput.x | rawOutput.y | rawOutput.z;
    return vec4(
        result & 255u,
        (result >> 8u) & 255u,
        (result >> 16u) & 255u,
        result >> 24u
    ) / 255.0;
}

vec3 decodeHDRColor(vec4 raw) {
    uvec4 scaled = uvec4(raw * 255.0) << uvec4(0, 8, 16, 24);
    uint data = scaled.x | scaled.y | scaled.z | scaled.w;
    return vec3(
        float(data & 2047u),
        float((data >> 11u) & 2047u),
        float(data >> 22u)
    ) / 128.0;
}

float[] WEIGHTS = float[](
    0.006827, 
    0.063616, 
    0.241441, 
    0.376230, 
    0.241441, 
    0.063616, 
    0.006827
);

void main() {
    vec2 texelSize = 1.0 / InSize;
    vec3 result = vec3(0);
    float totalWeight = 0.0;
    float counter = texture(TAASampler, texCoord).a * 255.0;
    
    vec3 centerNormal = texture(NormalsSampler, texCoord).xyz * 2.0 - 1.0;
    
    for (int dx = -3; dx <= 3; dx++) {
        float xWeight = WEIGHTS[dx + 3];
        for (int dy = -3; dy <= 3; dy++) {
            vec2 off = vec2(dx, dy);
            float yWeight = WEIGHTS[dy + 3];
            vec2 sampleCoord = texCoord + off * texelSize;
            vec3 normal = texture(NormalsSampler, sampleCoord).xyz * 2.0 - 1.0;
            float weight = xWeight * yWeight * pow(max(dot(normal, centerNormal), 0.0), 7.0);
            result += decodeHDRColor(texture(DiffuseSampler, sampleCoord)) * weight;
            totalWeight += weight;
        }
    }
    fragColor = encodeHDRColor(clamp(result / totalWeight, 0.0, 1.0));
}