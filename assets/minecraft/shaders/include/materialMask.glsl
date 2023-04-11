#line 1 1010

struct MaterialMaskData {
    bool metal;
    float emission;
    vec3 normal;
};

const float MAX_VALUE = 16777215.0;

vec3 getMaskNormal(int data) {
    vec3 normal = vec3(
        (data >> 9) & 15, 
        (data >> 13) & 15, 
        0.0
    ) / 15.0 * 2.0 - 1.0;

    normal.z = sqrt(1.0 - min(1.0, dot(normal.xy, normal.xy)));
    normal.z *= float((data >> 17) & 1) * 2.0 - 1.0;    
    return normalize(normal);
}

vec3 getMaskNormal(float raw) {
    int data = int(round(raw * MAX_VALUE));
    return getMaskNormal(data);
}

MaterialMaskData getMaterialMask(float raw) {
    int data = int(round(raw * MAX_VALUE));

    return MaterialMaskData(
        (data & 1) == 1,
        ((data >> 1) & 255) / 255.0,
        getMaskNormal(data)
    );
}

float storeMaterialMask(MaterialMaskData data) {
    vec3 unitNormal = data.normal * 0.5 + 0.5;
    return (
        int(data.metal) | 
        (int(data.emission * 255.0) << 1) |
        (int(round(unitNormal.x * 15.0)) << 9) |
        (int(round(unitNormal.y * 15.0)) << 13) |
        (data.normal.z > 0.0 ? 1 : 0) << 17
    ) / MAX_VALUE;
}