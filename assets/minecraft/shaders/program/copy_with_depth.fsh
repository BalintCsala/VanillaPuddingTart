#version 150

in vec2 texCoord;

uniform sampler2D DiffuseSampler;
uniform sampler2D DepthSampler;

out vec4 fragColor;

void main() {
    fragColor = texture(DiffuseSampler, texCoord);
    gl_FragDepth = texture(DepthSampler, texCoord).r;
}