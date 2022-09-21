#version 150

in vec2 texCoord;
in mat4 projMat;
in mat3 modelViewMat;
in mat4 prevProjMat;
in mat3 prevModelViewMat;
in mat4 projInv;
in vec3 cameraOffset;
in float near;
in float far;

uniform sampler2D DiffuseDepthSampler;
uniform sampler2D PrevDiffuseDepthSampler;
uniform sampler2D PrevTAASampler;

uniform vec2 InSize;

out vec4 fragColor;

float linearizeDepth(float depth) {
    return (near * far) / (depth * (near - far) + far);
}

vec3 screenToView(vec3 screenPos) {
    vec4 ndc = vec4(screenPos * 2.0 - 1.0, 1.0);
    vec4 viewPos = projInv * ndc;
    return viewPos.xyz / viewPos.w;
}

void main() {
    float depth = texture(DiffuseDepthSampler, texCoord).r;
    if (depth == 1.0) {
        fragColor = vec4(0.0, 0.0, 0.0, 1.0 / 255.0);
        return;
    }
    vec3 playerPos = screenToView(vec3(texCoord, depth)) * modelViewMat;
    vec3 prevPlayerPos = playerPos - cameraOffset;
    vec4 prevClipPos = prevProjMat * vec4(prevModelViewMat * prevPlayerPos, 1.0);
    vec3 prevScreenPos = prevClipPos.xyz / prevClipPos.w * 0.5 + 0.5;
    
    vec2 offset = (prevScreenPos.xy - texCoord) * InSize;
    if (clamp(prevScreenPos.xy, 0.0, 1.0) != prevScreenPos.xy || max(abs(offset.x), abs(offset.y)) > 127.5) {
        fragColor = vec4(0.0, 0.0, 0.0, 1.0 / 255.0);
        return;
    }
    
    float prevDepth = texture(PrevDiffuseDepthSampler, prevScreenPos.xy).r;
    if (abs(linearizeDepth(depth) - linearizeDepth(prevDepth)) > 0.5) {
        fragColor = vec4(0.0, 0.0, 0.0, 1.0 / 255.0);
        return;
    }
    
    uint counter = uint(texture(PrevTAASampler, texCoord).a * 255.0);
    counter = min(counter + 1u, 255u);
    
    uvec2 offsetDataRaw = uvec2(round((offset + 128.0) * 16.0)) << uvec2(12u, 0u);
    uint offsetData = offsetDataRaw.x | offsetDataRaw.y;
    fragColor = vec4(
        offsetData >> 16u,
        (offsetData >> 8u) & 255u,
        offsetData & 255u,
        255.0
    ) / 255.0;
}