import 'dart:math' as math;
import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';

/// 자르기 화면. 확정하면 정규화(0~1) [Rect]를 pop으로 반환한다.
class CropScreen extends StatefulWidget {
  const CropScreen({super.key, required this.imageBytes});

  final Uint8List imageBytes;

  @override
  State<CropScreen> createState() => _CropScreenState();
}

enum _DragMode {
  none,
  move,
  topLeft,
  topRight,
  bottomLeft,
  bottomRight,
  top,
  bottom,
  left,
  right,
}

class _AspectPreset {
  const _AspectPreset(this.label, this.ratio);

  final String label;

  /// 가로/세로 비율. null이면 자유 비율.
  final double? ratio;
}

class _CropScreenState extends State<CropScreen> {
  static const List<_AspectPreset> _presets = [
    _AspectPreset('자유', null),
    _AspectPreset('1:1', 1),
    _AspectPreset('4:5', 4 / 5),
    _AspectPreset('3:4', 3 / 4),
    _AspectPreset('16:9', 16 / 9),
  ];

  static const double _handleHitRadius = 28;
  static const double _minSize = 48;

  ui.Image? _image;

  /// 표시 좌표계(디스플레이된 이미지 기준)의 자르기 사각형.
  Rect? _cropRect;
  Size _displaySize = Size.zero;
  int _presetIndex = 0;
  _DragMode _dragMode = _DragMode.none;
  Rect _dragStartRect = Rect.zero;
  Offset _dragStartPoint = Offset.zero;

  @override
  void initState() {
    super.initState();
    _decode();
  }

  Future<void> _decode() async {
    final image = await decodeImageFromList(widget.imageBytes);
    if (!mounted) {
      image.dispose();
      return;
    }
    setState(() => _image = image);
  }

  @override
  void dispose() {
    _image?.dispose();
    super.dispose();
  }

  double? get _lockedRatio => _presets[_presetIndex].ratio;

  /// 화면 크기에 맞춰 이미지가 표시될 크기(contain)를 계산한다.
  Size _fitDisplaySize(Size available, ui.Image image) {
    final scale = math.min(
      available.width / image.width,
      available.height / image.height,
    );
    return Size(image.width * scale, image.height * scale);
  }

  /// 주어진 비율로 표시 영역 안에서 가장 큰 중앙 사각형을 만든다.
  Rect _centeredRect(Size display, double? ratio) {
    if (ratio == null) return Offset.zero & display;
    var width = display.width;
    var height = width / ratio;
    if (height > display.height) {
      height = display.height;
      width = height * ratio;
    }
    return Rect.fromCenter(
      center: display.center(Offset.zero),
      width: width,
      height: height,
    );
  }

  void _selectPreset(int index) {
    setState(() {
      _presetIndex = index;
      _cropRect = _centeredRect(_displaySize, _presets[index].ratio);
    });
  }

  _DragMode _hitTest(Offset point, Rect rect) {
    bool near(Offset corner) => (point - corner).distance <= _handleHitRadius;
    if (near(rect.topLeft)) return _DragMode.topLeft;
    if (near(rect.topRight)) return _DragMode.topRight;
    if (near(rect.bottomLeft)) return _DragMode.bottomLeft;
    if (near(rect.bottomRight)) return _DragMode.bottomRight;

    // 비율 고정 상태에서는 모서리 드래그가 비율을 깨므로 코너/이동만 허용.
    if (_lockedRatio == null) {
      final inX = point.dx >= rect.left && point.dx <= rect.right;
      final inY = point.dy >= rect.top && point.dy <= rect.bottom;
      if (inX && (point.dy - rect.top).abs() <= _handleHitRadius) {
        return _DragMode.top;
      }
      if (inX && (point.dy - rect.bottom).abs() <= _handleHitRadius) {
        return _DragMode.bottom;
      }
      if (inY && (point.dx - rect.left).abs() <= _handleHitRadius) {
        return _DragMode.left;
      }
      if (inY && (point.dx - rect.right).abs() <= _handleHitRadius) {
        return _DragMode.right;
      }
    }
    if (rect.contains(point)) return _DragMode.move;
    return _DragMode.none;
  }

  void _onPanStart(DragStartDetails details) {
    final rect = _cropRect;
    if (rect == null) return;
    _dragMode = _hitTest(details.localPosition, rect);
    _dragStartRect = rect;
    _dragStartPoint = details.localPosition;
  }

