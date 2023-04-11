#ifndef CONVERSIONS
#define CONVERSIONS

vec3 screenToView(vec3 screenPos, mat4 projInv) {
    vec4 ndc = vec4(screenPos * 2.0 - 1.0, 1.0);
    vec4 viewPos = projInv * ndc;
    return viewPos.xyz / viewPos.w;
}

vec3 viewToScreen(vec3 viewPos, mat4 projMat) {
    vec4 clipEnd = projMat * vec4(viewPos, 1);
    return clipEnd.xyz / clipEnd.w * 0.5 + 0.5;
}

float linearizeDepth(float depth, float near, float far) {
    return (near * far) / (depth * (near - far) + far);
}

#endif // CONVERSIONS