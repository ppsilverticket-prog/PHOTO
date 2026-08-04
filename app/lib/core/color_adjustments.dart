import 'dart:math' as math;

import 'package:image/image.dart' as img;

import 'filter_presets.dart';

/// 사용자 색보정 값. 모든 값은 -1.0 ~ 1.0, 0이 중립.
class ColorAdjustments {
  const ColorAdjustments({
    this.brightness = 0,
    this.contrast = 0,
    this.saturation = 0,
    this.temperature = 0,
    this.tint = 0,
    this.highlights = 0,
    this.shadows = 0,
  });

  static const ColorAdjustments neutral = ColorAdjustments();

  final double brightness;
  final double contrast;
  final double saturation;
  final double temperature;
  final double tint;
  final double highlights;
  final double shadows;

  bool get isNeutral =>
      brightness == 0 &&
      contrast == 0 &&
      saturation == 0 &&
      temperature == 0 &&
      tint == 0 &&
      highlights == 0 &&
      shadows == 0;

  ColorAdjustments copyWith({
    double? brightness,
    double? contrast,
    double? saturation,
    double? temperature,
    double? tint,
    double? highlights,
    double? shadows,
  }) {
    return ColorAdjustments(
      brightness: brightness ?? this.brightness,
      contrast: contrast ?? this.contrast,
      saturation: saturation ?? this.saturation,
      temperature: temperature ?? this.temperature,
      tint: tint ?? this.tint,
      highlights: highlights ?? this.highlights,
      shadows: shadows ?? this.shadows,
    );
  }

  @override
  bool operator ==(Object other) =>
      other is ColorAdjustments &&
      other.brightness == brightness &&
      other.contrast == contrast &&
      other.saturation == saturation &&
      other.temperature == temperature &&
      other.tint == tint &&
      other.highlights == highlights &&
      other.shadows == shadows;

  @override
  int get hashCode => Object.hash(brightness, contrast, saturation,
      temperature, tint, highlights, shadows);

  Map<String, double> toJson() => {
        if (brightness != 0) 'brightness': brightness,
        if (contrast != 0) 'contrast': contrast,
        if (saturation != 0) 'saturation': saturation,
        if (temperature != 0) 'temperature': temperature,
        if (tint != 0) 'tint': tint,
        if (highlights != 0) 'highlights': highlights,
        if (shadows != 0) 'shadows': shadows,
      };

  factory ColorAdjustments.fromJson(Map<String, dynamic> json) {
    double f(String key) => (json[key] as num?)?.toDouble() ?? 0;
    return ColorAdjustments(
      brightness: f('brightness'),
      contrast: f('contrast'),
      saturation: f('saturation'),
      temperature: f('temperature'),
      tint: f('tint'),
      highlights: f('highlights'),
      shadows: f('shadows'),
    );
  }
}

// ---------------------------------------------------------------------------
// CPU 구현 — shaders/adjustments.frag 와 수식이 반드시 일치해야 한다.
// 프리뷰는 GPU 셰이더, 저장은 이 CPU 경로를 쓰므로 어긋나면 결과물이 달라진다.
// ---------------------------------------------------------------------------

double _smoothstep(double edge0, double edge1, double x) {
  final t = ((x - edge0) / (edge1 - edge0)).clamp(0.0, 1.0);
  return t * t * (3 - 2 * t);
}

double _luma(double r, double g, double b) =>
    0.299 * r.clamp(0.0, 1.0) + 0.587 * g.clamp(0.0, 1.0) + 0.114 * b.clamp(0.0, 1.0);

/// (r, g, b)에 보정을 적용한다. 값 범위는 0.0~1.0.
List<double> adjustRgb(
  double r,
  double g,
  double b, {
  required double brightness,
  required double contrast,
  required double saturation,
  required double temperature,
  required double tint,
  required double highlights,
  required double shadows,
}) {
  r *= 1 + 0.25 * temperature;
  b *= 1 - 0.25 * temperature;
  g *= 1 + 0.25 * tint;

  r += brightness * 0.35;
  g += brightness * 0.35;
  b += brightness * 0.35;

  final contrastScale = 1 + contrast * 0.9;
  r = (r - 0.5) * contrastScale + 0.5;
  g = (g - 0.5) * contrastScale + 0.5;
  b = (b - 0.5) * contrastScale + 0.5;

  final luma = _luma(r, g, b);
  final satScale = 1 + saturation;
  r = luma + (r - luma) * satScale;
  g = luma + (g - luma) * satScale;
  b = luma + (b - luma) * satScale;

  final l2 = _luma(r, g, b).clamp(0.0, 1.0);
  final highlightShift = highlights * 0.35 * _smoothstep(0.5, 1.0, l2);
  final shadowShift = shadows * 0.35 * (1 - _smoothstep(0.0, 0.5, l2));
  r += highlightShift + shadowShift;
  g += highlightShift + shadowShift;
  b += highlightShift + shadowShift;

  return [r.clamp(0.0, 1.0), g.clamp(0.0, 1.0), b.clamp(0.0, 1.0)];
}

/// 이미지 전체에 사용자 보정 + 필터 프리셋을 적용한다 (in place).
img.Image applyAdjustmentsCpu(
  img.Image image, {
  ColorAdjustments adjustments = ColorAdjustments.neutral,
  FilterPreset? preset,
  double strength = 1.0,
}) {
  final hasFilter = preset != null && strength > 0;
  if (adjustments.isNeutral && !hasFilter) return image;

  for (final pixel in image) {
    var r = pixel.rNormalized.toDouble();
    var g = pixel.gNormalized.toDouble();
    var b = pixel.bNormalized.toDouble();

    final base = adjustRgb(
      r,
      g,
      b,
      brightness: adjustments.brightness,
      contrast: adjustments.contrast,
      saturation: adjustments.saturation,
      temperature: adjustments.temperature,
      tint: adjustments.tint,
      highlights: adjustments.highlights,
      shadows: adjustments.shadows,
    );
    r = base[0];
    g = base[1];
    b = base[2];

    if (hasFilter) {
      final filtered = adjustRgb(
        r,
        g,
        b,
        brightness: preset.brightness,
        contrast: preset.contrast,
        saturation: preset.saturation,
        temperature: preset.temperature,
        tint: preset.tint,
        highlights: 0,
        shadows: 0,
      );
      var fr = math.pow(filtered[0], 1 / math.max(preset.gamma[0], 0.01)).toDouble();
      var fg = math.pow(filtered[1], 1 / math.max(preset.gamma[1], 0.01)).toDouble();
      var fb = math.pow(filtered[2], 1 / math.max(preset.gamma[2], 0.01)).toDouble();
      fr = (fr * preset.gain[0] + preset.lift[0]).clamp(0.0, 1.0);
      fg = (fg * preset.gain[1] + preset.lift[1]).clamp(0.0, 1.0);
      fb = (fb * preset.gain[2] + preset.lift[2]).clamp(0.0, 1.0);

      r = r + (fr - r) * strength;
      g = g + (fg - g) * strength;
      b = b + (fb - b) * strength;
    }

    pixel.rNormalized = r;
    pixel.gNormalized = g;
    pixel.bNormalized = b;
  }
  return image;
}
