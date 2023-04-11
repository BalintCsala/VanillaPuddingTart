uint state;

uint rand() {
	uint newState = state * uint(747796405) + uint(2891336453);
	uint word = ((newState >> ((newState >> uint(28)) + uint(4))) ^ newState) * uint(277803737);
    state = (word >> uint(22)) ^ word;
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