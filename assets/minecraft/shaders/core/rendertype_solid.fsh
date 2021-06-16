#version 150

#moj_import <utils.glsl>

uniform sampler2D Sampler0;

in vec2 texCoord0;
in vec2 pixel;
in vec3 chunkOffset;
in vec4 glpos;

out vec4 fragColor;

void main() {
    gl_FragDepth = 1;
    if (gl_PrimitiveID < 2) {
        // We'll treat the first face of every chunk differently
        int index = inControl(gl_FragCoord.xy, glpos);
        if (gl_FragCoord.x == pixel.x && gl_FragCoord.y == pixel.y) {
            vec2 scaledUV = floor(texCoord0 * 64);
            int tx = int(scaledUV.x);
            int ty = int(scaledUV.y);
            fragColor = vec4(encodeInt((tx << 6) | ty), 1);
            discard;
        } else if (index >= 100 && index <= 102) {
            fragColor = vec4(encodeFloat(fract(chunkOffset[index - 100])), 1);
        } else {
            discard;
        }
    } else {
        fragColor = texture(Sampler0, texCoord0);
    }
}
