#version 150

in vec2 texCoord;
in vec3 sunDir;
in mat4 projMat;
in mat4 modelViewMat;
in vec3 chunkOffset;
in vec3 rayDir;
in float near;
in float far;
in mat4 projInv;
flat in uint frame;
in vec3 sunColor;

uniform sampler2D DiffuseSampler;
uniform sampler2D DiffuseDepthSampler;
uniform sampler2D DataSampler;
uniform sampler2D DataDepthSampler;

uniform sampler2D AlbedoAtlas;
uniform sampler2D NormalAtlas;
uniform sampler2D SpecularAtlas;

uniform sampler2D SteveSampler;

uniform vec2 InSize;

out vec4 fragColor;

const ivec2 GRID_SIZE = ivec2(1024, 705);
const int AREA_SIDE_LENGTH = int(pow(float(GRID_SIZE.x * GRID_SIZE.y / 2), 1.0 / 3.0));

const float EPSILON = 0.001;
const float PI = 3.141592654;
const float SUN_SIZE_FACTOR = 0.97;
const float SUN_INTENSITY = 15.0;
const float EMISSION_STRENGTH = 20.0;

const vec3 SKY_COLOR = vec3(49, 100, 255) / 255.0;
const float GAMMA_CORRECTION = 2.2;

// RANDOM

uint state;

uint rand() {
	state = (state << 13U) ^ state;
    state = state * (state * state * 15731U + 789221U) + 1376312589U;
    return state;
}

float randFloat() {
    return float(rand() & uvec3(0x7fffffffU)) / float(0x7fffffff);
}

vec2 randVec2() {
    return vec2(randFloat(), randFloat());
}

vec3 randVec3() {
    return vec3(randFloat(), randFloat(), randFloat());
}

vec4 randVec4() {
    return vec4(randFloat(), randFloat(), randFloat(), randFloat());
}

void initRNG(uvec2 pixel, uvec2 resolution, uint frame) {
    state = frame;
    state = (pixel.x + pixel.y * resolution.x) ^ rand();
    rand();
}

// VOXELIZATION

ivec2 positionToCell(vec3 position, out bool inside) {
    ivec3 sides = ivec3(AREA_SIDE_LENGTH);

    ivec3 iPosition = ivec3(floor(position));
    iPosition += sides / 2;

    inside = true;
    if (clamp(iPosition, ivec3(0), sides - 1) != iPosition) {
        inside = false;
        return ivec2(-1);
    }

    int index = (iPosition.y * sides.z + iPosition.z) * sides.x + iPosition.x;
    
    int halfWidth = GRID_SIZE.x / 2;
    ivec2 result = ivec2(
        (index % halfWidth) * 2,
        index / halfWidth + 1
    );
    result.x += result.y % 2;

    return result;
}

ivec2 cellToPixel(ivec2 cell) {
    return ivec2(round(vec2(cell) / GRID_SIZE * InSize));
}

// UTILS

vec3 screenToView(vec3 screenPos, mat4 projInv) {
    vec4 ndc = vec4(screenPos * 2.0 - 1.0, 1.0);
    vec4 viewPos = projInv * ndc;
    return viewPos.xyz / viewPos.w;
}

vec3 cosineWeighted(vec3 normal) {
    vec2 v = randVec2();
    float angle = 2.0 * PI * v.x;
    float u = 2.0 * v.y - 1.0;

    vec3 directionOffset = vec3(sqrt(1.0 - u * u) * vec2(cos(angle), sin(angle)), u);
    return normalize(normal + directionOffset);
}

vec3 viewToScreen(vec3 viewPos) {
    vec4 clipEnd = projMat * vec4(viewPos, 1);
    return clipEnd.xyz / clipEnd.w * 0.5 + 0.5;
}

// MAIN 

