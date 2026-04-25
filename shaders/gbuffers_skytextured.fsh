#version 330 compatibility

uniform sampler2D gtexture;
uniform int worldTime;

uniform float alphaTestRef = 0.1;

in vec2 texcoord;
in vec4 glcolor;

/* RENDERTARGETS: 0 */
layout(location = 0) out vec4 color;

void main() {
	color = texture(gtexture, texcoord) * glcolor;
	float worldTimeF = float(worldTime);
	float duskFade = 1.0 - smoothstep(12000.0, 13500.0, worldTimeF);
	float dawnFade = smoothstep(22500.0, 23500.0, worldTimeF);
	float dayVisibility = max(duskFade, dawnFade);
	float nightAmount = 1.0 - dayVisibility;
	float gray = dot(color.rgb, vec3(0.2126, 0.7152, 0.0722));
	color.rgb = mix(vec3(gray), color.rgb, 1.0 - nightAmount * 0.35);
	color.rgb *= mix(0.30, 1.0, dayVisibility);
	if (color.a < alphaTestRef) {
		discard;
	}
}