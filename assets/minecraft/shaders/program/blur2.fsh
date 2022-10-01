#version 150

in vec2 texCoord;

uniform sampler2D DiffuseSampler;
uniform sampler2D NormalsSampler;
uniform vec2 InSize;
uniform vec2 Direction;

out vec4 fragColor;

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

void main() {
    float scale = exp2(-floor(log2(texCoord.x)));
    vec2 tcoord = texCoord * scale - vec2(1, 1); 
    vec3 centerNormal = texture(NormalsSampler, tcoord).rgb * 2.0 - 1.0;

    vec2 texSize = 1.0 / InSize;
    vec2 mipmapTexSize = texSize * scale;

    vec3 normalFarLeft = texture(NormalsSampler, tcoord - 2.0 * mipmapTexSize * Direction).rgb * 2.0 - 1.0;
    vec3 normalLeft = texture(NormalsSampler, tcoord - mipmapTexSize * Direction).rgb * 2.0 - 1.0;
    vec3 normalRight = texture(NormalsSampler, tcoord + mipmapTexSize * Direction).rgb * 2.0 - 1.0;
    vec3 normalFarRight = texture(NormalsSampler, tcoord + 2.0 * mipmapTexSize * Direction).rgb * 2.0 - 1.0;
    
    float weightFarLeft = 0.15 * max(dot(normalLeft, centerNormal), 0.0);
    float weightLeft = 0.20 * max(dot(normalLeft, centerNormal), 0.0);
    const float weightCenter = 0.30;
    float weightRight = 0.20 * max(dot(normalRight, centerNormal), 0.0);
    float weightFarRight = 0.15 * max(dot(normalRight, centerNormal), 0.0);

    vec3 total;
    total  = weightFarLeft * decodeHDRColor(texture(DiffuseSampler, texCoord - 2.0 * texSize * Direction));
    total += weightLeft * decodeHDRColor(texture(DiffuseSampler, texCoord - texSize * Direction));
    total += weightCenter * decodeHDRColor(texture(DiffuseSampler, texCoord));
    total += weightRight * decodeHDRColor(texture(DiffuseSampler, texCoord + texSize * Direction));
    total += weightFarRight * decodeHDRColor(texture(DiffuseSampler, texCoord + 2.0 * texSize * Direction));
    total /= (weightFarLeft + weightLeft + weightCenter + weightRight + weightFarRight);
    fragColor = encodeHDRColor(total);
}