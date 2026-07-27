import 'dart:math' as math;
import 'dart:ui' show Offset;

import 'package:image/image.dart' as img;

/// 반경 [radius] 안에서만 작용하는 국소 워프 하나 (픽셀 좌표계).
///
/// 두 종류의 변형을 합성한다:
/// - [expand]: 중심에서 방사 방향 확대/축소 (눈 크게, 입술 볼륨)
/// - [pull]: 중심 부근을 [pull] 방향으로 이동 (얼굴 슬림, 턱 조정)
///
/// 역방향(backward) 매핑이다. 즉 결과 픽셀마다 "원본의 어느 좌표를 읽을지"를
/// 계산한다.
///
/// 두 변형 모두 `(1 - d²/r²)²` 감쇠를 쓴다. 이 곡선은 반경 경계에서 값과
/// 기울기가 모두 0이라 워프한 영역과 원본이 이어지는 자리에 자국이 남지
/// 않는다. 변위가 반경의 65%를 넘으면 이미지가 접히므로, 호출하는 쪽에서
/// [pull] 크기를 얼굴 크기에 비례한 작은 값으로 유지해야 한다.
class LocalWarp {
  const LocalWarp({
    required this.center,
    required this.radius,
    this.pull = Offset.zero,
    this.expand = 0,
  });

  final Offset center;
  final double radius;
  final Offset pull;
  final double expand;

  bool get isNoop =>
      radius <= 0 || (expand == 0 && pull.dx == 0 && pull.dy == 0);

  /// 결과 좌표 [p]가 읽어야 할 원본 좌표를 반환한다.
  /// 반경 밖이면 [p]를 그대로 돌려준다.
  Offset sourceOf(Offset p) {
    final dx = p.dx - center.dx;
    final dy = p.dy - center.dy;
    final d2 = dx * dx + dy * dy;
    final r2 = radius * radius;
    if (d2 >= r2 || r2 <= 0) return p;

    final t = 1 - d2 / r2;
    final falloff = t * t;

    var sx = p.dx;
    var sy = p.dy;

    if (expand != 0) {
      final f = 1 - expand * falloff;
      sx = center.dx + dx * f;
      sy = center.dy + dy * f;
    }

    if (pull.dx != 0 || pull.dy != 0) {
      sx -= falloff * pull.dx;
      sy -= falloff * pull.dy;
    }

    return Offset(sx, sy);
  }
}

/// [warps]를 순서대로 합성해 [src]에 적용한 새 이미지를 만든다.
///
/// 워프의 영향 반경 밖 픽셀은 그대로 복사되므로, 얼굴 영역만 실제로
/// 리샘플링된다.
img.Image applyWarps(img.Image src, List<LocalWarp> warps) {
  final active = warps.where((w) => !w.isNoop).toList();
  if (active.isEmpty) return src;

  var minX = double.infinity;
  var minY = double.infinity;
  var maxX = double.negativeInfinity;
  var maxY = double.negativeInfinity;
  for (final w in active) {
    minX = math.min(minX, w.center.dx - w.radius);
    minY = math.min(minY, w.center.dy - w.radius);
    maxX = math.max(maxX, w.center.dx + w.radius);
    maxY = math.max(maxY, w.center.dy + w.radius);
  }

  final x0 = minX.floor().clamp(0, src.width - 1);
  final y0 = minY.floor().clamp(0, src.height - 1);
  final x1 = maxX.ceil().clamp(0, src.width - 1);
  final y1 = maxY.ceil().clamp(0, src.height - 1);
  if (x1 < x0 || y1 < y0) return src;

  final dst = src.clone();
  final maxXf = (src.width - 1).toDouble();
  final maxYf = (src.height - 1).toDouble();

  for (var y = y0; y <= y1; y++) {
    for (var x = x0; x <= x1; x++) {
      var p = Offset(x.toDouble(), y.toDouble());
      for (final w in active) {
        p = w.sourceOf(p);
      }
      if (p.dx == x && p.dy == y) continue;

      final sample = src.getPixelLinear(
        p.dx.clamp(0.0, maxXf),
        p.dy.clamp(0.0, maxYf),
      );
      dst.setPixel(x, y, sample);
    }
  }
  return dst;
}
