import 'dart:math' as math;
import 'dart:ui' as ui;

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';

import '../../shared/app_theme.dart';

import '../../core/erase/erase_stroke.dart';
import '../../core/image_pipeline.dart';

/// 지우개 화면. 지우고 싶은 곳을 문지르면 손을 뗄 때 그 자리가
/// 주변 텍스처로 메워진다.
///
/// [imageBytes]는 **지우개를 적용하기 전** 이미지여야 한다. 붓질을 되돌릴 때
/// 항상 이 원본에서 남은 붓질만 다시 적용하므로, 지운 것이 누적되어
/// 뭉개지지 않는다.
class EraseScreen extends StatefulWidget {
  const EraseScreen({
    super.key,
    required this.imageBytes,
    this.initialStrokes = const [],
  });

  final Uint8List imageBytes;
  final List<EraseStroke> initialStrokes;

  @override
  State<EraseScreen> createState() => _EraseScreenState();
}

class _EraseScreenState extends State<EraseScreen> {
  static const double _minRadius = 0.015;
  static const double _maxRadius = 0.12;

  late List<EraseStroke> _strokes = [...widget.initialStrokes];
  final List<Offset> _drawing = [];

  ui.Image? _image;
  double _radius = 0.04;
  bool _processing = false;
  int _generation = 0;
  Size _displaySize = Size.zero;

  @override
  void initState() {
    super.initState();
    if (_strokes.isEmpty) {
      _decode(widget.imageBytes);
    } else {
      _reprocess();
    }
  }

  @override
  void dispose() {
    _image?.dispose();
    super.dispose();
  }

  Future<void> _decode(Uint8List bytes) async {
    final image = await decodeImageFromList(bytes);
    if (!mounted) {
      image.dispose();
      return;
    }
    setState(() {
      _image?.dispose();
      _image = image;
    });
  }

