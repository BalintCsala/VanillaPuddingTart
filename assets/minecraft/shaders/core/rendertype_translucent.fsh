#version 420

#moj_import <fog.glsl>

uniform sampler2D Sampler0;

uniform vec4 ColorModulator;
uniform float FogStart;
uniform float FogEnd;
uniform vec4 FogColor;

in float vertexDistance;
in vec4 vertexColor;
in vec2 texCoord0;
in vec3 vertexPos;

out vec4 fragColor;

void main() {
    vec4 color = texture(Sampler0, texCoord0);
    if (vertexColor.b > vertexColor.r) {
        vec3 normal = normalize(cross(dFdx(vertexPos), dFdy(vertexPos)));
        fragColor = color;
        fragColor.r = (int(round((normal.x * 0.5 + 0.5) * 16)) << 4 | int(round((normal.z * 0.5 + 0.5) * 16))) / 255.0;
        fragColor.a = 1.0;
        return;
    }
    if (distance(color.rgb, vec3(1, 0, 1)) < 0.01) {
        discard;
    }
    fragColor = linear_fog(color * vertexColor * ColorModulator, vertexDistance, FogStart, FogEnd, FogColor);
}
