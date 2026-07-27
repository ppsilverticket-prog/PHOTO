#version 460 core

// 색보정 + 파라메트릭 필터 셰이더.
// lib/core/color_adjustments.dart 의 CPU 구현과 수식이 반드시 일치해야 한다.

precision mediump float;

#include <flutter/runtime_effect.glsl>

uniform vec2 uSize;

// 사용자 보정값 (-1.0 ~ 1.0)
uniform float uBrightness;
uniform float uContrast;
uniform float uSaturation;
uniform float uTemperature;
uniform float uTint;
uniform float uHighlights;
uniform float uShadows;

// 필터 프리셋의 기본 보정값
uniform float uPBrightness;
uniform float uPContrast;
uniform float uPSaturation;
uniform float uPTemperature;
uniform float uPTint;

// 필터 프리셋의 채널별 lift / gamma / gain
uniform vec3 uLift;
uniform vec3 uGamma;
uniform vec3 uGain;

// 필터 강도 (0 = 필터 없음, 1 = 최대)
uniform float uStrength;

uniform sampler2D uTexture;

out vec4 fragColor;

const vec3 kLuma = vec3(0.299, 0.587, 0.114);

vec3 adjust(vec3 c, float brightness, float contrast, float saturation,
            float temperature, float tint, float highlights, float shadows) {
  c.r *= 1.0 + 0.25 * temperature;
  c.b *= 1.0 - 0.25 * temperature;
  c.g *= 1.0 + 0.25 * tint;

  c += brightness * 0.35;
  c = (c - 0.5) * (1.0 + contrast * 0.9) + 0.5;

  float luma = dot(clamp(c, 0.0, 1.0), kLuma);
  c = mix(vec3(luma), c, 1.0 + saturation);

  float l2 = clamp(dot(clamp(c, 0.0, 1.0), kLuma), 0.0, 1.0);
  c += highlights * 0.35 * smoothstep(0.5, 1.0, l2);
  c += shadows * 0.35 * (1.0 - smoothstep(0.0, 0.5, l2));
  return clamp(c, 0.0, 1.0);
}

void main() {
  vec2 uv = FlutterFragCoord().xy / uSize;
  vec4 src = texture(uTexture, uv);

  vec3 base = adjust(src.rgb, uBrightness, uContrast, uSaturation,
                     uTemperature, uTint, uHighlights, uShadows);

  vec3 filtered = adjust(base, uPBrightness, uPContrast, uPSaturation,
                         uPTemperature, uPTint, 0.0, 0.0);
  filtered = pow(filtered, 1.0 / max(uGamma, vec3(0.01)));
  filtered = clamp(filtered * uGain + uLift, 0.0, 1.0);

  vec3 result = mix(base, filtered, uStrength);
  fragColor = vec4(result, src.a);
}
