#version 420

#include<hdr.glsl>
#include<variance.glsl>
#include<materialMask.glsl>
#include<conversions.glsl>
#line 7 1234

const float[] KERNEL = float[](
    3.0 / 8.0,
    1.0 / 4.0,
    1.0 / 16.0
);

const float[] GAUSS_KERNEL = float[](
    1.0 / 2.0,
    1.0 / 4.0
);

const float NORMAL_MULTIPLIER = 8.0;
const float DEPTH_MULTIPLIER = 1.0;
const float LUMA_MULTIPLIER = 40.0;

in vec2 texCoord;
in float renderScale;
in float near;
in float far;

uniform sampler2D DiffuseSampler;
uniform sampler2D DepthSampler;
uniform sampler2D NormalsSampler;
uniform sampler2D VarianceSampler;
uniform sampler2D MaterialMask;

uniform vec2 InSize;
uniform float Step;
uniform vec2 Direction;

out vec4 fragColor;

float depthToClip(float depth) {
    return (linearizeDepth(depth, near, far) - near) / (far - near) * 2.0 - 1.0;
}

void main() {
    ivec2 fragCoord = ivec2(gl_FragCoord.xy);
    int stepSize = int(Step);
    
    MaterialMaskData maskData = getMaterialMask(texture(MaterialMask, texCoord * renderScale).x);
    vec3 centerNormal = texture(NormalsSampler, texCoord).rgb * 2.0 - 1.0;//maskData.normal;
    // vec3 centerNormal = maskData.normal;
    float centerDepth = texture(DepthSampler, texCoord).x;

    if (centerDepth == 1.0) {
        fragColor = texture(DiffuseSampler, texCoord * renderScale, 0);
        return;
    } 
    centerDepth = depthToClip(centerDepth);

    float centerVariance = 0.0;
    
    float gaussianTotalWeight = 0.0;
    for (int x = -1; x <= 1; x++) {
        for (int y = -1; y <= 1; y++) {
            float kernelWeight = GAUSS_KERNEL[abs(x)] * GAUSS_KERNEL[abs(y)];
            vec2 sampleCoord = vec2(gl_FragCoord.xy + vec2(x, y)) / InSize;
            if (clamp(sampleCoord, 0.0, renderScale) != sampleCoord)
                continue;
                
            centerVariance += loadVariance(texture(VarianceSampler, sampleCoord).x) * kernelWeight;
            gaussianTotalWeight += kernelWeight;
        }
    }
    float stdDeviation = sqrt(max(centerVariance / gaussianTotalWeight, 0.0));

    float centerLuma = luminance(decodeHDRColor(texture(DiffuseSampler, texCoord * renderScale)));
    float depthGradient = Direction.x > 0.5 ? dFdx(centerDepth) : dFdy(centerDepth);

    float totalWeight = 0.0;
    vec3 color = vec3(0.0);
    float newVariance = 0.0;
    int radius = maskData.metal ? (Step > 16.0 ? 0 : 1) : 2;
    for (int i = -radius; i <= radius; i++) {
        float kernelWeight = KERNEL[abs(i)];
        ivec2 off = ivec2(i * stepSize * Direction);
        vec2 sampleCoord = (vec2(fragCoord + off) + 0.5) / InSize;
        if (clamp(sampleCoord, 0.0, renderScale - 0.001) != sampleCoord)
            continue;

        float depth = texture(DepthSampler, sampleCoord / renderScale).x;
        if (depth == 1.0)
            continue;
            
        depth = depthToClip(depth); 
        vec3 normal = texture(NormalsSampler, sampleCoord / renderScale).rgb * 2.0 - 1.0;//getMaskNormal(texture(MaterialMask, sampleCoord).x);
        // vec3 normal = getMaskNormal(texture(MaterialMask, sampleCoord).x);
        float variance = loadVariance(texture(VarianceSampler, sampleCoord).x);
        vec3 sampl = decodeHDRColor(texture(DiffuseSampler, sampleCoord));
        float luma = luminance(sampl);

        float normalWeight = pow(max(0.0, dot(centerNormal, normal)), NORMAL_MULTIPLIER);
        float depthWeight = -abs(centerDepth - depth) / (DEPTH_MULTIPLIER * abs(i * stepSize * depthGradient) + 0.001);
        float lumaWeight = -abs(luma - centerLuma) / (LUMA_MULTIPLIER * stdDeviation + 0.001);

        float weight = kernelWeight * normalWeight * exp(depthWeight + lumaWeight);
        totalWeight += weight;
        color += sampl * weight;
        newVariance += variance * weight * weight;
    }
    color /= totalWeight;
    newVariance /= totalWeight * totalWeight;
    fragColor = encodeHDRColor(color); 
    gl_FragDepth = storeVariance(newVariance);
}