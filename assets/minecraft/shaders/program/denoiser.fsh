#version 150

const float EPSILON = 0.01;

in vec2 texCoord;
in vec2 oneTexel;
in mat4 currProjMat;
in mat4 currModelViewMat;
in mat4 prevProjMat;
in mat4 prevModelViewMat;
in mat4 projInv;
in vec3 rayDir;
in float near;
in float far;
in vec3 prevPosition;

uniform sampler2D DiffuseSampler;
uniform sampler2D CurrentFrameDepthSampler;
uniform sampler2D PreviousFrameSampler;
uniform sampler2D PreviousFrameDepthSampler;

out vec4 fragColor;

vec3 calculateWorldPos(float depth, vec2 texCoord, mat4 projMat, mat4 modelViewMat) {
    vec4 clip = vec4(texCoord * 2 - 1, depth, 1);
    vec4 viewSpace = inverse(projMat) * clip;
    viewSpace /= viewSpace.w;
    return (inverse(modelViewMat) * viewSpace).xyz;
}

void main() {
    vec3 currColor = texture(DiffuseSampler, texCoord).rgb;
    vec3 prevColor = texture(PreviousFrameSampler, texCoord).rgb;
    fragColor = vec4(currColor, 1);

    // Reprojection based aliasing

    // We'll recreate the current world position from the texture coord and depth sampler
    float currDepth = texture(CurrentFrameDepthSampler, texCoord).r * 2 - 1;
    vec3 worldPos = calculateWorldPos(currDepth, texCoord, currProjMat, currModelViewMat);
    // Then we offset this by the amount the player moved between the two frames
    vec3 prevRelativeWorldPos = worldPos - prevPosition;

    // We can then convert this into the texture coord of the fragment in the previous frame
    vec4 prevClip = prevProjMat * prevModelViewMat * vec4(prevRelativeWorldPos, 1);
    vec2 prevTexCoord = (prevClip.xy / prevClip.w + 1) / 2;

    // Throw away the previous data if the uvs fall outside of the screen area
    if (any(greaterThan(abs(prevTexCoord - 0.5), vec2(0.5))) || currDepth > 1 - 1e-6) {
        return;
    }

    // We'll reproject this back into world pos to check for occlusions
    float prevDepth = texture(PreviousFrameDepthSampler, prevTexCoord).r * 2 - 1;
    vec3 prevWorldPos = calculateWorldPos(prevDepth, prevTexCoord, prevProjMat, prevModelViewMat);

    if (length(worldPos - prevWorldPos - prevPosition) < EPSILON * length(worldPos)) {
        // If the distance between the two fragments are similar, we use them for denoising
        fragColor.rgb = mix(fragColor.rgb, texture(PreviousFrameSampler, prevTexCoord).rgb, 0.9);
    }
}