  /// 원본에 현재 붓질 전체를 다시 적용한다.
  Future<void> _reprocess() async {
    final generation = ++_generation;
    setState(() => _processing = true);
    try {
      final bytes = await compute(
        runPipeline,
        PipelineRequest(
          sourceBytes: widget.imageBytes,
          ops: const [],
          erasures: _strokes,
        ),
      );
      if (!mounted || generation != _generation) return;
      await _decode(bytes);
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('지우지 못했어요: $e')),
      );
    } finally {
      if (mounted && generation == _generation) {
        setState(() => _processing = false);
      }
    }
  }

  Offset? _normalize(Offset local) {
    if (_displaySize.width <= 0 || _displaySize.height <= 0) return null;
    return Offset(
      (local.dx / _displaySize.width).clamp(0.0, 1.0),
      (local.dy / _displaySize.height).clamp(0.0, 1.0),
    );
  }

  void _onPanStart(DragStartDetails details) {
    if (_processing) return;
    final p = _normalize(details.localPosition);
    if (p == null) return;
    setState(() {
      _drawing
        ..clear()
        ..add(p);
    });
  }

  void _onPanUpdate(DragUpdateDetails details) {
    if (_processing || _drawing.isEmpty) return;
    final p = _normalize(details.localPosition);
    if (p == null) return;
    setState(() => _drawing.add(p));
  }

  void _onPanEnd(DragEndDetails details) {
    if (_drawing.isEmpty) return;
    final stroke = EraseStroke(points: [..._drawing], radius: _radius);
    setState(() {
      _strokes = [..._strokes, stroke];
      _drawing.clear();
    });
    _reprocess();
  }

  void _undo() {
    if (_strokes.isEmpty || _processing) return;
    setState(() => _strokes = _strokes.sublist(0, _strokes.length - 1));
    if (_strokes.isEmpty) {
      _decode(widget.imageBytes);
    } else {
      _reprocess();
    }
  }

  Size _fitDisplaySize(Size available, ui.Image image) {
    final scale = math.min(
      available.width / image.width,
      available.height / image.height,
    );
    return Size(image.width * scale, image.height * scale);
  }

  @override
  Widget build(BuildContext context) {
    final image = _image;
    final scheme = Theme.of(context).colorScheme;

    return Scaffold(
      backgroundColor: AppColors.canvas,
      appBar: AppBar(
        backgroundColor: AppColors.canvas,
        title: const Text('지우개'),
        actions: [
          IconButton(
            tooltip: '붓질 되돌리기',
            onPressed: _strokes.isEmpty || _processing ? null : _undo,
            icon: const Icon(Icons.undo),
          ),
          TextButton(
            onPressed: image == null || _processing
                ? null
                : () => Navigator.of(context).pop(_strokes),
            child: const Text('완료'),
          ),
        ],
      ),
      body: Column(
        children: [
          Expanded(
            child: image == null
                ? const Center(child: CircularProgressIndicator())
                : Padding(
                    padding: const EdgeInsets.all(12),
                    child: LayoutBuilder(
                      builder: (context, constraints) {
                        _displaySize =
                            _fitDisplaySize(constraints.biggest, image);
                        return Center(
                          child: SizedBox(
                            width: _displaySize.width,
                            height: _displaySize.height,
                            child: GestureDetector(
                              behavior: HitTestBehavior.opaque,
                              onPanStart: _onPanStart,
                              onPanUpdate: _onPanUpdate,
                              onPanEnd: _onPanEnd,
                              child: Stack(
                                fit: StackFit.expand,
                                children: [
                                  RawImage(image: image, fit: BoxFit.fill),
                                  CustomPaint(
                                    painter: _BrushPainter(
                                      points: _drawing,
                                      radius: _radius,
                                      color: scheme.primary,
                                    ),
                                  ),
                                  if (_processing)
                                    const Align(
                                      alignment: Alignment.topCenter,
                                      child: LinearProgressIndicator(
                                          minHeight: 2),
                                    ),
                                ],
                              ),
                            ),
                          ),
                        );
                      },
                    ),
                  ),
          ),
          SafeArea(
            top: false,
            child: Padding(
              padding: const EdgeInsets.fromLTRB(16, 0, 16, 8),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(
                    _strokes.isEmpty
                        ? '지우고 싶은 부분을 문질러 주세요'
                        : '${_strokes.length}번 지웠어요',
                    style: TextStyle(
                      fontSize: 12,
                      color: scheme.onSurfaceVariant,
                    ),
                  ),
                  Row(
                    children: [
                      const Icon(Icons.brush, size: 18),
                      Expanded(
                        child: Slider(
                          value: _radius,
                          min: _minRadius,
                          max: _maxRadius,
                          onChanged: (v) => setState(() => _radius = v),
                        ),
                      ),
                      SizedBox(
                        width: 36,
                        child: Text(
                          (_radius * 100).round().toString(),
                          textAlign: TextAlign.center,
                          style: const TextStyle(fontSize: 12),
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}

/// 손가락이 지나간 자리를 반투명하게 보여준다. 손을 떼면 실제로 지워지고
/// 이 표시는 사라진다.
class _BrushPainter extends CustomPainter {
  const _BrushPainter({
    required this.points,
    required this.radius,
    required this.color,
  });

  final List<Offset> points;
  final double radius;
  final Color color;

  @override
  void paint(Canvas canvas, Size size) {
    if (points.isEmpty) return;
    // 붓 반지름은 이미지 폭 기준이므로 표시에서도 폭을 기준으로 환산한다.
    final strokeWidth = radius * 2 * size.width;
    final paint = Paint()
      ..color = color.withValues(alpha: 0.45)
      ..strokeWidth = strokeWidth
      ..strokeCap = StrokeCap.round
      ..strokeJoin = StrokeJoin.round
      ..style = PaintingStyle.stroke;

    final path = Path()
      ..moveTo(points.first.dx * size.width, points.first.dy * size.height);
    for (final p in points.skip(1)) {
      path.lineTo(p.dx * size.width, p.dy * size.height);
    }
    if (points.length == 1) {
      canvas.drawCircle(
        Offset(points.first.dx * size.width, points.first.dy * size.height),
        strokeWidth / 2,
        Paint()..color = color.withValues(alpha: 0.45),
      );
      return;
    }
    canvas.drawPath(path, paint);
  }

  @override
  bool shouldRepaint(_BrushPainter oldDelegate) =>
      oldDelegate.points.length != points.length ||
      oldDelegate.radius != radius;
}
