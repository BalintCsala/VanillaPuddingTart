#ifndef VOXELIZATION
#define VOXELIZATION

#include<constants.glsl>

ivec2 positionToCellStore(vec3 position, out bool inside) {
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

ivec2 cellToPixelStore(ivec2 cell, ivec2 screenSize) {
    return ivec2(round(vec2(cell) / GRID_SIZE * screenSize));
}

ivec2 positionToPixel(vec3 position, out bool inside) {
    ivec3 sides = ivec3(AREA_SIDE_LENGTH);

    ivec3 iPosition = ivec3(floor(position));
    iPosition += sides / 2;

    inside = true;
    if (clamp(iPosition, ivec3(0), sides - 1) != iPosition) {
        inside = false;
        return ivec2(-1);
    }

    int index = (iPosition.y * sides.z + iPosition.z) * sides.x + iPosition.x;
    
    return ivec2(
        index % STORAGE_SIZE,
        index / STORAGE_SIZE
    );
}

ivec3 pixelToPosition(ivec2 pixel) {
    ivec3 sides = ivec3(AREA_SIDE_LENGTH);

    int index = pixel.x + pixel.y * STORAGE_SIZE;
    return ivec3(
        index % sides.x,
        index / sides.x / sides.z,
        (index / sides.x) % sides.z
    ) - sides / 2;
}

#endif // VOXELIZATION