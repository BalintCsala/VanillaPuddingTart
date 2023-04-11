const float MAX_VARIANCE = 256.0;

float storeVariance(float value) {
    return log2(value + 1.0) / log2(MAX_VARIANCE);
}

float loadVariance(float value) {
    return exp2(value * log2(MAX_VARIANCE)) - 1.0;
}