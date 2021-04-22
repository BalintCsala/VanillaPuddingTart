#version 150

#moj_import <utils.glsl>

in vec3 Position;

uniform mat4 ModelViewMat;
uniform mat4 ProjMat;

out float isSky;
out vec4 glpos;

const float BOTTOM = -32.0;
const float SCALE = 0.01;
const float SKYHEIGHT = 16.0;
const float SKYRADIUS = 512.0;
const float FUDGE = 0.004;

void main() {
    // "position.vsh" is only responsible for the sky.
    // We will use it for two things, we can give the background a constant white color and we can also pass some
    // crucial information to the post shaders (the model-view and the projection matrices).
    // Code is from the sun-position shader from thebbq https://github.com/bradleyq/shader-toolkit/blob/main/sun-position
    vec3 scaledPos = Position;
    if (abs(scaledPos.y  - SKYHEIGHT) < FUDGE && (length(scaledPos.xz) <= FUDGE || abs(length(scaledPos.xz) - SKYRADIUS) < FUDGE)) {
        isSky = 1.0;

        // Make sky into a cone by bringing down edges of the disk.
        if (length(scaledPos.xz) > 1.0) {
            scaledPos.y = BOTTOM;
        }

        // Make it big so it does not interfere with void plane.
        scaledPos.xyz *= SCALE;

        // rotate to z axis
        scaledPos = scaledPos.xzy;
        scaledPos.z *= -1;

        // ignore model view so the cone follows the camera angle.
        gl_Position = ProjMat * vec4(scaledPos, 1.0);
    } else {
        gl_Position = ProjMat * ModelViewMat * vec4(scaledPos, 1.0);
    }
}
