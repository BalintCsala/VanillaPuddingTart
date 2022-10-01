#version 150

uniform sampler2D DiffuseSampler;
uniform sampler2D DiffuseDepthSampler;
uniform sampler2D PrevDiffuseSampler;
uniform sampler2D TAASampler;

uniform vec2 InSize;

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

void main() {
    ivec2 fragCoord = ivec2(texCoord * InSize);
    vec4 data = texelFetch(TAASampler, fragCoord, 0);
    uvec3 offsetDataRaw = uvec3(data.rgb * 255.0) << uvec3(16u, 8u, 0u);
    uint offsetData = offsetDataRaw.x | offsetDataRaw.y | offsetDataRaw.z;
    
    vec2 offset = vec2(
        offsetData >> 12u,
        offsetData & 4095u
    ) / 16.0 - 128.0; 

    gl_FragDepth = texelFetch(DiffuseDepthSampler, fragCoord, 0).r;
    vec4 colorData = texelFetch(DiffuseSampler, fragCoord, 0);
    
    uint counter = uint(data.a * 255.0) - 1u;
    if (counter == 0u) {
        fragColor = colorData;
        return;
    }
    
    vec3 color = decodeHDRColor(colorData);
    
    vec3 prevColor = bilinearSample(PrevDiffuseSampler, vec2(fragCoord) + offset + 1.0 / 64.0);
    
    fragColor = encodeHDRColor(mix(
        color,
        prevColor,
        min(float(counter) / float(counter + 1u), 0.96)
    ));
} 