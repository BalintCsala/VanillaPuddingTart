#version 420

#include<fog.glsl>
#include<utils.glsl>
#include<voxelization.glsl>

uniform sampler2D Sampler0;
uniform sampler2D Sampler2;

uniform vec4 ColorModulator;
uniform float FogStart;
uniform float FogEnd;
uniform vec4 FogColor;
uniform vec3 ChunkOffset;

in float vertexDistance;
in vec4 vertexColor;
in vec2 texCoord0;
in float dataFace;
in vec4 glpos;
flat in ivec2 cell;

out vec4 fragColor;

void main() {
    ivec2 screenSize = getScreenSize(gl_FragCoord.xy, glpos);
    discardControl(gl_FragCoord.xy, float(screenSize.x));
    if (dataFace < 0.5) {
        vec4 color = texture(Sampler0, texCoord0) * vertexColor * ColorModulator;
        if (color.a < 0.5) {
            discard;
        }
        fragColor = linear_fog(color, vertexDistance, FogStart, FogEnd, FogColor);
    } else if (dataFace < 1.5) {
        ivec2 pixel = cellToPixelStore(cell, screenSize);
        if (ivec2(gl_FragCoord.xy) != pixel)
            discard;
            
        fragColor = texelFetch(Sampler0, ivec2(texCoord0 * textureSize(Sampler0, 0)) + ivec2(9, 0), 0);
        
        ivec3 scaledColor = ivec3(round(vertexColor.rgb * vec3(3, 7, 3))) << ivec3(0, 2, 5);
        int tintColor = scaledColor.r | scaledColor.g | scaledColor.b;
        fragColor.a = tintColor / 255.0;
    } else {
        int index = int(gl_FragCoord.x);
        if (index < 3) {
            vec3 storedChunkOffset = mod(ChunkOffset, vec3(16)) / 16.0;
            fragColor = vec4(encodeFloat(storedChunkOffset[index]), 1);
        } else if (index == 3) {
            float lightLevel = (texture(Sampler2, vec2(0.5 / 16.0)).r * 255.0 - 15.0) / 20.0;
            fragColor.a = 1.0;
            fragColor.rgb = vec3(lightLevel);
        } else {
            discard;
        }
    }
}
