#version 420

#include<voxelization.glsl>

uniform sampler2D DiffuseSampler;
uniform sampler2D DepthSampler;
uniform vec2 InSize;
uniform vec2 OutSize;

in vec2 texCoord;

out vec4 fragColor;

void main() {
    ivec2 pixel = ivec2(gl_FragCoord.xy);
    ivec3 position = pixelToPosition(pixel);
    bool inside;
    ivec2 oldPixel = cellToPixelStore(positionToCellStore(vec3(position), inside), ivec2(InSize));

    if (texelFetch(DepthSampler, oldPixel, 0).r != 0.0) {
        gl_FragDepth = 1.0;
        fragColor = vec4(0);
        return;
    }
    
    fragColor = texelFetch(DiffuseSampler, oldPixel, 0);
    gl_FragDepth = 0.0;
}
