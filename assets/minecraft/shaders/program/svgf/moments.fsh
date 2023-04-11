#version 420

#include<hdr.glsl>
#include<variance.glsl>
#include<constants.glsl>
#include<conversions.glsl>
#line 7 3722

in vec2 texCoord;
in mat4 projInv;
in mat3 modelViewMat;
in vec3 cameraOffset;
in mat4 prevProjMat;
in mat3 prevModelViewMat;
in float renderScale;

uniform sampler2D DiffuseSampler;
uniform sampler2D DepthSampler;
uniform sampler2D CounterSampler;
uniform sampler2D PrevMomentsSampler;
uniform vec2 InSize;

out vec4 fragColor;

void main() {
    float counter = texture(CounterSampler, texCoord * renderScale).r * MAX_COUNTER;

    float depth = texture(DepthSampler, texCoord).r;
    if (depth == 1.0) {
        return;
    }

    float luma = luminance(decodeHDRColor(texture(DiffuseSampler, texCoord * renderScale)));
    vec2 data = vec2(luma, luma * luma);
    
    if (counter > 0.5) {
        vec3 playerPos = screenToView(vec3(texCoord, depth), projInv) * modelViewMat;
        vec3 prevPlayerPos = playerPos - cameraOffset;
        vec4 prevClipPos = prevProjMat * vec4(prevModelViewMat * prevPlayerPos, 1.0);
        vec3 prevScreenPos = prevClipPos.xyz / prevClipPos.w * 0.5 + 0.5;
        
        vec2 previousData = unpackHalf2x16(packUnorm4x8(texture(PrevMomentsSampler, prevScreenPos.xy * renderScale)));
        
        data = mix(previousData, data, max(1.0 / (counter + 1.0), MAX_TEMPORAL_BLENDING));
    }
    
    fragColor = unpackUnorm4x8(packHalf2x16(data));
}