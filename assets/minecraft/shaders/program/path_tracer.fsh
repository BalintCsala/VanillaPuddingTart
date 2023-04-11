#version 420

#include<hdr.glsl>
#include<constants.glsl>
#include<rand.glsl>
#include<voxelization.glsl>
#include<conversions.glsl>
#include<materialMask.glsl>
#include<quaternions.glsl>
#line 10 0

in vec2 texCoord;
in vec3 sunDir;
in mat4 projMat;
in mat3 modelViewMat;
in vec3 chunkOffset;
in vec3 rayDir;
in float near;
in float far;
in mat4 projInv;
flat in uint frame;
in vec3 sunColor;
in float renderScale;
in vec3 steveDirection;
flat in ivec2 atlasSize;

uniform sampler2D DiffuseSampler;
uniform sampler2D DepthSampler;
uniform sampler2D WaterSampler;
uniform sampler2D NormalSampler;

uniform sampler2D VoxelSampler;
uniform sampler2D VoxelDepthSampler;

uniform sampler2D Atlas;
uniform sampler2D Models;
uniform sampler2D SteveSampler;

uniform vec2 InSize;

out vec4 fragColor;

const float SUN_SIZE_FACTOR = 0.97;
const float SUN_INTENSITY = 5.0;
const float EMISSION_STRENGTH = 30.0;
const float WATER_F0 = (1.333 - 1.0) * (1.333 - 1.0) / (1.333 + 1.0) / (1.333 + 1.0);

const vec3 SKY_COLOR = vec3(30, 60, 255) / 255.0 * 0.8;
const float GAMMA_CORRECTION = 2.2;

const float ANGLE_22_5 = 0.39269908169872414;

struct Ray {
    vec3 origin;
    ivec3 cell;
    vec3 direction;
};

// UTILS

vec3 cosineWeighted(vec3 normal) {
    vec2 v = randVec2();
    float angle = 2.0 * PI * v.x;
    float u = 2.0 * v.y - 1.0;

    vec3 directionOffset = vec3(sqrt(1.0 - u * u) * vec2(cos(angle), sin(angle)), u);
    return normalize(normal + directionOffset);
}

// MAIN 

vec2 boxIntersection( in vec3 ro, in vec3 rd, vec3 boxSize, out vec3 outNormal ) 
{
    vec3 m = 1.0/rd; // can precompute if traversing a set of aligned boxes
    vec3 n = m*ro;   // can precompute if traversing a set of aligned boxes
    vec3 k = abs(m)*boxSize;
    vec3 t1 = -n - k;
    vec3 t2 = -n + k;
    float tN = max( max( t1.x, t1.y ), t1.z );
    float tF = min( min( t2.x, t2.y ), t2.z );
    if( tN>tF || tF<0.0) return vec2(-1.0); // no intersection
    outNormal = (tN>=0.0) ? step(vec3(tN),t1) : // ro ouside the box
                           step(t2,vec3(tF));  // ro inside the box
    outNormal *= -sign(rd);
    return vec2( tN, tF );
}

bool isSolid(ivec2 pixel) {
    return texelFetch(VoxelDepthSampler, pixel, 0).r == 0.0;
}

struct Intersection {
    bool hit;
    mat3 tbn;
    vec2 uv;
    float dist;
    ivec2 pixel;
};

Intersection noIntersection() {
    Intersection res;
    res.hit = false;
    return res;
}

