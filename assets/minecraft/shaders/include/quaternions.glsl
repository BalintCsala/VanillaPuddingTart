#ifndef QUATERNIONS_GLSL
#define QUATERNIONS_GLSL
#line 3 6723

vec4 quaternionMultiply(vec4 a, vec4 b) {
    return vec4(
        a.x * b.w + a.y * b.z - a.z * b.y + a.w * b.x,
        -a.x * b.z + a.y * b.w + a.z * b.x + a.w * b.y,
        a.x * b.y - a.y * b.x + a.z * b.w + a.w * b.z,
        -a.x * b.x - a.y * b.y - a.z * b.z + a.w * b.w
    );
}

vec3 quaternionRotate(vec3 pos, vec3 axis, float angle) {
    vec4 q = vec4(sin(angle / 2.0) * axis, cos(angle / 2.0));
    vec4 qInv = vec4(-q.xyz, q.w);
    return quaternionMultiply(quaternionMultiply(q, vec4(pos, 0)), qInv).xyz;
}

vec3 quaternionRotate(vec3 pos, vec4 q) {
    vec4 qInv = vec4(-q.xyz, q.w);
    return quaternionMultiply(quaternionMultiply(q, vec4(pos, 0)), qInv).xyz;
}

vec4 getRotationToZAxis(vec3 vec) {
	if (vec.z < -0.99999) return vec4(1.0, 0.0, 0.0, 0.0);
	return normalize(vec4(vec.y, -vec.x, 0.0, 1.0 + vec.z));
}

#endif // QUATERNIONS_GLSL