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
            // store ModelViewMat in control pixels
            int c = (index - 16) / 3;
            int r = (index - 16) - c * 3;
            fragColor = vec4(encodeFloat(ModelViewMat[c][r]), 1.0);
        } else if (index >= 3 && index <= 4) {
            // store ProjMat[0][0] and ProjMat[1][1] in control pixels
            fragColor = vec4(encodeFloat(atan(ProjMat[index - 3][index - 3])), 1.0);
        } else if (index >= 103 && index <= 105) {
            vec3 up = normalize((ModelViewMat * vec4(0, 1, 0, 0)).xyz);
            fragColor = vec4(encodeFloat(up[index - 103]), 1);
        } else if (index >= 106 && index <= 108) {
            vec3 forward = normalize((ModelViewMat * vec4(0, 0, 1, 0)).xyz);
            fragColor = vec4(encodeFloat(forward[index - 106]), 1);
        } else if (index == 109) {
            fragColor = vec4(encodeFloat(atan(1 / ProjMat[0][0]) / 3.141592654), 1);
        }
    } else {
        // Otherwise we draw a white sky
        fragColor = vec4(1);
    }
}