Intersection checkIntersection(ivec2 pixel, Ray ray) {
    ivec3 raw = ivec3(texelFetch(VoxelSampler, pixel, 0).rgb * 255.0);
    int index = raw.r | (raw.g << 8) | (raw.b << 16);
    int count = int(texelFetch(Models, ivec2(0, index), 0).r * 255.0);
    
    float minT = -1.0;
    vec2 uv;
    vec3 tangent;
    vec3 normal;
    for (int i = 0; i < count; i++) {
        const int bytesPerModel = 16;
        
        vec3 from = texelFetch(Models, ivec2(bytesPerModel * i + 1, index), 0).rgb * 3.0 - 1.0;
        vec3 to = texelFetch(Models, ivec2(bytesPerModel * i + 2, index), 0).rgb * 3.0 - 1.0;
        vec4 rotation = texelFetch(Models, ivec2(bytesPerModel * i + 3, index), 0);
        vec3 pivot = texelFetch(Models, ivec2(bytesPerModel * i + 4, index), 0).rgb - 0.5;
        
        float angle = (rotation.w * 255.0 - 2.0) * ANGLE_22_5;
        vec4 quaternion = vec4(
            -rotation.xyz * sin(angle / 2.0),
            cos(angle / 2.0)
        );
        
        vec3 size = (to - from) / 2.0;
        vec3 center = (from + to) / 2.0;
        vec3 newNormal;
        
        vec3 ro = ray.origin - ray.cell - center - ray.direction * 0.2;
        vec3 rd = ray.direction;
        
        ro -= pivot;
        ro = quaternionRotate(ro, quaternion);
        rd = quaternionRotate(rd, quaternion);
        ro += pivot;

        vec2 t = boxIntersection(ro, rd, size, newNormal);    
        if (minT < 0.0 || (t.x >= 0.0 && t.x < minT)) {
            vec3 hitPos = ro + rd * t.x;
            if (clamp(hitPos, -0.501, 0.501) != hitPos) continue;
            vec3 relativePos = (hitPos + size) / size / 2.0;
            int faceID;
            vec2 newUV;
            vec3 newTangent;
            if (newNormal.x > 0.99) {
                faceID = 4;
                newUV = vec2(1.0 - relativePos.z, 1.0 - relativePos.y);
                newTangent = vec3(0.0, 0.0, -1.0); 
            } else if (newNormal.x < -0.99) {
                faceID = 5;
                newUV = vec2(relativePos.z, 1.0 - relativePos.y);
                newTangent = vec3(0.0, 0.0, 1.0);
            } else if (newNormal.y > 0.99) {
                faceID = 1;
                newUV = vec2(relativePos.x, relativePos.z);
                newTangent = vec3(1.0, 0.0, 0.0);
            } else if (newNormal.y < -0.99) {
                faceID = 0;
                newUV = vec2(1.0 - relativePos.x, relativePos.z);
                newTangent = vec3(-1.0, 0.0, 0.0);
            } else if (newNormal.z > 0.99) {
                faceID = 2;
                newUV = vec2(relativePos.x, 1.0 - relativePos.y);
                newTangent = vec3(1.0, 0.0, 0.0);
            } else if (newNormal.z < -0.99) {
                faceID = 3;
                newUV = vec2(1.0 - relativePos.x, 1.0 - relativePos.y);
                newTangent = vec3(-1.0, 0.0, 0.0);
            }
            ivec4 textureData = ivec4(texelFetch(Models, ivec2(bytesPerModel * i + 5 + faceID * 2, index), 0) * 255.0);            
            if (textureData.a > 200)
                continue;
                
            vec4 uvData = texelFetch(Models, ivec2(bytesPerModel * i + 5 + faceID * 2 + 1, index), 0);
            int textureIndex = textureData.r | (textureData.g << 8) | (textureData.b << 16);
            vec2 topLeft = vec2(textureIndex & 1023, (textureIndex >> 10) & 1023);
            float size = exp2(float(textureIndex >> 20));
            
            newUV = (mix(uvData.xy, uvData.zw, newUV) * size + topLeft) * 16.0;
            
            if (texelFetch(Atlas, ivec2(newUV), 0).a < 0.5)
                continue;

            minT = t.x;
            uv = newUV;

            vec4 invQuaternion = vec4(-quaternion.xyz, quaternion.w);
            newNormal = quaternionRotate(newNormal, invQuaternion);
            newTangent = quaternionRotate(newTangent, invQuaternion);
            normal = newNormal;
            tangent = newTangent;
        }
    }

    mat3 tbn = mat3(tangent, cross(normal, tangent), normal);
    return Intersection(minT > 0.0, tbn, uv, minT - 0.2, pixel);
}

