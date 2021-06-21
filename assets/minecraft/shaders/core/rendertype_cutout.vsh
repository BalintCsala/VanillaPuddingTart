#version 150

#moj_import <utils.glsl>

in vec3 Position;
in vec4 Color;
in vec2 UV0;
in vec2 UV1;
in ivec2 UV2;
in vec3 Normal;

uniform sampler2D Sampler0;
uniform sampler2D Sampler2;
uniform mat4 ModelViewMat;
uniform mat4 ProjMat;
uniform vec3 ChunkOffset;

out vec2 texCoord0;
out vec2 pixel;
out vec3 chunkOffset;
out vec4 glpos;

// Location of the vertices based on their vertex id-s.
const vec3 VertexPositions[] = vec3[](
	/* +X */ vec3(1, 1, 1), vec3(1, 0, 1), vec3(1, 0, 0), vec3(1, 1, 0),
	/* -X */ vec3(0, 1, 0), vec3(0, 0, 0), vec3(0, 0, 1), vec3(0, 1, 1),
	/* +Y */ vec3(0, 1, 0), vec3(0, 1, 1), vec3(1, 1, 1), vec3(1, 1, 0),
	/* -Y */ vec3(0, 0, 1), vec3(0, 0, 0), vec3(1, 0, 0), vec3(1, 0, 1),
	/* +Z */ vec3(0, 1, 1), vec3(0, 0, 1), vec3(1, 0, 1), vec3(1, 1, 1),
	/* -Z */ vec3(1, 1, 0), vec3(1, 0, 0), vec3(0, 0, 0), vec3(0, 1, 0)
);

const vec4 ScreenPositions[] = vec4[](
	vec4(-1, -1, 0, 1),
	vec4(1, -1, 0, 1),
	vec4(1, 1, 0, 1),
	vec4(-1, 1, 0, 1)
);

void main() {

	// The index of the vertex in the face we're currently drawing.
	int faceVertexID = imod(gl_VertexID, 4);

	// Since UVs can be rotated, we need to rely on the vertex ids to get the position of the block the vertex belongs
	// to.
	// We'll also define an unrotated, absolute texture coordinate for later use.
	vec3 vertexPosition;
	vec2 realTexCoord;
	if (dot(Normal, vec3(1, 0, 0)) > 1 - EPSILON) {
		vertexPosition = VertexPositions[0 * 4 + faceVertexID];
		realTexCoord = vec2(-1, 1) * vertexPosition.zy + vec2(1, 0);
	} else if (dot(Normal, vec3(-1, 0, 0)) > 1 - EPSILON) {
		vertexPosition = VertexPositions[1 * 4 + faceVertexID];
		realTexCoord = vertexPosition.zy;
	} else if (dot(Normal, vec3(0, 1, 0)) > 1 - EPSILON) {
		vertexPosition = VertexPositions[2 * 4 + faceVertexID];
		realTexCoord = vec2(-1, 1) * vertexPosition.xz + vec2(1, 0);
	} else if (dot(Normal, vec3(0, -1, 0)) > 1 - EPSILON) {
		vertexPosition = VertexPositions[3 * 4 + faceVertexID];
		realTexCoord = vertexPosition.xz;
	} else if (dot(Normal, vec3(0, 0, 1)) > 1 - EPSILON) {
		vertexPosition = VertexPositions[4 * 4 + faceVertexID];
		realTexCoord = vertexPosition.xy;
	} else {
		vertexPosition = VertexPositions[5 * 4 + faceVertexID];
		realTexCoord = vec2(-1, 1) * vertexPosition.xy + vec2(1, 0);
	}
	// Position of the block relative to the player.
	vec3 relativePos = floor(round(Position + (vertexPosition * 2.0 - 1.0) * 0.49) + ChunkOffset);

	vec3 worldPos = relativePos - vertexPosition;
	// We calculate which pixel the block should be stored in
	pixel = blockToPixel(worldPos);

	// We'll deal with the first blockface of every chunk differently
	if (gl_VertexID < 4) {
		// We can make it occupy the whole screen and use it to store chunk offset
		gl_Position = ScreenPositions[gl_VertexID];
		glpos = gl_Position;
	} else {
		// Cull the blocks that are at least (LAYER_SIZE / 2 - 1) blocks away in any direction.

		if (any(greaterThan(abs(worldPos), vec3(LAYER_SIZE / 2 - 1)))) {
			gl_Position = vec4(999, 999, 0, 1);
			return;
		}

		// Place each face as a single pixel. If any of the faces are visible, the block will be shown.
		gl_Position = vec4(pixelToTexCoord(pixel + realTexCoord) * 2 - 1, 0, 1);
	}

	texCoord0 = UV0;
	chunkOffset = ChunkOffset;
}
