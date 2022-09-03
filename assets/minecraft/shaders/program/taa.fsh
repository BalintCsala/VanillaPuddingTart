#version 150

in vec2 texCoord;
in mat4 projMat;
in mat3 modelViewMat;
in mat4 prevProjMat;
in mat3 prevModelViewMat;
in mat4 projInv;
in vec3 cameraOffset;

uniform sampler2D DiffuseSampler;
uniform sampler2D DiffuseDepthSampler;
uniform sampler2D PrevResultSampler;
uniform sampler2D PrevResultDepthSampler;
uniform vec2 InSize;

out vec4 fragColor;

float linearizeDepth(float depth) {
    // TODO: Check if this is ok
    return 5.0 / (depth * 99.95 + 100.0);
}

vec3 screenToView(vec3 screenPos) {
    vec4 ndc = vec4(screenPos * 2.0 - 1.0, 1.0);
    vec4 viewPos = projInv * ndc;
    return viewPos.xyz / viewPos.w;
}

// From a presentation given by Lasse Jon Fuglsang Pedersen titled "Temporal Reprojection Anti-Aliasing in INSIDE"
// https://www.youtube.com/watch?v=2XXS5UyNjjU&t=434s
vec3 clipColor(vec3 aabbMin, vec3 aabbMax, vec3 prevColor) {
    // Center of the clip space
    vec3 pClip = (aabbMax + aabbMin) / 2;
    // Size of the clip space
    vec3 eClip = (aabbMax - aabbMin) / 2;

    // The relative coordinates of the previous color in the clip space
    vec3 vClip = prevColor - pClip;
    // Normalized clip space coordintes
    vec3 vUnit = vClip / eClip;
    // The distance of the previous color from the center of the clip space in each axis in the normalized clip space
    vec3 aUnit = abs(vUnit);
    // The divisor is the largest distance from the center along each axis
    float divisor = max(aUnit.x, max(aUnit.y, aUnit.z));
    if (divisor > 1) {
        // If the divisor is larger, than 1, that means that the previous color is outside of the clip space
        // If we divide by divisor, we'll put it into clip space
        return pClip + vClip / divisor;
    }
    // Otherwise it's already clipped
    return prevColor;
}

vec4 encodeHDRColor(vec3 color) {
    uvec3 rawOutput = uvec3(color * vec3(2047.0, 2047.0, 1023.0)) << uvec3(0, 11, 22);
    uint output = rawOutput.x | rawOutput.y | rawOutput.z;
    return vec4(
        output & 255u,
        (output >> 8u) & 255u,
        (output >> 16u) & 255u,
        output >> 24u
    ) / 255.0;
}

vec3 decodeHDRColor(vec4 raw) {
    uvec4 scaled = uvec4(raw * 255.0) << uvec4(0, 8, 16, 24);
    uint data = scaled.x | scaled.y | scaled.z | scaled.w;
    return vec3(
        data & 2047u,
        (data >> 11u) & 2047u,
        data >> 22u
    ) / vec3(2047.0, 2047.0, 1024.0);
}

vec3 bilinearSample(sampler2D sampl, vec2 texCoord) {
    vec2 fragCoord = texCoord * InSize - 0.5;
    ivec2 bottomLeft = ivec2(fragCoord);
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
    vec3 color = bilinearSample(DiffuseSampler, texCoord);
    float depth = texture(DiffuseDepthSampler, texCoord).r;
    gl_FragDepth = depth;
    vec3 playerPos = screenToView(vec3(texCoord, depth)) * modelViewMat;
    vec3 prevPlayerPos = playerPos - cameraOffset;
    vec4 prevClipPos = prevProjMat * vec4(prevModelViewMat * prevPlayerPos, 1.0);
    vec3 prevScreenPos = prevClipPos.xyz / prevClipPos.w * 0.5 + 0.5;
    if (clamp(prevScreenPos.xy, 0.0, 1.0) != prevScreenPos.xy) {
        fragColor = encodeHDRColor(color);
        return;
    }
    float prevDepth = texture(PrevResultDepthSampler, prevScreenPos.xy).r;
    if (abs(linearizeDepth(depth) - linearizeDepth(prevDepth)) > 0.001) {
        fragColor = encodeHDRColor(color);
        return;
    }
    
    vec2 oneTexel = 1.0 / InSize;
    vec3 minCol = vec3(1);
    vec3 maxCol = vec3(0);
    for (float x = -1; x <= 1; x++) {
        for (float y = -1; y <= 1; y++) {
            vec3 neighbor = decodeHDRColor(texture(DiffuseSampler, texCoord + vec2(x, y) * oneTexel));
            minCol = min(minCol, neighbor);
            maxCol = max(maxCol, neighbor);
        }
    }
    
    vec3 prevColor = bilinearSample(PrevResultSampler, prevScreenPos.xy);
    vec3 clippedPrevColor = clipColor(minCol, maxCol, prevColor);
    fragColor = encodeHDRColor(mix(clippedPrevColor, color, 0.02));
}