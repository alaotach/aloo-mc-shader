#version 330 compatibility

uniform sampler2D lightmap;
uniform sampler2D gtexture;

uniform float alphaTestRef = 0.1;

in vec2 lmcoord;
in vec2 texcoord;
in vec4 glcolor;

/* RENDERTARGETS: 0,4 */
layout(location = 0) out vec4 color;
layout(location = 1) out vec4 translucentColor;

void main() {
	color = texture(gtexture, texcoord) * glcolor;
	vec3 lm = texture(lightmap, lmcoord).rgb;
	color.rgb *= lm;
	if (color.a < alphaTestRef) {
		discard;
	}
	translucentColor = vec4(color.rgb, 1.0);
}
