#version 150

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

// From a presentation given by Lasse Jon Fuglsang Pedersen titled "Temporal Reprojection Anti-Aliasing in INSIDE"
// https://www.youtube.com/watch?v=2XXS5UyNjjU&t=434s
vec3 clipColor(vec3 aabbMin, vec3 aabbMax, vec3 prevColor) {
    // Center of the clip space
    vec3 pClip = (aabbMax + aabbMin) / 2;
    // Size of the clip space
    vec3 eClip = (aabbMax - aabbMin) / 2;

    // The relative coordinates of the previous color in the clip space
    vec3 vClip = prevColor - pClip;
    // Normalized clip space coordintes
    vec3 vUnit = vClip / eClip;
    // The distance of the previous color from the center of the clip space in each axis in the normalized clip space
    vec3 aUnit = abs(vUnit);
    // The divisor is the largest distance from the center along each axis
    float divisor = max(aUnit.x, max(aUnit.y, aUnit.z));
    if (divisor > 1) {
        // If the divisor is larger, than 1, that means that the previous color is outside of the clip space
        // If we divide by divisor, we'll put it into clip space
        return pClip + vClip / divisor;
    }
    // Otherwise it's already clipped
    return prevColor;
}

void main() {
    vec3 currColor = texture(DiffuseSampler, texCoord).rgb;
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
    if (any(greaterThan(abs(prevTexCoord - 0.5), vec2(0.5)))) {
        return;
    }

    // We'll reproject this back into world pos to check for occlusions
    float prevDepth = texture(PreviousFrameDepthSampler, prevTexCoord).r * 2 - 1;
    vec3 prevWorldPos = calculateWorldPos(prevDepth, prevTexCoord, prevProjMat, prevModelViewMat);

    // Temporal antialiasing from same talk mentioned earlier
    vec3 prevColor = texture(PreviousFrameSampler, prevTexCoord).rgb;
    // We'll calculate the color space from the neighbouring texels
    vec3 minCol = vec3(1);
    vec3 maxCol = vec3(0);
    for (float x = -1; x <= 1; x++) {
        for (float y = -1; y <= 1; y++) {
            vec3 neighbor = texture(DiffuseSampler, texCoord + vec2(x, y) * oneTexel).rgb;
            minCol = min(minCol, neighbor);
            maxCol = max(maxCol, neighbor);
        }
    }

    // Then we'll clip the previous color into the clip space
    vec3 clippedPrevColor = clipColor(minCol, maxCol, prevColor);
    // And use the clipped value for aliasing
    fragColor.rgb = mix(fragColor.rgb, clippedPrevColor, 0.5);
}