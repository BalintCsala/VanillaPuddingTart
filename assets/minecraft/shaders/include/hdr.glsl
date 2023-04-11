#ifndef HDR_GLSL
#define HDR_GLSL

const float MAX_BRIGHTNESS = 30.0;
const float BRIGHTNESS_CURVE = 0.1;

vec4 encodeHDRColor(vec3 color) {
    color /= MAX_BRIGHTNESS;
    color = clamp(color, 0.0, 1.0);
    color = pow(color, vec3(BRIGHTNESS_CURVE));
    color *= vec3(2047.0, 2047.0, 1023.0);
    uvec3 rawOutput = uvec3(round(color)) << uvec3(0, 11, 22);
    uint result = rawOutput.x | rawOutput.y | rawOutput.z;
    return vec4(
        result & 255u,
        (result >> 8u) & 255u,
        (result >> 16u) & 255u,
        result >> 24u
    ) / 255.0;
}

vec3 decodeHDRColor(vec4 raw) {
    uvec4 scaled = uvec4(raw * 255.0) << uvec4(0, 8, 16, 24);
    uint data = scaled.x | scaled.y | scaled.z | scaled.w;
    vec3 color = vec3(
        float(data & 2047u),
        float((data >> 11u) & 2047u),
        float(data >> 22u)
    );
    color /= vec3(2047.0, 2047.0, 1023.0);
    color = pow(color, vec3(1.0 / BRIGHTNESS_CURVE));
    return color * MAX_BRIGHTNESS;
}

float luminance(vec3 color) {
    return dot(color, vec3(0.2125, 0.7154, 0.0721));
}

#endif // HDR_GLSL