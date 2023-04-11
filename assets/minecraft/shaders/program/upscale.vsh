#version 420

#include<post/renderscale.glsl>

in vec4 Position;

uniform mat4 ProjMat;
uniform sampler2D DataSampler;

out vec2 texCoord;
out float renderScale;

void main() {
    vec4 outPos = ProjMat * vec4(Position.xy, 0.0, 1.0);
    gl_Position = vec4(outPos.xy, 0.0, 1.0);
    texCoord = gl_Position.xy * 0.5 + 0.5;
    renderScale = getRenderScale(DataSampler);
}