vec3 getNormal(vec2 texCoord, float depth, vec3 viewPos) {
    vec2 off = 1.0 / InSize * 1.01;
    vec2 right = texCoord + vec2(off.x, 0);
    vec2 left = texCoord + vec2(-off.x, 0);
    vec2 top = texCoord + vec2(0, off.y);
    vec2 bottom = texCoord + vec2(0, -off.y);
    
    float depthRight = texture(DiffuseDepthSampler, right).r;
    float depthLeft = texture(DiffuseDepthSampler, left).r;
    float depthTop = texture(DiffuseDepthSampler, top).r;
    float depthBottom = texture(DiffuseDepthSampler, bottom).r;
    float depthX, depthY;
    vec2 texCoordX, texCoordY;
    float mul = 1.0;
    
    if (abs(depthRight - depth) < abs(depthLeft - depth)) {
        depthX = depthRight;
        texCoordX = right;
    } else {
        depthX = depthLeft;
        texCoordX = left;
        mul *= -1.0;
    }
    if (abs(depthTop - depth) < abs(depthBottom - depth)) {
        depthY = depthTop;
        texCoordY = top;
    } else {
        depthY = depthBottom;
        texCoordY = bottom;
        mul *= -1.0;
    }
    
    vec3 viewPosX = screenToView(vec3(texCoordX, depthX), projInv);
    vec3 viewPosY = screenToView(vec3(texCoordY, depthY), projInv);
    vec3 viewNormal = normalize(cross(viewPosX - viewPos, viewPosY - viewPos)) * mul;
    return viewNormal * mat3(modelViewMat);
}

bool isSolid(ivec3 blockPos) {
    bool inside;
    ivec2 cell = positionToCell(vec3(blockPos), inside);
    if (!inside)
        return false;
    ivec2 pixel = cellToPixel(cell);
    return texelFetch(DataDepthSampler, pixel, 0).r == 0.0;
}

struct Material {
    vec3 albedo;
    vec3 normal;
    float ambientOcclusion;
    float roughness;
    vec3 F0;
    float emission;
    bool metal;
};

const vec3 PREDETERMINED_F0[] = vec3[](
    vec3(0.53123, 0.51236, 0.49583), // Iron
    vec3(0.94423, 0.77610, 0.37340), // Gold
    vec3(0.91230, 0.91385, 0.91968), // Aluminium
    vec3(0.55560, 0.55454, 0.55478), // Chrome
    vec3(0.92595, 0.72090, 0.50415), // Copper
    vec3(0.63248, 0.62594, 0.64148), // Lead
    vec3(0.67885, 0.64240, 0.58841), // Platinum
    vec3(0.96200, 0.94947, 0.92212)  // Silver
);

float luma(vec3 rgb) {
    return dot(rgb, vec3(0.2125, 0.7154, 0.0721));
}

void getTangentBitangent(vec3 normal, out vec3 tangent, out vec3 bitangent) {
    if (abs(normal.x) > 0.5) {
        tangent = vec3(0, 0, 1);
    } else {
        tangent = vec3(1, 0, 0);
    }
    bitangent = cross(tangent, normal);
}

Material getMaterial(ivec3 blockPos, vec2 texCoord, vec3 geometryNormal) {
    bool inside;
    ivec2 cell = positionToCell(vec3(blockPos), inside);
    ivec2 pixel = cellToPixel(cell);
    if (!inside || texelFetch(DataDepthSampler, pixel, 0).r > 0.0) {
        return Material(
            vec3(1),
            geometryNormal,
            1.0,
            0.5,
            vec3(0.04),
            0.0,
            false
        );
    }
    uvec4 dataRaw = uvec4(round(texelFetch(DataSampler, pixel, 0) * 255.0)) << uvec4(0u, 8u, 16u, 0u);
    uint data = dataRaw.r | dataRaw.g | dataRaw.b;
    vec3 tintColor = vec3(
        float(dataRaw.a & 3u) / 3.0,
        float((dataRaw.a >> 2u) & 7u) / 7.0,
        float(dataRaw.a >> 5u) / 3.0
    );
    
    int size = int(exp2(float(4u + (data >> 22u))));
    ivec2 pos = ivec2(
        data & 2047u,
        (data >> 11u) & 2047u
    ) * 16;
    ivec2 atlasTexCoord = pos + ivec2(texCoord * size);
    
    vec3 albedo = pow(texelFetch(AlbedoAtlas, atlasTexCoord, 0).rgb * tintColor, vec3(GAMMA_CORRECTION));
    vec3 normalData = texelFetch(NormalAtlas, atlasTexCoord, 0).rgb;
    if (dot(normalData.xy, normalData.xy) < 0.01) {
        normalData.xy = vec2(0.5);
        normalData.z = 1.0;
    }
    
    vec3 specularData = texelFetch(SpecularAtlas, atlasTexCoord, 0).rgb;
    
    vec3 F0 = vec3(specularData.y);
    int index = int(round(specularData.y * 255.0));
    bool metal = index >= 230;
    if (index == 255) {
        F0 = albedo;
        albedo = vec3(1);
    } else if (metal) {
        F0 = PREDETERMINED_F0[index - 230];
    }
    
    vec3 tangent, bitangent;
    getTangentBitangent(geometryNormal, tangent, bitangent);
    mat3 tbn = mat3(tangent, bitangent, geometryNormal);
    normalData.xy = normalData.xy * 2.0 - 1.0;
    
    return Material(
        albedo,
        tbn * normalize(vec3(normalData.xy, sqrt(1.0 - dot(normalData.xy, normalData.xy)))),
        normalData.z,
        (1.0 - specularData.x) * (1.0 - specularData.x),
        F0,
        specularData.z == 1.0 ? 0.0 : specularData.z,
        metal
    );
}

