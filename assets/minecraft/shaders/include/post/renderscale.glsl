#ifndef RENDERSCALE_GLSL
#define RENDERSCALE_GLSL

float getRenderScale(sampler2D dataSampler) {
    return clamp(texelFetch(dataSampler, ivec2(3, 0), 0).r * 0.5 + 0.5, 0.5, 1.0);
}

vec4 scaleClipPos(vec4 clipPos, float renderScale) {
    return vec4((clipPos.xy + 1.0) * renderScale - 1.0, clipPos.zw);
}

#endif // RENDERSCALE_GLSL