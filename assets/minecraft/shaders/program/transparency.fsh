#version 420

#include<font.glsl>

uniform sampler2D DiffuseSampler;
uniform sampler2D DepthSampler;
uniform sampler2D ItemEntitySampler;
uniform sampler2D ItemEntityDepthSampler;
uniform sampler2D ParticlesSampler;
uniform sampler2D ParticlesDepthSampler;
uniform sampler2D CloudsSampler;
uniform sampler2D CloudsDepthSampler;
uniform sampler2D WeatherSampler;
uniform sampler2D WeatherDepthSampler;
uniform sampler2D Atlas;

in vec2 texCoord;

#define NUM_LAYERS 6

vec4 color_layers[NUM_LAYERS];
float depth_layers[NUM_LAYERS];
int active_layers = 0;

out vec4 fragColor;

void try_insert( vec4 color, float depth ) {
    if ( color.a == 0.0 ) {
        return;
    }

    color_layers[active_layers] = color;
    depth_layers[active_layers] = depth;

    int jj = active_layers++;
    int ii = jj - 1;
    while ( jj > 0 && depth_layers[jj] > depth_layers[ii] ) {
        float depthTemp = depth_layers[ii];
        depth_layers[ii] = depth_layers[jj];
        depth_layers[jj] = depthTemp;

        vec4 colorTemp = color_layers[ii];
        color_layers[ii] = color_layers[jj];
        color_layers[jj] = colorTemp;

        jj = ii--;
    }
}

vec3 blend( vec3 dst, vec4 src ) {
    return ( dst * ( 1.0 - src.a ) ) + src.rgb;
}

void main() {
    if (textureSize(Atlas, 0).x < 16) {
        fragColor = vec4(0, 0, 0, 1);
        // Set offset to the pixel coordinates you want the text to start at
        ivec2 start = ivec2(200, 8);
        // Set these to the text and background color respectively
        vec4 textColor = vec4(1, 0, 0, 1);
        vec4 backgroundColor = vec4(0, 0, 0, 1);

        // Don't change from here
        ivec2 pixel = ivec2(gl_FragCoord.xy) % ivec2(10000, 60);
        ivec2 offset = pixel - start;
        if (offset.x >= 0 && offset.y >= 0 && offset.x < 730 && offset.y < 12) {
            uint[] TEXT = uint[](_I, _N, _C, _O, _R, _R, _E, _C, _T, _SPACE, _I, _N, _S, _T, _A, _L, _L, _A, _T, _I, _O, _N, _COMMA, _SPACE, _C, _H, _E, _C, _K, _SPACE, _T, _H, _E, _SPACE, _G, _U, _I, _D, _E, _SPACE, _L, _I, _N, _K, _E, _D, _SPACE, _O, _N, _SPACE, _T, _H, _E, _SPACE, _P, _A, _T, _R, _E, _O, _N);
            for (int i = 0; i < 61; i++) {
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
        return;
    }
    color_layers[0] = vec4( texture( DiffuseSampler, texCoord ).rgb, 1.0 );
    depth_layers[0] = texture( DepthSampler, texCoord ).r;
    active_layers = 1;

    try_insert( texture( ItemEntitySampler, texCoord ), texture( ItemEntityDepthSampler, texCoord ).r );
    try_insert( texture( ParticlesSampler, texCoord ), texture( ParticlesDepthSampler, texCoord ).r );
    try_insert( texture( WeatherSampler, texCoord ), texture( WeatherDepthSampler, texCoord ).r );
    try_insert( texture( CloudsSampler, texCoord ), texture( CloudsDepthSampler, texCoord ).r );

    vec3 texelAccum = color_layers[0].rgb;
    for ( int ii = 1; ii < active_layers; ++ii ) {
        texelAccum = blend( texelAccum, color_layers[ii] );
    }

    fragColor = vec4( texelAccum.rgb, 1.0 );
}
