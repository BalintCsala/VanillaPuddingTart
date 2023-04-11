#version 420

#include<hdr.glsl>

in vec2 texCoord;
in float renderScale;

uniform sampler2D DiffuseSampler;
uniform sampler2D DepthSampler;
uniform vec2 InSize;

out vec4 fragColor;

vec3 bilinearSample(sampler2D sampl, vec2 fragCoord) {
    ivec2 bottomLeft = ivec2(floor(fragCoord));
    vec2 fractFragCoord = fract(fragCoord);
    return mix(
        mix(
            decodeHDRColor(texelFetch(sampl, bottomLeft + ivec2(0, 0), 0)),
            decodeHDRColor(texelFetch(sampl, bottomLeft + ivec2(1, 0), 0)),
            fractFragCoord.x
        ),
        mix(
            decodeHDRColor(texelFetch(sampl, bottomLeft + ivec2(0, 1), 0)),
            decodeHDRColor(texelFetch(sampl, bottomLeft + ivec2(1, 1), 0)),
            fractFragCoord.x
        ),
        fractFragCoord.y
    );
}

void main() {
    ivec2 fragCoord = ivec2(floor((texCoord * InSize) * renderScale));
    fragColor = texelFetch(DiffuseSampler, fragCoord, 0);
    gl_FragDepth = texture(DepthSampler, texCoord * renderScale).r;
}