#version 150

in vec2 texCoord;
in vec2 oneTexel;

uniform sampler2D DiffuseSampler;
uniform sampler2D CurrentFrameDepthSampler;
uniform sampler2D PreviousFrameSampler;
uniform sampler2D PreviousFrameDepthSampler;

out vec4 fragColor;

void main() {
    vec3 currColor = texture(DiffuseSampler, texCoord).rgb;
    fragColor = vec4(currColor, 1);//texture(CurrentFrameDepthSampler, texCoord).rrra;//vec4(mix(currColor, vec3(0, 0, 0), texture(CurrentFrameDepthSampler, texCoord).r * 5), 1);
}