#version 150

const float HORIZONDIST = 128;

in vec3 Position;
in vec4 Color;

uniform mat4 ModelViewMat;
uniform mat4 ProjMat;

out vec4 vertexColor;
out float isHorizon;

void main() {
    gl_Position = ProjMat * ModelViewMat * vec4(Position, 1.0);
    isHorizon = 0.0;

    if ((ModelViewMat * vec4(Position, 1.0)).z > -HORIZONDIST - 10.0) {
        isHorizon = 1.0;
    }

    vertexColor = Color;
}