Intersection checkIntersection(Ray ray) {
    bool inside;
    ivec2 pixel = positionToPixel(vec3(ray.cell), inside);

    if (!inside || !isSolid(pixel))
        return noIntersection();

    return checkIntersection(pixel, ray);
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

Material defaultMaterial(vec3 normal) {
    return Material(
        vec3(1),
        normal,
        1.0,
        0.0,
        vec3(0.04),
        0.0,
        false
    );
}

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

mat3 getTBN(vec3 normal) {
    float xSign = abs(normal.x) < 0.1 ? 0.0 : sign(normal.x);
    float ySign = abs(normal.y) < 0.1 ? 0.0 : sign(normal.y);
    float zSign = abs(normal.z) < 0.1 ? 0.0 : sign(normal.z);
    vec3 tangent = vec3(zSign - ySign, 0, -xSign);
    vec3 bitangent = cross(tangent, normal);
    return mat3(tangent, bitangent, normal);
}

Material getMaterial(Intersection intersection) {
    uvec4 dataRaw = uvec4(round(texelFetch(VoxelSampler, intersection.pixel, 0) * 255.0)) << uvec4(0u, 8u, 16u, 0u);
    uint data = dataRaw.r | dataRaw.g | dataRaw.b;
    vec3 tintColor = vec3(
        float(dataRaw.a & 3u) / 3.0,
        float((dataRaw.a >> 2u) & 7u) / 7.0,
        float(dataRaw.a >> 5u) / 3.0
    );
    
    ivec2 atlasTexCoord = ivec2(intersection.uv);
    
    vec3 albedo = pow(texelFetch(Atlas, atlasTexCoord, 0).rgb * tintColor, vec3(GAMMA_CORRECTION));
    vec3 normalData = texelFetch(Atlas, atlasTexCoord + ivec2(atlasSize.x, 0), 0).rgb;
    vec3 normal;
    float ambientOcclusion;
    if (dot(normalData.xy, normalData.xy) < 0.01) {
        normal = intersection.tbn[2];
        ambientOcclusion = 1.0;
    } else {
        normalData.xy = normalData.xy * 2.0 - 1.0;
        normal = intersection.tbn * normalize(vec3(normalData.xy, sqrt(1.0 - dot(normalData.xy, normalData.xy)))),
        ambientOcclusion = normalData.b;
    }
    
    vec4 specularData = texelFetch(Atlas, atlasTexCoord + ivec2(0, atlasSize.y), 0);
    
    vec3 F0 = vec3(specularData.g);
    int index = int(round(specularData.g * 255.0));
    bool metal = index >= 230;
    if (index == 255) {
        F0 = albedo;
        albedo = vec3(1);
    } else if (metal) {
        F0 = PREDETERMINED_F0[index - 230];
    }
    
    return Material(
        albedo,
        normal,
        ambientOcclusion,
        (1.0 - specularData.r) * (1.0 - specularData.r),
        F0,
        specularData.a == 1.0 ? 0.0 : specularData.a,
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

struct PathTraceOutput {
    vec3 radiance;
    MaterialMaskData materialMask;
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

float traceSteve(Ray ray, vec3 point, vec3 normal, out vec2 uv) {
    float t = dot(point - ray.origin, normal) / dot(ray.direction, normal);
    vec3 hitPoint = ray.origin + ray.direction * t;
    vec3 bitangent = vec3(0, 1, 0);
    vec3 tangent = normalize(cross(bitangent, normal));
    uv = vec2(dot(tangent, hitPoint - point), dot(-bitangent, hitPoint - point));
    uv *= vec2(1.0, 22.0 / 39.0) * 1.875;
    uv = uv * 0.5 + 0.5 - vec2(0, 0.35);
    uv.x = 1.0 - uv.x;
    if (clamp(uv, vec2(0.0), vec2(1.0)) != uv)
        return -1.0;
    return t;
}

Hit raytrace(inout Ray ray, bool checkSteve, int maxSteps) {
    Intersection intersection = checkIntersection(ray);
    if (intersection.dist > 0.01) {
        vec3 normal = intersection.tbn[2];
        ray.origin += normal * 0.01;
        
        Hit hit = Hit(true, intersection.dist, normal, getMaterial(intersection));
        return hit;
    }

    // Steve
    vec2 steveUV;
    float steveDist = checkSteve ? traceSteve(ray, -fract(chunkOffset), steveDirection, steveUV) : -1.0;
    vec4 steveColor = checkSteve ? texture(SteveSampler, steveUV) : vec4(0.0);
    
    // Voxel tracing
    vec3 nextEdge = max(sign(ray.direction), 0.0);
    vec3 steps = (nextEdge - fract(ray.origin)) / ray.direction;
    vec3 originalStepSizes = abs(1.0 / ray.direction);
    vec3 rdSign = sign(ray.direction);
    
    float dist = 0.0;
    for (int i = 0; i < maxSteps; i++) {
        float stepSize = min(steps.x, min(steps.y, steps.z));
        ray.origin += ray.direction * stepSize;
        vec3 stepAxis = vec3(lessThanEqual(steps, vec3(stepSize)));
        ivec3 nextCell = ray.cell + ivec3(stepAxis * rdSign);
        dist += stepSize;
        
        if (steveDist > 0.0 && dist > steveDist && steveColor.a > 0.0) {
            ray.origin += ray.direction * steveDist + steveDirection * 0.01;
            ray.cell = ivec3(floor(ray.origin));
            return Hit(
                true, 
                steveDist, 
                steveDirection, 
                Material(
                    steveColor.rgb,
                    steveDirection,
                    0.0,
                    0.5,
                    vec3(0.04),
                    0.0,
                    false
                )
            );
        }
        
        Intersection intersection = checkIntersection(Ray(ray.origin, nextCell, ray.direction));
        if (intersection.hit) {
            vec3 normal = intersection.tbn[2];
            ray.origin += normal * 0.001;
            
            Hit hit = Hit(true, dist + intersection.dist, normal, getMaterial(intersection));
            return hit;
        }

        ray.cell = nextCell;
        steps += originalStepSizes * stepAxis - stepSize;
    }
    return noHit();
}

vec3 fresnel(vec3 F0, float cosTheta) {
    return F0 + (1.0 - F0) * pow(max(1.0 - cosTheta, 0.0), 5);
}

bool checkSun(vec3 hitPos, ivec3 hitCell, int maxSteps, vec3 normal, out float diffuse) {
    vec3 dir = mix(cosineWeighted(sunDir), sunDir, SUN_SIZE_FACTOR);
    diffuse = max(dot(dir, normal), 0.0);
    if (diffuse <= 0.0)
        return false;
    Ray sunRay = Ray(hitPos, hitCell, dir);
    return !raytrace(sunRay, true, maxSteps).hit;
}

vec3 getNextRayDirection(Material material, vec3 rayDir, vec3 geometryNormal) {
    if (material.metal) {
        vec3 reflected = reflect(rayDir, material.normal);
        return mix(reflected, cosineWeighted(geometryNormal), material.roughness * 0.3);
    } else {
        return cosineWeighted(geometryNormal);
    }
}

PathTraceOutput pathtrace(vec3 playerPos, vec3 normal) {
    vec3 blockPos = playerPos - fract(chunkOffset);

    Material material = defaultMaterial(normal);
    material.albedo = pow(texture(DiffuseSampler, texCoord).rgb, vec3(GAMMA_CORRECTION));

    vec3 rayDir = normalize(playerPos);
    float dist = length(playerPos);
    float offset = 0.0005 * dist * dist + 0.001;
    Ray initialRay = Ray(blockPos - rayDir * 1.0, ivec3(floor(blockPos - normal * offset)), rayDir);
    Intersection intersection = checkIntersection(initialRay);
    if (intersection.hit) {
        material = getMaterial(intersection);    
    } else {
        material.normal = normal;
    }
    
    rayDir = getNextRayDirection(material, rayDir, normal);
    vec3 radiance = vec3(0);
    vec3 throughput = vec3(1.0);
    
    throughput *= fresnel(material.F0, max(dot(-rayDir, normal), 0.0));
    
    Ray ray = Ray(blockPos + normal * 0.01, ivec3(floor(blockPos + normal * 0.01)), rayDir);
    
    if (!material.metal) {
        float diffuse = 0.0;
        if (checkSun(ray.origin, ray.cell, 55, material.normal, diffuse)) {
            radiance += diffuse / PI * throughput * SUN_INTENSITY * sunColor;
        }        
        throughput *= dot(rayDir, material.normal);
    }

    MaterialMaskData maskData = MaterialMaskData(
        material.metal,
        material.emission,
        material.normal
    );
    
    for (int i = 0; i < 3; i++) {
        Hit hit = raytrace(ray, true, i < 2 ? 55 : 55);

        if (!hit.hit) {
            radiance += SKY_COLOR * throughput;
            break;
        }

        radiance += hit.material.emission * hit.material.albedo * throughput * EMISSION_STRENGTH;
        
        vec3 nextRayDir = getNextRayDirection(hit.material, ray.direction, hit.geometryNormal);
        
        throughput *= fresnel(hit.material.F0, max(dot(-nextRayDir, hit.geometryNormal), 0.0));
        throughput *= hit.material.albedo;
        
        float diffuse = 0.0;
        if (!hit.material.metal && checkSun(ray.origin, ray.cell, i < 1 ? 55 : 25, hit.material.normal, diffuse)) {
            radiance += diffuse / PI * throughput * SUN_INTENSITY * sunColor;
        }
        
        if (!material.metal) {
            throughput *= material.ambientOcclusion;
        }
        float luma = dot(throughput, vec3(1.0)) / 3.0;
        if (randFloat() > luma) {
            break;
        }
        throughput /= luma;
        
        ray.direction = nextRayDir;
    }
    return PathTraceOutput(radiance, maskData);
}

float fresnel(float cosTheta, float F0) {
    return F0 + (1.0 - F0) * pow(1.0 - cosTheta, 5.0);
}

void main() {
    ivec2 fragCoord = ivec2(gl_FragCoord.xy);
    initRNG(uvec2(fragCoord), uvec2(InSize), frame * 1000u);
    
    float depth = texture(DepthSampler, texCoord).r;
    vec4 waterColor = texture(WaterSampler, texCoord);
    float solidDepth;
    vec3 albedo = pow(texture(DiffuseSampler, texCoord).rgb, vec3(GAMMA_CORRECTION));
    if (depth == 1.0) {
        fragColor = encodeHDRColor(pow(albedo, vec3(1.5)));  
        return;
    }
    
    vec3 screenPos = vec3(texCoord, depth);
    vec3 viewPos = screenToView(screenPos, projInv);
    vec3 playerPos = viewPos * modelViewMat;
    vec3 normal =  normalize(
        texture(NormalSampler, texCoord).rgb * 2.0 - 1.0
    );

    PathTraceOutput ptOutput = pathtrace(playerPos, normal);

    gl_FragDepth = storeMaterialMask(ptOutput.materialMask);
    
    fragColor = encodeHDRColor(ptOutput.radiance);
}