#version 420

in vec2 texCoord;

uniform sampler2D DiffuseSampler;

out vec4 fragColor;

void main() {
    fragColor = texture(DiffuseSampler, texCoord);
}