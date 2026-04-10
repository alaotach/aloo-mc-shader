#version 330 compatibility

#include "/lib/shadowDistort.glsl"

uniform sampler2D colortex0;
uniform sampler2D colortex1;
uniform sampler2D colortex2;
uniform sampler2D depthtex0;
uniform sampler2D shadowtex0;
uniform sampler2D shadowtex1;
uniform sampler2D shadowcolor0;
uniform vec3 shadowLightPosition;
uniform mat4 gbufferModelViewInverse;
uniform mat4 gbufferProjectionInverse;
uniform mat4 shadowModelView;
uniform mat4 shadowProjection;
uniform int worldTime;

const float SHADOW_PCF_RADIUS = 1.0;


const vec3 blocklightColor = vec3(1.0, 0.5, 0.08);

const vec3 sunlightColor = vec3(1.0, 1.0, 0.9);
const vec3 skylightColorDay = vec3(0.05, 0.15, 0.3);
const vec3 ambientColorDay = vec3(0.1);
const vec3 moonlightColor = vec3(0.02, 0.04, 0.08);
const vec3 skylightColorNight = vec3(0.01, 0.02, 0.04);
const vec3 ambientColorNight = vec3(0.02);


in vec2 texcoord;

/* RENDERTARGETS: 0 */
layout(location = 0) out vec4 color;

 vec3 projectAndDivide(mat4 projectionMatrix, vec3 pos){
   vec4 homPos = projectionMatrix * vec4(pos, 1.0);
   return homPos.xyz / homPos.w;
 }

  vec3 getShadow(vec3 shadowScreenPos){
   float transparentShadow = step(shadowScreenPos.z, texture(shadowtex0, shadowScreenPos.xy).r);
   if (transparentShadow == 1.0){
     return vec3(1.0);
   }

   float opaqueShadow = step(shadowScreenPos.z, texture(shadowtex1, shadowScreenPos.xy).r);
   if(opaqueShadow == 0.0){
     return vec3(0.0);
   }
   vec4 shadowColor = texture(shadowcolor0, shadowScreenPos.xy);
   return shadowColor.rgb * (1.0 - shadowColor.a);
 }

 vec3 getShadowPcf(vec3 shadowScreenPos){
	 vec2 texel = 1.0 / vec2(textureSize(shadowtex0, 0));
	 vec3 shadowAccum = vec3(0.0);
	 float weightSum = 0.0;


	 for (int y = -1; y <= 1; y++) {
		 for (int x = -1; x <= 1; x++) {
			 vec2 offset = vec2(float(x), float(y)) * texel * SHADOW_PCF_RADIUS;
			 float wx = (x == 0) ? 2.0 : 1.0;
			 float wy = (y == 0) ? 2.0 : 1.0;
			 float w = wx * wy;
			 shadowAccum += getShadow(vec3(shadowScreenPos.xy + offset, shadowScreenPos.z)) * w;
			 weightSum += w;
		 }
	 }
	 return shadowAccum / max(weightSum, 1e-4);
 }

void main() {
    vec2 lightmap = texture(colortex1, texcoord).xy;
    vec3 encodedNormal = texture(colortex2, texcoord).rgb;
    vec3 normal = normalize((encodedNormal - 0.5) * 2.0);
    vec3 lightVector = normalize(shadowLightPosition);
    vec3 worldLightVector = mat3(gbufferModelViewInverse) * lightVector;
    color = texture(colortex0, texcoord);
    color.rgb = pow(color.rgb, vec3(2.2));
    color.a = 1.0;
    float depth = texture(depthtex0, texcoord).r;
      if (depth == 1.0) {
        return;
    }

    vec3 ndcPos = vec3(texcoord.xy, depth) * 2.0 - 1.0;
    vec3 viewPos = projectAndDivide(gbufferProjectionInverse, ndcPos);
    vec3 feetPlayerPos = (gbufferModelViewInverse * vec4(viewPos, 1.0)).xyz;
    vec3 shadowViewPos = (shadowModelView * vec4(feetPlayerPos, 1.0)).xyz;
    vec4 shadowClipPos = shadowProjection * vec4(shadowViewPos, 1.0);
    shadowClipPos.z -= 0.001;
    shadowClipPos.xyz = distortShadowClipPos(shadowClipPos.xyz);
    vec3 shadowNdcPos = shadowClipPos.xyz / shadowClipPos.w;
    vec3 shadowScreenPos = shadowNdcPos * 0.5 + 0.5;

    vec3 shadow = getShadowPcf(shadowScreenPos);

    float timeMask = (worldTime < 13000 || worldTime > 23000) ? 1.0 : 0.0;    
    vec3 currSunlightColor = mix(moonlightColor, sunlightColor, timeMask);
    vec3 currSkylightColor = mix(skylightColorNight, skylightColorDay, timeMask);
    vec3 currAmbientColor = mix(ambientColorNight, ambientColorDay, timeMask);

    vec3 blocklight = lightmap.x * blocklightColor;
    vec3 skylight = lightmap.y * currSkylightColor;
    vec3 ambient = currAmbientColor;
    vec3 sunlight = currSunlightColor * clamp(dot(worldLightVector, normal), 0.0, 1.0) * shadow;
    color.rgb *= blocklight + skylight + ambient + sunlight;
    color.a = 1.0;
}