#version 420

in vec2 texCoord;
in mat3 modelViewMat;
in vec3 chunkOffset;
in mat4 projInv;

uniform sampler2D DiffuseSampler;
uniform sampler2D CounterSampler;
uniform sampler2D DepthSampler;
uniform sampler2D VoronoiSampler;

out vec4 fragColor;

int readCounter() {
    ivec4 raw = ivec4(texelFetch(CounterSampler, ivec2(0), 0) * 255.0);
    return (raw.z << 16) | (raw.y << 8) | raw.x;
}

vec3 screenToView(vec3 screenPos, mat4 projInv) {
    vec4 ndc = vec4(screenPos * 2.0 - 1.0, 1.0);
    vec4 viewPos = projInv * ndc;
    return viewPos.xyz / viewPos.w;
}

void main() {
    float time = float(readCounter()) / 60.0;
    vec4 color = texture(DiffuseSampler, texCoord);
    if (distance(color.gba, vec3(1)) > 0.001) {
        fragColor = vec4(0);
        return;
    }
    
    float depth = texture(DepthSampler, texCoord).r;
    vec3 screenPos = vec3(texCoord, depth);
    vec3 view = screenToView(screenPos, projInv);
    vec3 playerPos = view * modelViewMat - chunkOffset;
    
    vec3 normal;
    int normalIndex = int(round(color.r * 255.0));
    vec3 surfaceNormal = vec3(
        (normalIndex >> 4) / 16.0 * 2.0 - 1.0,
        0.0,
        (normalIndex & 15) / 16.0 * 2.0 - 1.0
    );
    surfaceNormal.y = sqrt(1.0 - dot(surfaceNormal.xz, surfaceNormal.xz));
    
    const vec2[] DIRECTIONS = vec2[](
        normalize(vec2(1.0, 1.0)),
        normalize(vec2(-1.0, -0.3)),
        normalize(vec2(0.2, -1.0)),
        normalize(vec2(-0.3, 0.7))
    );
    
    const float[] SPEEDS = float[](
        0.04,
        0.03,
        0.02,
        0.04
    );
    float height = 0.0;
    float weight = 0.02;
    for (int i = 0; i < 4; i++) {
        height += (1.0 - texture(VoronoiSampler, playerPos.xz / 2.0 + DIRECTIONS[i] * time * SPEEDS[i])[i]) * weight;
        weight /= 2.0;
    }
    if (surfaceNormal.y > 0.9) {
        normal = normalize(cross(
            dFdx(vec3(playerPos.x, height, playerPos.z)),
            dFdy(vec3(playerPos.x, height, playerPos.z))
        ));
    } else {
        normal = surfaceNormal;
    }
    fragColor = vec4(normal * 0.5 + 0.5, 1.0);
}