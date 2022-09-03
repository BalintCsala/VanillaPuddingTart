#version 150

#moj_import <font.glsl>
#moj_import <utils.glsl>

in vec4 vertexColor;
in float isHorizon;

uniform vec4 ColorModulator;
uniform float GameTime;
uniform vec2 ScreenSize;

out vec4 fragColor;

void main() {
    if (isHorizon > 0.5) {
        discardControl(gl_FragCoord.xy, ScreenSize.x);
    }

    vec4 color = vertexColor;
    if (color.a == 0.0) {
        discard;
    }
    if (distance(color.rgb, vec3(16 / 255.0)) < 0.01) {
        vec4 textColor = mix(vec4(1), vertexColor, 0.7);
        vec4 backgroundColor = vertexColor;

        ivec2 pixel = ivec2(gl_FragCoord.xy);
        ivec2 offset = pixel - ivec2(10, 26);
        if (offset.x >= 0 && offset.y >= 0 && offset.x < 622 && offset.y < 12) {
            uint[] TEXT = uint[](_S, _H, _A, _D, _E, _R, _SPACE, _M, _A, _D, _E, _SPACE, _B, _Y, _SPACE, _B, _A, _L, _I, _N, _T, _SPACE, _C, _S, _A, _L, _A, _SPACE, _PARENL, _G, _I, _T, _H, _U, _B, _DOT, _C, _O, _M, _RSLASH, _B, _A, _L, _I, _N, _T, _C, _S, _A, _L, _A, _PARENR);
            for (int i = 0; i < 52; i++) {
                int startX = i * 12;
                int endX = startX + 10;
                if (offset.x < endX) {
                    bool pixelOn = getPixel(TEXT[i], (offset.x - startX) / 2, offset.y / 2);
                    fragColor = pixelOn ? textColor : backgroundColor;
                    break;
                } else if (offset.x < endX + 2) {
                    fragColor = backgroundColor;
                    break;
                }
            }
            return;
        }

        offset = pixel - ivec2(10, 10);
        if (offset.x >= 0 && offset.y >= 0 && offset.x < 514 && offset.y < 12) {
            uint[] TEXT = uint[](_T, _H, _I, _S, _SPACE, _I, _S, _SPACE, _C, _U, _R, _R, _E, _N, _T, _L, _Y, _SPACE, _I, _N, _SPACE, _P, _R, _E, _DASH, _A, _L, _P, _H, _A, _COMMA, _SPACE, _E, _X, _P, _E, _C, _T, _SPACE, _B, _U, _G, _S);
            for (int i = 0; i < 43; i++) {
                int startX = i * 12;
                int endX = startX + 10;
                if (offset.x < endX) {
                    bool pixelOn = getPixel(TEXT[i], (offset.x - startX) / 2, offset.y / 2);
                    fragColor = pixelOn ? textColor : backgroundColor;
                    break;
                } else if (offset.x < endX + 2) {
                    fragColor = backgroundColor;
                    break;
                }
            }
            return;
        }
    }

    fragColor = color * ColorModulator;
}
