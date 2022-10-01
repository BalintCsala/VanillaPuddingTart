#version 150

const float SQRT_2PI = 2.506628274631002;

in vec2 texCoord;

uniform vec2 InSize;
uniform sampler2D TAASampler;
uniform sampler2D DiffuseSampler;
uniform sampler2D DiffuseDepthSampler;
uniform sampler2D NormalsSampler;
uniform sampler2D MipmapSampler;

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

vec3 bilinearSample(sampler2D sampl, vec2 fragCoord) {
    ivec2 bottomLeft = ivec2(floor(fragCoord));
    vec2 fractFragCoord = fract(fragCoord);
    return mix(
        mix(
            decodeHDRColor(texelFetch(sampl, bottomLeft + ivec2(0, 0), 0)),
            decodeHDRColor(texelFetch(sampl, bottomLeft + ivec2(1, 0), 0)),
            fractFragCoord.x
        ),
        mix(
            decodeHDRColor(texelFetch(sampl, bottomLeft + ivec2(0, 1), 0)),
            decodeHDRColor(texelFetch(sampl, bottomLeft + ivec2(1, 1), 0)),
            fractFragCoord.x
        ),
        fractFragCoord.y
    );
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
    float depth = texture(DiffuseDepthSampler, texCoord).r;
    if (depth == 1.0) {
        fragColor = texture(DiffuseSampler, texCoord);
        return;
    }
    vec3 result = vec3(0);
    float totalWeight = 0.0;
    float counter = texture(TAASampler, texCoord).a * 255.0 - 1.0;
    
    float blurAmount = 1.0 - counter / 255.0;
    float layer = pow(blurAmount, 40.0) * 3.0 + 1.0;
    float lowerLayer = floor(layer);
    float upperLayer = ceil(layer);
    vec2 lowerTexcoord = (texCoord + 1) * exp2(-lowerLayer);
    vec2 upperTexcoord = lowerTexcoord / 2.0;
    
    vec3 lowerColor = bilinearSample(MipmapSampler, lowerTexcoord * InSize);
    vec3 upperColor = bilinearSample(MipmapSampler, upperTexcoord * InSize);
    vec3 color = mix(lowerColor, upperColor, fract(layer));
    
    fragColor = encodeHDRColor(color);
}