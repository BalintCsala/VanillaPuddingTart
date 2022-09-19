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