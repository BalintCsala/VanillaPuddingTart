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
uniform vec2 InSize;

out vec4 fragColor;

void main() {
    float counter = texture(CounterSampler, texCoord * renderScale).r * MAX_COUNTER;

    float depth = texture(DepthSampler, texCoord).r;
    if (depth == 1.0) {
        return;
    }
    
    float variance;
    if (counter < 4.0) {
        float totalWeight = 0.0;
        vec2 avgMoments = vec2(0.0);
        for (int x = -3; x <= 3; x++) {
            for (int y = -3; y <= 3; y++) {
                vec2 samplePos = (gl_FragCoord.xy + vec2(x, y)) / InSize;
                if (clamp(samplePos, 0.0, renderScale) != samplePos) {
                    continue;
                }
                
                // TODO: Use a better weight function
                float weight = 1.0;
                
                vec2 moments = unpackHalf2x16(packUnorm4x8(texture(DiffuseSampler, samplePos)));
                avgMoments += moments * weight;

                totalWeight += weight;
            }
        }
        
        avgMoments /= totalWeight;
        
        variance = avgMoments.y - avgMoments.x * avgMoments.x;
        variance *= 4.0 - counter;
    } else {
        vec2 moments = unpackHalf2x16(packUnorm4x8(texture(DiffuseSampler, texCoord * renderScale)));
        variance = moments.y - moments.x * moments.x;
    }
    
    gl_FragDepth = storeVariance(variance);
}