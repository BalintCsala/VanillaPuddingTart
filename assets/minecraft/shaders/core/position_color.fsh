#version 150

in vec4 vertexColor;
in float isHorizon;

uniform vec4 ColorModulator;

out vec4 fragColor;

void main() {
    if (isHorizon > 0.5) {
        discard;
    }

    vec4 color = vertexColor;
    if (color.a == 0.0) {
        discard;
    }
    fragColor = color * ColorModulator;
}
