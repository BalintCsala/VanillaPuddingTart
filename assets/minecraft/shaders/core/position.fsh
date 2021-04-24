#version 150

#moj_import <utils.glsl>

in float isSky;

uniform vec4 ColorModulator;
uniform float FogStart;
uniform float FogEnd;
uniform vec4 FogColor;
uniform vec2 ScreenSize;
uniform mat4 ProjMat;
uniform mat4 ModelViewMat;

out vec4 fragColor;

void main() {
    int index = inControl(gl_FragCoord.xy, ScreenSize.x);
    if (isSky > 0.5 && index != -1) {
        if (index >= 5 && index <= 15) {
            // store ProjMat in control pixels
            int c = (index - 5) / 4;
            int r = (index - 5) - c * 4;
            c = (c == 0 && r == 1) ? c : c + 1;
            fragColor = vec4(encodeFloat(ProjMat[c][r]), 1.0);
        } else if (index >= 16 && index <= 24) {
            int c = (index - 16) / 3;
            int r = (index - 16) - c * 3;
            fragColor = vec4(encodeFloat(ModelViewMat[c][r]), 1.0);
        } else if (index >= 3 && index <= 4) {
            // store ProjMat[0][0] and ProjMat[1][1] in control pixels
            fragColor = vec4(encodeFloat(atan(ProjMat[index - 3][index - 3])), 1.0);
        } else if (index == 109) {
            fragColor = vec4(encodeFloat(atan(1 / ProjMat[0][0])), 1);
        } else if (index <= 2) {
            discard;
        }
    } else if (index != -1) {
        discard;
    } else {
        // Otherwise we draw a white sky
        fragColor = vec4(1);
    }
}