  void _onPanUpdate(DragUpdateDetails details) {
    if (_dragMode == _DragMode.none || _cropRect == null) return;
    final delta = details.localPosition - _dragStartPoint;
    final bounds = Offset.zero & _displaySize;
    var rect = _dragStartRect;

    switch (_dragMode) {
      case _DragMode.move:
        var shifted = rect.shift(delta);
        shifted = shifted.translate(
          shifted.left < 0
              ? -shifted.left
              : (shifted.right > bounds.right
                  ? bounds.right - shifted.right
                  : 0),
          shifted.top < 0
              ? -shifted.top
              : (shifted.bottom > bounds.bottom
                  ? bounds.bottom - shifted.bottom
                  : 0),
        );
        rect = shifted;
      case _DragMode.topLeft:
        rect = _resizeCorner(rect, delta, anchor: rect.bottomRight,
            movingLeft: true, movingTop: true, bounds: bounds);
      case _DragMode.topRight:
        rect = _resizeCorner(rect, delta, anchor: rect.bottomLeft,
            movingLeft: false, movingTop: true, bounds: bounds);
      case _DragMode.bottomLeft:
        rect = _resizeCorner(rect, delta, anchor: rect.topRight,
            movingLeft: true, movingTop: false, bounds: bounds);
      case _DragMode.bottomRight:
        rect = _resizeCorner(rect, delta, anchor: rect.topLeft,
            movingLeft: false, movingTop: false, bounds: bounds);
      case _DragMode.top:
        rect = Rect.fromLTRB(
          rect.left,
          (rect.top + delta.dy).clamp(0.0, rect.bottom - _minSize),
          rect.right,
          rect.bottom,
        );
      case _DragMode.bottom:
        rect = Rect.fromLTRB(
          rect.left,
          rect.top,
          rect.right,
          (rect.bottom + delta.dy).clamp(rect.top + _minSize, bounds.bottom),
        );
      case _DragMode.left:
        rect = Rect.fromLTRB(
          (rect.left + delta.dx).clamp(0.0, rect.right - _minSize),
          rect.top,
          rect.right,
          rect.bottom,
        );
      case _DragMode.right:
        rect = Rect.fromLTRB(
          rect.left,
          rect.top,
          (rect.right + delta.dx).clamp(rect.left + _minSize, bounds.right),
          rect.bottom,
        );
      case _DragMode.none:
        return;
    }
    setState(() => _cropRect = rect);
  }

  /// 코너 드래그. 비율이 고정돼 있으면 반대편 코너를 기준점으로 유지한 채
  /// 비율을 지키며 크기를 조절한다.
  Rect _resizeCorner(
    Rect start,
    Offset delta, {
    required Offset anchor,
    required bool movingLeft,
    required bool movingTop,
    required Rect bounds,
  }) {
    final ratio = _lockedRatio;
    var movingX = (movingLeft ? start.left : start.right) + delta.dx;
    var movingY = (movingTop ? start.top : start.bottom) + delta.dy;

    if (ratio == null) {
      movingX = movingLeft
          ? movingX.clamp(0.0, anchor.dx - _minSize)
          : movingX.clamp(anchor.dx + _minSize, bounds.right);
      movingY = movingTop
          ? movingY.clamp(0.0, anchor.dy - _minSize)
          : movingY.clamp(anchor.dy + _minSize, bounds.bottom);
      return Rect.fromPoints(anchor, Offset(movingX, movingY));
    }

    // 비율 고정: 드래그된 폭을 기준으로 높이를 계산하고 경계로 다시 제한.
    var width = (movingX - anchor.dx).abs();
    var height = width / ratio;

    final maxWidth = movingLeft ? anchor.dx : bounds.right - anchor.dx;
    final maxHeight = movingTop ? anchor.dy : bounds.bottom - anchor.dy;
    final scale = math.min(
      1.0,
      math.min(maxWidth / math.max(width, 1e-6),
          maxHeight / math.max(height, 1e-6)),
    );
    width = math.max(width * scale, _minSize);
    height = width / ratio;
    if (height < _minSize) {
      height = _minSize;
      width = height * ratio;
    }

    final x = movingLeft ? anchor.dx - width : anchor.dx + width;
    final y = movingTop ? anchor.dy - height : anchor.dy + height;
    return Rect.fromPoints(anchor, Offset(x, y));
  }

