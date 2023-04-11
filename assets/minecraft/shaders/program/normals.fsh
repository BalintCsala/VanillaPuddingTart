#version 420

#include<conversions.glsl>

in vec2 texCoord;
in mat4 projInv;
in mat3 modelViewMat;
in float near;
in float far;

uniform sampler2D DiffuseSampler;
uniform sampler2D DepthSampler;

uniform vec2 InSize;

out vec4 fragColor;

vec3 getNormal(vec3 screenPos) {
    vec3 viewPos = screenToView(screenPos, projInv);

    vec2 off = 1.0 / InSize * 1.00;
    vec2 right = screenPos.xy + vec2(off.x, 0);
    vec2 left = screenPos.xy + vec2(-off.x, 0);
    vec2 top = screenPos.xy + vec2(0, off.y);
    vec2 bottom = screenPos.xy + vec2(0, -off.y);
    
    float depthRight = texture(DepthSampler, right).r;
    float depthLeft = texture(DepthSampler, left).r;
    float depthTop = texture(DepthSampler, top).r;
    float depthBottom = texture(DepthSampler, bottom).r;

    float linDepth = linearizeDepth(screenPos.z, near, far);
    float linDepthRight = linearizeDepth(depthRight, near, far);
    float linDepthLeft = linearizeDepth(depthLeft, near, far);
    float linDepthTop = linearizeDepth(depthTop, near, far);
    float linDepthBottom = linearizeDepth(depthBottom, near, far);

    float depthX, depthY;
    vec2 texCoordX, texCoordY;
    float mul = 1.0;
    
    if (abs(linDepthRight - linDepth) < abs(linDepthLeft - linDepth)) {
        depthX = depthRight;
        texCoordX = right;
    } else {
        depthX = depthLeft;
        texCoordX = left;
        mul *= -1.0;
    }
    if (abs(linDepthTop - linDepth) < abs(linDepthBottom - linDepth)) {
        depthY = depthTop;
        texCoordY = top;
    } else {
        depthY = depthBottom;
        texCoordY = bottom;
        mul *= -1.0;
    }
    
    vec3 viewPosX = screenToView(vec3(texCoordX, depthX), projInv);
    vec3 viewPosY = screenToView(vec3(texCoordY, depthY), projInv);
    vec3 viewNormal = normalize(cross(viewPosX - viewPos, viewPosY - viewPos)) * mul;
    return viewNormal * modelViewMat;
}

void main() {
    float depth = texture(DepthSampler, texCoord).r;
    if (depth == 1.0) {
        fragColor = vec4(0, 0, 1, 1);
        return;
    }
    
    vec3 normal = getNormal(vec3(texCoord, depth));
    fragColor = vec4(
        normal * 0.5 + 0.5, 
        1.0
    );
}