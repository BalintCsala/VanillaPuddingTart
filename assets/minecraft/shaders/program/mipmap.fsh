#version 150
uniform sampler2D DiffuseSampler;
uniform sampler2D MipmapSampler;
uniform vec2 InSize;
uniform float Stage;

in vec2 texCoord;

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

vec3 downSample(sampler2D sampl, vec2 texCoord) {
    vec2 texSize = 1.0 / InSize;
    vec2 bottomLeft = floor(texCoord * InSize) * texSize;
    vec3 off = vec3(texSize, 0.0);
    return 
        decodeHDRColor(texture(sampl, bottomLeft + off.zz)) * 0.25 +
        decodeHDRColor(texture(sampl, bottomLeft + off.xz)) * 0.25 +
        decodeHDRColor(texture(sampl, bottomLeft + off.zy)) * 0.25 +
        decodeHDRColor(texture(sampl, bottomLeft + off.xy)) * 0.25;
}

void main() {
    float scale = exp2(Stage);
    vec2 tcoord = texCoord * scale - 1.0; 
    if (clamp(tcoord, vec2(0.0), vec2(1.0)) != tcoord) {
        fragColor = texture(DiffuseSampler, texCoord);
        return;
    }
    if (Stage > 1.5) {
        tcoord = (tcoord + 1.0) / scale * 2.0;        
    }
    fragColor = encodeHDRColor(downSample(DiffuseSampler, tcoord));
}