  void _confirm() {
    final rect = _cropRect;
    if (rect == null || _displaySize == Size.zero) return;
    final normalized = Rect.fromLTRB(
      (rect.left / _displaySize.width).clamp(0.0, 1.0),
      (rect.top / _displaySize.height).clamp(0.0, 1.0),
      (rect.right / _displaySize.width).clamp(0.0, 1.0),
      (rect.bottom / _displaySize.height).clamp(0.0, 1.0),
    );
    Navigator.of(context).pop(normalized);
  }

  @override
  Widget build(BuildContext context) {
    final image = _image;
    return Scaffold(
      backgroundColor: Colors.black,
      appBar: AppBar(
        backgroundColor: Colors.black,
        title: const Text('자르기'),
        actions: [
          TextButton(
            onPressed: image != null ? _confirm : null,
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
                    padding: const EdgeInsets.all(16),
                    child: LayoutBuilder(
                      builder: (context, constraints) {
                        final display =
                            _fitDisplaySize(constraints.biggest, image);
                        if (display != _displaySize) {
                          // 레이아웃 변경(회전 등) 시 크롭 영역을 리셋한다.
                          _displaySize = display;
                          _cropRect =
                              _centeredRect(display, _lockedRatio);
                        }
                        return Center(
                          child: SizedBox(
                            width: display.width,
                            height: display.height,
                            child: GestureDetector(
                              behavior: HitTestBehavior.opaque,
                              onPanStart: _onPanStart,
                              onPanUpdate: _onPanUpdate,
                              onPanEnd: (_) =>
                                  _dragMode = _DragMode.none,
                              child: Stack(
                                fit: StackFit.expand,
                                children: [
                                  RawImage(image: image, fit: BoxFit.fill),
                                  if (_cropRect != null)
                                    CustomPaint(
                                      painter: _CropOverlayPainter(
                                        rect: _cropRect!,
                                      ),
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
            child: SizedBox(
              height: 64,
              child: ListView.separated(
                scrollDirection: Axis.horizontal,
                padding: const EdgeInsets.symmetric(horizontal: 16),
                itemCount: _presets.length,
                separatorBuilder: (_, _) => const SizedBox(width: 8),
                itemBuilder: (context, index) {
                  final selected = index == _presetIndex;
                  return Center(
                    child: ChoiceChip(
                      label: Text(_presets[index].label),
                      selected: selected,
                      onSelected: (_) => _selectPreset(index),
                    ),
                  );
                },
              ),
            ),
          ),
        ],
      ),
    );
  }
}

/// 자르기 영역 밖을 어둡게 처리하고 격자/핸들을 그린다.
class _CropOverlayPainter extends CustomPainter {
  const _CropOverlayPainter({required this.rect});

  final Rect rect;

  @override
  void paint(Canvas canvas, Size size) {
    final outside = Path.combine(
      PathOperation.difference,
      Path()..addRect(Offset.zero & size),
      Path()..addRect(rect),
    );
    canvas.drawPath(outside, Paint()..color = Colors.black54);

    final border = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1.5
      ..color = Colors.white;
    canvas.drawRect(rect, border);

    final grid = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = 0.5
      ..color = Colors.white38;
    for (var i = 1; i < 3; i++) {
      final x = rect.left + rect.width * i / 3;
      final y = rect.top + rect.height * i / 3;
      canvas.drawLine(Offset(x, rect.top), Offset(x, rect.bottom), grid);
      canvas.drawLine(Offset(rect.left, y), Offset(rect.right, y), grid);
    }

    final handle = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = 4
      ..strokeCap = StrokeCap.round
      ..color = Colors.white;
    const len = 18.0;
    void corner(Offset c, double dx, double dy) {
      canvas.drawLine(c, c + Offset(dx * len, 0), handle);
      canvas.drawLine(c, c + Offset(0, dy * len), handle);
    }

    corner(rect.topLeft, 1, 1);
    corner(rect.topRight, -1, 1);
    corner(rect.bottomLeft, 1, -1);
    corner(rect.bottomRight, -1, -1);
  }

  @override
  bool shouldRepaint(_CropOverlayPainter oldDelegate) =>
      oldDelegate.rect != rect;
}