struct Hit {
    bool hit;
    float t;
    vec3 geometryNormal;
    Material material;
};

Hit noHit() {
    Hit hit;
    hit.hit = false;
    return hit;
}

struct Ray {
    vec3 origin;
    ivec3 cell;
    vec3 direction;
};

vec2 getTexCoord(vec3 pos, vec3 normal) {
    vec3 absNormal = abs(normal);
    float maxNormal = max(absNormal.x, max(absNormal.y, absNormal.z));
    vec3 flatNormal = vec3(greaterThanEqual(absNormal, vec3(maxNormal))) * sign(normal);
    vec3 fractPos = fract(pos);
    return max(flatNormal.x, 0.0) * vec2(1.0 - fractPos.z, 1.0 - fractPos.y) +
        max(-flatNormal.x, 0.0) * vec2(fractPos.z, 1.0 - fractPos.y) +
        max(flatNormal.y, 0.0) * vec2(fractPos.x, fractPos.z) +
        max(-flatNormal.y, 0.0) * vec2(fractPos.x, 1.0 - fractPos.z) +
        max(flatNormal.z, 0.0) * vec2(fractPos.x, 1.0 - fractPos.y) +
        max(-flatNormal.z, 0.0) * vec2(1.0 - fractPos.x, 1.0 - fractPos.y);
}

Hit raytrace(inout Ray ray) {
    const int MAX_RT_STEPS = 55;
    vec3 nextEdge = max(sign(ray.direction), 0.0);
    vec3 steps = (nextEdge - fract(ray.origin)) / ray.direction;
    vec3 originalStepSizes = abs(1.0 / ray.direction);
    vec3 rdSign = sign(ray.direction);
    
    float t = 0.0;
    for (int i = 0; i < MAX_RT_STEPS; i++) {
        float stepSize = min(steps.x, min(steps.y, steps.z));
        ray.origin += ray.direction * stepSize;
        vec3 stepAxis = vec3(lessThanEqual(steps, vec3(stepSize)));
        ivec3 nextCell = ray.cell + ivec3(stepAxis * rdSign);
        t += stepSize;
        
        if (isSolid(nextCell)) {
            vec3 normal = -stepAxis * rdSign;
            vec2 texCoord = getTexCoord(ray.origin, normal);
            ray.origin += normal * 0.001;
            
            Hit hit = Hit(true, t, normal, getMaterial(nextCell, texCoord, normal));
            return hit;
        }
        
        steps += originalStepSizes * stepAxis - stepSize;
        ray.cell = nextCell;
    }
    return noHit();
}

vec3 fresnel(vec3 F0, float cosTheta) {
    return F0 + (1.0 - F0) * pow(max(1.0 - cosTheta, 0.0), 5);
}

float traceSteve(Ray ray, vec3 point, vec3 normal, out vec2 uv) {
    float t = dot(point - ray.origin, normal) / dot(ray.direction, normal);
    vec3 hitPoint = ray.origin + ray.direction * t;
    vec3 bitangent = vec3(0, 1, 0);
    vec3 tangent = normalize(cross(bitangent, normal));
    uv = vec2(dot(tangent, hitPoint - point), dot(-bitangent, hitPoint - point));
    uv *= vec2(1.0, 22.0 / 39.0) * 1.875;
    uv = uv * 0.5 + 0.5 - vec2(0, 0.35);
    if (clamp(uv, vec2(0.0), vec2(1.0)) != uv)
        return -1.0;
    return t;
}

bool checkSun(vec3 hitPos, ivec3 hitCell) {
    Ray sunRay = Ray(hitPos, hitCell, mix(cosineWeighted(sunDir), sunDir, SUN_SIZE_FACTOR));
    return !raytrace(sunRay).hit;
}

