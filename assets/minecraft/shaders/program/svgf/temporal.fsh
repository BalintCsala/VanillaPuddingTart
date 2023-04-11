#version 420

#include<hdr.glsl>
#include<conversions.glsl>
#include<constants.glsl>
#line 7 7583

in vec2 texCoord;
in mat3 modelViewMat;
in mat4 prevProjMat;
in mat3 prevModelViewMat;
in mat4 projInv;
in vec3 cameraOffset;
in float near;
in float far;
in float renderScale;
in float prevRenderScale;

uniform sampler2D DiffuseSampler;
uniform sampler2D DepthSampler;

uniform sampler2D PrevDiffuseSampler;
uniform sampler2D PrevDepthSampler;

uniform sampler2D NormalsSampler;
uniform sampler2D PrevNormalsSampler;

uniform sampler2D PrevCounterSampler;

uniform vec2 InSize;

out vec4 fragColor;

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
    vec4 rawColor = texture(DiffuseSampler, texCoord * renderScale);

    fragColor = rawColor;
    gl_FragDepth = 0.0;
    
    float depth = texture(DepthSampler, texCoord).r;
    if (depth == 1.0) {
        return;
    }
    vec3 playerPos = screenToView(vec3(texCoord, depth), projInv) * modelViewMat;
    vec3 prevPlayerPos = playerPos - cameraOffset;
    vec4 prevClipPos = prevProjMat * vec4(prevModelViewMat * prevPlayerPos, 1.0);
    vec3 prevScreenPos = prevClipPos.xyz / prevClipPos.w * 0.5 + 0.5;

    if (clamp(prevScreenPos.xy, 0.0, 1.0) != prevScreenPos.xy) {
        return;
    }

    vec3 normal = texture(NormalsSampler, texCoord).rgb * 2.0 - 1.0;
    vec3 prevNormal = texture(PrevNormalsSampler, prevScreenPos.xy).rgb * 2.0 - 1.0;
    
    if (dot(normal, prevNormal) < 0.3) {
        return;
    }
    
    float prevDepth = texture(PrevDepthSampler, prevScreenPos.xy).r;
    if (abs(prevScreenPos.z - prevDepth) > 0.003) {
        return;
    }
    
    uint counter = uint(texture(PrevCounterSampler, prevScreenPos.xy * prevRenderScale).r * float(MAX_COUNTER));
    counter = min(counter + 1u, MAX_COUNTER);

    vec3 color = decodeHDRColor(rawColor);
    vec3 prevColor = bilinearSample(PrevDiffuseSampler, (prevScreenPos.xy * prevRenderScale) * InSize - 0.5);
    
    fragColor = encodeHDRColor(mix(
        prevColor,
        color,
        max(1.0 / float(counter + 1), MAX_TEMPORAL_BLENDING)
    ));
    gl_FragDepth = float(counter) / float(MAX_COUNTER);
}