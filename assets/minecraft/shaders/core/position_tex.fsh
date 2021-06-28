#version 150

#moj_import <utils.glsl>

uniform sampler2D Sampler0;
uniform vec4 ColorModulator;
uniform vec2 ScreenSize;
uniform mat4 ModelViewMat;

in mat4 ProjInv;
in vec3 cscale;
in vec3 c1;
in vec3 c2;
in vec3 c3;
in vec2 texCoord0;
in float isSun;

out vec4 fragColor;

#define PRECISIONSCALE 1000.0
#define MAGICSUNSIZE 3.0

void main() {
    vec4 color = vec4(0.0);

    int index = inControl(gl_FragCoord.xy, ScreenSize.x);
    
    if(index != -1) {
        if (isSun > 0.75 && index >= 0 && index <= 2) {
            vec4 sunDir = vec4(normalize(c1 / cscale.x + c3 / cscale.z), 0.0);
            color = vec4(encodeFloat(sunDir[index]), 1.0);
        } else if (isSun < 0.25) {
            color = texture(Sampler0, texCoord0) * ColorModulator;
        } else {
            discard;
        }
    } else if(isSun > 0.75) {
        discard;
    } else {
        color = texture(Sampler0, texCoord0) * ColorModulator;
    }

    if (color.a == 0.0) {
        discard;
    }
    fragColor = color;
}