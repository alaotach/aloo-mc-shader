#version 330 compatibility

uniform sampler2D lightmap;
uniform sampler2D gtexture;
uniform vec4 entityColor;

uniform float alphaTestRef = 0.1;

in vec2 lmcoord;
in vec2 texcoord;
in vec4 glcolor;
in vec3 normal;

/* RENDERTARGETS: 0,1,2 */
layout(location = 0) out vec4 color;
layout(location = 1) out vec4 lightLevelData;
layout(location = 2) out vec4 encodedNormal;

void main() {
	vec4 albedo = texture(gtexture, texcoord);
	if (albedo.a < alphaTestRef) {
		discard;
	}

	color = vec4(albedo.rgb * glcolor.rgb, 1.0);
	color.rgb = mix(color.rgb, entityColor.rgb, entityColor.a);
	
	// We pass lightmap coordinates to composite shader instead of applying them here
	lightLevelData = vec4(lmcoord, 0.0, 1.0);
	
	// Pass default up normal since entities don't always have valid normals passed depending on vertex shader
	encodedNormal = vec4(normal * 0.5 + 0.5, 1.0);
}