#version 420

#include<constants.glsl>

in vec4 Position;

uniform vec2 InSize;

out vec2 texCoord;

vec4[] OFFSETS = vec4[](
    vec4(-1, -1, 0, 1),
    vec4(1, -1, 0, 1),
    vec4(1, 1, 0, 1),
    vec4(-1, 1, 0, 1)
);

void main() {
    vec4 outPos = OFFSETS[gl_VertexID];
    texCoord = outPos.xy * 0.5 + 0.5;
    
    gl_Position = outPos;
}