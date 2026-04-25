#version 330 compatibility

out vec2 texcoord;
out vec4 glcolor;

void main() {
	gl_Position = ftransform();
	texcoord = (gl_TextureMatrix[0] * gl_MultiTexCoord0).xy;
	float angle = 0.8;
	mat2 rot = mat2(
		cos(angle), -sin(angle),
		sin(angle),  cos(angle)
	);
	texcoord = rot * (texcoord - 0.5) + 0.5;
	glcolor = gl_Color;
}