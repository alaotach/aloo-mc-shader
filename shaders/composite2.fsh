#version 330 compatibility

uniform sampler2D colortex0;
uniform sampler2D colortex3;
uniform sampler2D depthtex0;
uniform vec3 shadowLightPosition;

const float BLOOM_THRESHOLD = 1.24;
uniform mat4 gbufferProjection;

const int GODRAY_SAMPLES = 80;
const float GODRAY_DENSITY = 0.95;
const float GODRAY_WEIGHT = 0.012;
const float GODRAY_DECAY = 0.97;
const float GODRAY_EXPOSURE = 1.25;

in vec2 texcoord;

/* RENDERTARGETS: 0 */
layout(location = 0) out vec4 color;

float luminance(vec3 c) {
  return dot(c, vec3(0.2126, 0.7152, 0.0722));
}

vec3 upsampleGodray(vec2 uv) {
  vec2 texel = 1.0 / vec2(textureSize(colortex3, 0));
  float centerDepth = texture(depthtex0, uv).r;

  vec3 accum = vec3(0.0);
  float weightSum = 0.0;

  for (int y = -1; y <= 1; y++) {
    for (int x = -1; x <= 1; x++) {
      vec2 off = vec2(float(x), float(y)) * texel;
      vec2 suv = uv + off;

      float d = texture(depthtex0, suv).r;
      float depthWeight = exp(-abs(d - centerDepth) * 400.0);
      float wx = (x == 0) ? 2.0 : 1.0;
      float wy = (y == 0) ? 2.0 : 1.0;
      float w = wx * wy * depthWeight;

      accum += texture(colortex3, suv).rgb * w;
      weightSum += w;
    }
  }

  return accum / max(weightSum, 1e-4);
}

void main() {
    color = texture(colortex0, texcoord);
    vec4 sunClip = gbufferProjection * vec4(shadowLightPosition * 1000.0, 1.0);
    vec3 sunNdc = sunClip.xyz / sunClip.w;
    vec2 sunScreenPos = sunNdc.xy * 0.5 + 0.5;
    if (sunClip.w < 0.0) return;

    vec2 deltaUV = (texcoord - sunScreenPos) * (1.0 / float(GODRAY_SAMPLES)) * GODRAY_DENSITY;
    vec2 uv = texcoord;
    float intensityDecay = 1.0;
    vec3 godray = vec3(0.0);

    for (int i = 0; i < GODRAY_SAMPLES; i++) {
        uv -= deltaUV;
        if (uv.x < 0.0 || uv.x > 1.0 || uv.y < 0.0 || uv.y > 1.0) break;

        float depth = texture(depthtex0, uv).r;
        float isSky = step(0.9999, depth);
        vec3 sample = texture(colortex0, uv).rgb * isSky;

        godray += sample * intensityDecay * GODRAY_WEIGHT;
        intensityDecay *= GODRAY_DECAY;
    }

    vec3 volumetricGodray = upsampleGodray(texcoord);
    color.rgb += godray * GODRAY_EXPOSURE + volumetricGodray;
    color.a = 1.0;
}