#version 420

#include<hdr.glsl>
#include<materialMask.glsl>
#line 5 1020

in vec2 texCoord;

uniform sampler2D DiffuseSampler;
uniform sampler2D GISampler;
uniform sampler2D WaterSampler;
uniform sampler2D MaterialMask;

out vec4 fragColor;

// TONEMAPPING

vec3 ACESFilm(vec3 x)
{
    float a = 2.51;
    float b = 0.03;
    float c = 2.43;
    float d = 0.59;
    float e = 0.14;
    return clamp((x*(a*x+b))/(x*(c*x+d)+e), 0.0, 1.0);
}

void main() {
    MaterialMaskData maskData = getMaterialMask(texture(MaterialMask, texCoord).r);
    bool isWater = texture(WaterSampler, texCoord).a > 0.5;
    vec3 color = pow(texture(DiffuseSampler, texCoord).rgb, vec3(2.2));
    vec3 gi = decodeHDRColor(texture(GISampler, texCoord));
    color = vec3(color) * (gi + maskData.emission * 10.0);
    
    color = ACESFilm(color);
    color = pow(color, vec3(1.0 / 2.2));
    fragColor = vec4(color, 1.0);
}