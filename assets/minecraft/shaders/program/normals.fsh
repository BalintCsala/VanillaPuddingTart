#version 150

in vec2 texCoord;
in mat4 projInv;
uniform sampler2D DiffuseDepthSampler;

out vec4 fragColor;

void main() {
    vec3 screenPos = vec3(
        texCoord,
        texture(DiffuseDepthSampler, texCoord).r
    );
    if (screenPos.z == 1.0) {
        fragColor = vec4(0, 0, 1, 1);
        return;
    }
    
    vec4 temp = projInv * vec4(screenPos * 2.0 - 1.0, 1);
    vec3 viewPos = temp.xyz / temp.w;
    vec3 normal = normalize(cross(dFdx(viewPos), dFdy(viewPos)));
    fragColor = vec4(normal * 0.5 + 0.5, 1);
}