vec3 getNextRayDirection(Material material, vec3 rayDir, vec3 geometryNormal) {
    if (material.metal) {
        vec3 reflected = reflect(rayDir, material.normal);
        return mix(reflected, cosineWeighted(geometryNormal), material.roughness);
    } else {
        return cosineWeighted(material.normal);
    }
}

vec3 pathtrace(vec3 playerPos, vec3 normal) {
    vec2 texCoord = getTexCoord(playerPos - fract(chunkOffset), normal);
    Material material = getMaterial(ivec3(floor(playerPos - fract(chunkOffset) - normal * 0.1)), texCoord, normal);
    
    vec3 radiance = material.albedo * material.emission * EMISSION_STRENGTH;
    vec3 throughput = vec3(1.0);
    
    vec3 rayDir = getNextRayDirection(material, normalize(playerPos), normal);
    throughput *= fresnel(material.F0, max(dot(-rayDir, normal), 0.0));
    
    Ray ray = Ray(playerPos - fract(chunkOffset), ivec3(floor(playerPos - fract(chunkOffset))), rayDir);
    
    if (!material.metal) {
        if (checkSun(ray.origin, ray.cell)) {
            radiance += max(dot(material.normal, sunDir), 0.0) / PI * throughput * SUN_INTENSITY * sunColor;
        }
        
        throughput *= material.ambientOcclusion;
    }
    
    for (int i = 0; i < 3; i++) {
        vec2 steveUV;
        vec3 steveNormal = -transpose(modelViewMat)[2].xyz;
        float steveDist = traceSteve(ray, -fract(chunkOffset), steveNormal, steveUV);
        vec4 steveColor = texture(SteveSampler, steveUV);
        vec3 steveHitPoint = ray.origin + ray.direction * steveDist;
        Hit hit = raytrace(ray);
        if (steveDist > 0.0 && (!hit.hit || hit.t > steveDist) && steveColor.a > 0.0) {
            hit = Hit(
                true, 
                steveDist, 
                steveNormal, 
                Material(
                    steveColor.rgb,
                    steveNormal,
                    0.0,
                    0.5,
                    vec3(0.04),
                    0.0,
                    false
                )
            );
            ray.origin = steveHitPoint + steveNormal * 0.01;
            ray.cell = ivec3(floor(ray.origin));
        } else if (!hit.hit) {
            radiance += SKY_COLOR * throughput;
        }
        radiance += hit.material.emission * hit.material.albedo * throughput * EMISSION_STRENGTH;
        
        vec3 nextRayDir = getNextRayDirection(hit.material, ray.direction, hit.geometryNormal);
        
        throughput *= fresnel(hit.material.F0, max(dot(-nextRayDir, hit.geometryNormal), 0.0));
        
        throughput *= hit.material.albedo;
        
        if (checkSun(ray.origin, ray.cell)) {
            radiance += max(dot(hit.material.normal, sunDir), 0.0) / PI * throughput * SUN_INTENSITY * sunColor;
        }
        
        if (!material.metal) {
            throughput *= material.ambientOcclusion;
        }
        
        ray.direction = nextRayDir;
    }
    return radiance;
}

vec4 encodeHDRColor(vec3 color) {
    uvec3 rawOutput = uvec3(round(color * 128.0)) << uvec3(0, 11, 22);
    uint result = rawOutput.x | rawOutput.y | rawOutput.z;
    return vec4(
        result & 255u,
        (result >> 8u) & 255u,
        (result >> 16u) & 255u,
        result >> 24u
    ) / 255.0;
}

void main() {
    ivec2 fragCoord = ivec2(gl_FragCoord.xy);
    initRNG(uvec2(fragCoord), uvec2(InSize), frame);
    
    float depth = texture(DiffuseDepthSampler, texCoord).r;
    vec3 albedo = pow(texture(DiffuseSampler, texCoord).rgb, vec3(GAMMA_CORRECTION));
    if (depth == 1.0) {
        fragColor = encodeHDRColor(albedo);
        return;
    }
    
    vec3 screenPos = vec3(texCoord, depth);
    vec3 viewPos = screenToView(screenPos, projInv);
    vec3 playerPos = viewPos * mat3(modelViewMat);
    vec3 normal = normalize(cross(dFdx(playerPos), dFdy(playerPos)));//getNormal(texCoord, depth, viewPos);
    vec3 radiance = pathtrace(playerPos, normal);
    
    vec3 outputColor = pow(radiance, vec3(1.0 / GAMMA_CORRECTION));
    fragColor = encodeHDRColor(outputColor);
}