#version 330 compatibility

#include "/lib/shadowDistort.glsl"

uniform sampler2D colortex0;
uniform sampler2D depthtex0;
uniform sampler2D shadowtex0;
uniform sampler2D shadowtex1;
uniform sampler2D shadowcolor0;

uniform mat4 gbufferProjectionInverse;
uniform mat4 gbufferModelViewInverse;
uniform vec3 fogColor;
uniform float far;
uniform vec3 shadowLightPosition;
uniform mat4 shadowModelView;
uniform mat4 shadowProjection;
uniform int worldTime;
uniform int frameCounter;

const float FOG_DENSITY = 5.0;
const int GODRAY_SAMPLES = 30;
const float GODRAY_STRENGTH = 0.058;
const float SHADOW_PCF_RADIUS = 1.25;
const float VOLUMETRIC_SIZE = 2.0;

in vec2 texcoord;

vec3 projectAndDivide(mat4 projectionMatrix, vec3 pos);

float interleavedGradientNoise(vec2 p){
  return fract(52.9829189 * fract(dot(p, vec2(0.06711056, 0.00583715))));
}

vec2 r2Sequence(float n){
  const vec2 a = vec2(0.75487766, 0.56984029);
  return fract(a * n);
}

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

float getShadowPcfVisibility(vec3 shadowScreenPos){
  vec2 texel = 1.0 / vec2(textureSize(shadowtex0, 0));
  float visibility = 0.0;
  float weightSum = 0.0;

  for (int y = -1; y <= 1; y++) {
    for (int x = -1; x <= 1; x++) {
      vec2 offset = vec2(float(x), float(y)) * texel * SHADOW_PCF_RADIUS;
      float wx = (x == 0) ? 2.0 : 1.0;
      float wy = (y == 0) ? 2.0 : 1.0;
      float w = wx * wy;
      vec3 shadow = getShadow(vec3(shadowScreenPos.xy + offset, shadowScreenPos.z));
      visibility += dot(shadow, vec3(0.3333333)) * w;
      weightSum += w;
    }
  }

  return visibility / max(weightSum, 1e-4);
}

/* RENDERTARGETS: 0,3 */
layout(location = 0) out vec4 color;
layout(location = 1) out vec4 godrayOut;

