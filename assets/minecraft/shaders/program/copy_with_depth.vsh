#version 420

in vec4 Position;

out vec2 texCoord;

vec4[] OFFSETS = vec4[](
    vec4(-1, -1, 0, 1),
    vec4(1, -1, 0, 1),
    vec4(1, 1, 0, 1),
    vec4(-1, 1, 0, 1)
);

void main() {
    vec4 outPos = OFFSETS[gl_VertexID];
    gl_Position = vec4(outPos.xy, 0.0, 1.0);
    texCoord = outPos.xy * 0.5 + 0.5;
}