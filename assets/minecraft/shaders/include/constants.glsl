#ifndef CONSTANTS_GLSL
#define CONSTANTS_GLSL

// Application specific
const ivec2 GRID_SIZE = ivec2(1024, 705);
const int AREA_SIDE_LENGTH = int(pow(float(GRID_SIZE.x * GRID_SIZE.y / 2), 1.0 / 3.0));
const int STORAGE_SIZE = 839;
const uint MAX_COUNTER = 255u;

// Universal
const float EPSILON = 0.001;
const float PI = 3.141592654;

// Temporal

const float MAX_TEMPORAL_BLENDING = 0.05;

#endif // CONSTANTS_GLSL