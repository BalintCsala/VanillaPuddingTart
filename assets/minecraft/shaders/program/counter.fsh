#version 420

uniform sampler2D DiffuseSampler;

out vec4 fragColor;

uint readCounter() {
    uvec4 raw = uvec4(texelFetch(DiffuseSampler, ivec2(0), 0) * 255.0);
    return (raw.z << 16u) | (raw.y << 8u) | raw.x;
}

void main() {
    uint frame =  readCounter() + 1u;
    vec4 result = vec4(
        frame & 255u,
        (frame >> 8u) & 255u,
        (frame >> 16u) & 255u,
        255
    ) / 255.0;
    fragColor = result;
}