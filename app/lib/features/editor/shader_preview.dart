import 'dart:ui' as ui;

import 'package:flutter/material.dart';

import '../../core/color_adjustments.dart';
import '../../core/filter_presets.dart';

/// adjustments.frag 프로그램 로더. 실패하면 null을 반환하고
/// 호출 측은 CPU 프리뷰로 폴백한다.
class AdjustmentShaderProgram {
  AdjustmentShaderProgram._();

  static Future<ui.FragmentProgram?>? _future;

  static Future<ui.FragmentProgram?> load() {
    return _future ??= ui.FragmentProgram.fromAsset(
      'shaders/adjustments.frag',
    ).then<ui.FragmentProgram?>((p) => p).catchError((Object _) => null);
  }
}

/// 기하 연산이 적용된 [image] 위에 색보정/필터를 GPU 셰이더로 실시간 렌더링.
class ShaderPreview extends StatelessWidget {
  const ShaderPreview({
    super.key,
    required this.program,
    required this.image,
    required this.adjustments,
    this.preset,
    this.strength = 1.0,
  });

  final ui.FragmentProgram program;
  final ui.Image image;
  final ColorAdjustments adjustments;
  final FilterPreset? preset;
  final double strength;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: AspectRatio(
        aspectRatio: image.width / image.height,
        child: CustomPaint(
          painter: _ShaderPainter(
            shader: program.fragmentShader(),
            image: image,
            adjustments: adjustments,
            preset: preset,
            strength: preset == null ? 0.0 : strength,
          ),
        ),
      ),
    );
  }
}

class _ShaderPainter extends CustomPainter {
  _ShaderPainter({
    required this.shader,
    required this.image,
    required this.adjustments,
    required this.preset,
    required this.strength,
  });

  final ui.FragmentShader shader;
  final ui.Image image;
  final ColorAdjustments adjustments;
  final FilterPreset? preset;
  final double strength;

  @override
  void paint(Canvas canvas, Size size) {
    final p = preset;
    var i = 0;
    void f(double v) => shader.setFloat(i++, v);

    f(size.width);
    f(size.height);
    f(adjustments.brightness);
    f(adjustments.contrast);
    f(adjustments.saturation);
    f(adjustments.temperature);
    f(adjustments.tint);
    f(adjustments.highlights);
    f(adjustments.shadows);
    f(p?.brightness ?? 0);
    f(p?.contrast ?? 0);
    f(p?.saturation ?? 0);
    f(p?.temperature ?? 0);
    f(p?.tint ?? 0);
    for (var c = 0; c < 3; c++) {
      f(p?.lift[c] ?? 0);
    }
    for (var c = 0; c < 3; c++) {
      f(p?.gamma[c] ?? 1);
    }
    for (var c = 0; c < 3; c++) {
      f(p?.gain[c] ?? 1);
    }
    f(strength);
    shader.setImageSampler(0, image);

    canvas.drawRect(Offset.zero & size, Paint()..shader = shader);
  }

  @override
  bool shouldRepaint(_ShaderPainter oldDelegate) =>
      oldDelegate.image != image ||
      oldDelegate.adjustments != adjustments ||
      oldDelegate.preset != preset ||
      oldDelegate.strength != strength;
}