void main() {
    godrayOut = vec4(0.0);
    vec4 baseColor = texture(colortex0, texcoord);
    color = baseColor;

    vec2 screenSize = vec2(textureSize(colortex0, 0));
    vec2 lowResCoord = floor((texcoord * screenSize) / VOLUMETRIC_SIZE);
    vec2 volumetricUv = (lowResCoord * VOLUMETRIC_SIZE + 0.5 * VOLUMETRIC_SIZE) / screenSize;

    float sceneDepth = texture(depthtex0, volumetricUv).r;

    if (sceneDepth < 0.01){
      color.a = 1.0;
      return;
    }
    vec3 sunViewDir = normalize(shadowLightPosition);
    vec3 sunWorldDir = normalize(mat3(gbufferModelViewInverse) * sunViewDir);
    float sunElevation = sunWorldDir.y;

    // time maask for variable color and intensity of light
    float timeMask = (worldTime < 13000 || worldTime > 23000) ? 1.0 : 0.0;
    vec3 ndcPos = vec3(volumetricUv.xy, sceneDepth) * 2.0 - 1.0;
    vec3 viewPos = projectAndDivide(gbufferProjectionInverse, ndcPos);
    float dist = length(viewPos) / far;
    float fogFactor = exp(-FOG_DENSITY * (1.0 - dist));

    if (sceneDepth >= 1.0) {
      fogFactor = 0.0;
    }

    vec3 rayDir = normalize(viewPos);

    float forwardScattering = clamp(dot(rayDir, sunViewDir), 0.0, 1.0);
    float backwardScattering = clamp(dot(rayDir, -sunViewDir), 0.0, 1.0);
    float cinematicScattering = max(forwardScattering, backwardScattering * 0.85);
    float phaseFunction = 1.08 + pow(cinematicScattering, 2.0) * 1.95;
    vec2 jitterSeed = r2Sequence(float(frameCounter)) * 256.0;
    float noise = interleavedGradientNoise(floor(gl_FragCoord.xy / VOLUMETRIC_SIZE) + jitterSeed);
    float baseSteps = float(GODRAY_SAMPLES);
    float samplesFloat = round(baseSteps + ((baseSteps / 8.0) + 2.0) * noise);
    int samples = int(samplesFloat);

    // max lim for raymarching dist
    float maxDistance = min(length(viewPos), 120.0);
    float stepSize = maxDistance / samplesFloat;
    float t = stepSize * 0.5;
    float intensity = 0.0;
    t += stepSize * noise;

    for(int i = 0; i < samples; i++) {
        if (t > maxDistance) {
          break;
        }

        vec3 sampleViewPos = rayDir * t;
        vec3 sampleWorldPos = (gbufferModelViewInverse * vec4(sampleViewPos, 1.0)).xyz;
        vec3 sampleShadowViewPos = (shadowModelView * vec4(sampleWorldPos, 1.0)).xyz;
        vec4 sampleShadowClipPos = shadowProjection * vec4(sampleShadowViewPos, 1.0);
        sampleShadowClipPos.z -= 0.001;
        vec3 undistortedNDC = sampleShadowClipPos.xyz / sampleShadowClipPos.w;
        bool isOutside = abs(undistortedNDC.x) >= 0.95 || abs(undistortedNDC.y) >= 0.95 || abs(undistortedNDC.z) >= 0.95;
        sampleShadowClipPos.xyz = distortShadowClipPos(sampleShadowClipPos.xyz);
        vec3 sampleShadowNdc = sampleShadowClipPos.xyz / sampleShadowClipPos.w;
        vec3 sampleShadow = sampleShadowNdc * 0.5 + 0.5;
        vec2 jitter = vec2(
            fract(sin(float(i) * 12.9898 + noise) * 43758.5453),
            fract(sin(float(i) * 78.233 + noise) * 43758.5453)
        ) - 0.5;
        float spreadStrength = 0.002 * t;
        sampleShadow.xy += jitter * spreadStrength;

        float visibility = 1.0;

        if (!isOutside) {
          visibility = getShadowPcfVisibility(sampleShadow);
        }
        float distanceAttenuation = 2.0;
        float lightTravelDist = clamp(sampleShadow.z, 0.0, 1.0); 
        float lightFade = pow(1.0 - lightTravelDist, distanceAttenuation);
        float distanceFade = smoothstep(120.0, 50.0, t);
        float heightFactor = exp(-max(sampleWorldPos.y, 0.0) * 0.005) * distanceFade;
        intensity += visibility * heightFactor * lightFade * stepSize * 0.12;
        if (intensity > 5.0) {
            break;
        }

        t += stepSize;
    }
    intensity = 1.0 - exp(-intensity);
    intensity = pow(clamp(intensity, 0.0, 1.0), 0.9);

    float warmTint = smoothstep(0.0, 0.15, sunElevation);
    vec3 sunriseTint = mix(vec3(1.25, 0.72, 0.42), vec3(1.0, 0.95, 0.8), warmTint);
    vec3 moonTint = vec3(0.03, 0.07, 0.15);
    vec3 baseRayColor = mix(moonTint, sunriseTint, timeMask);
    float offAngleLift = mix(1.18, 1.0, forwardScattering);
    vec3 currentGodray = baseRayColor * intensity * GODRAY_STRENGTH * phaseFunction * offAngleLift;
    vec3 temporalGodray = currentGodray;
    godrayOut = vec4(temporalGodray, 1.0);

    color.rgb = baseColor.rgb;
    color.rgb = mix(color.rgb, pow(fogColor, vec3(2.2)), clamp(fogFactor, 0.0, 1.0));
    color.a = 1.0;
}