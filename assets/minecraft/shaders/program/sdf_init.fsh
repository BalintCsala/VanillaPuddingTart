#version 150

const vec2 VOXEL_STORAGE_RESOLUTION = vec2(1024, 705);

const float EPSILON = 0.00001;

in vec2 texCoord;

uniform sampler2D DiffuseSampler;

out vec4 fragColor;

void main() {
    vec2 uv = (floor(texCoord * (VOXEL_STORAGE_RESOLUTION - 1)) + 0.5) / (VOXEL_STORAGE_RESOLUTION - 1);
    vec3 rawData = texture(DiffuseSampler, uv).rgb;
    float val = (rawData.r + rawData.g + rawData.b + EPSILON < 3) ? 0 : 1;
    fragColor = vec4(val / 255.0, 0, 0, 1);
}