import 'dart:math' as math;
import 'dart:ui';

/// 검출된 얼굴 하나. 모든 좌표는 이미지 크기로 정규화(0.0~1.0)되어 있어
/// 프리뷰와 원본 해상도에서 동일하게 재사용된다.
///
/// 검출 백엔드(ML Kit 등)에 의존하지 않는 표현이며, 랜드마크가 일부만
/// 검출돼도 동작하도록 모든 세부 좌표에 경계 상자 기반 폴백이 있다.
class FaceLandmarks {
  const FaceLandmarks({
    required this.bounds,
    this.leftEye,
    this.rightEye,
    this.noseBase,
    this.mouthLeft,
    this.mouthRight,
    this.mouthBottom,
    this.faceContour = const [],
  });

  /// 얼굴 경계 상자 (정규화 좌표).
  final Rect bounds;

  /// 화면 기준 왼쪽/오른쪽 눈 중심.
  final Offset? leftEye;
  final Offset? rightEye;
  final Offset? noseBase;
  final Offset? mouthLeft;
  final Offset? mouthRight;
  final Offset? mouthBottom;

  /// 얼굴 외곽선 (윤곽). 비어 있으면 경계 상자 타원으로 대체된다.
  final List<Offset> faceContour;

  Offset get center => bounds.center;

  /// 두 눈 사이 거리. 얼굴 크기의 기준 단위로 쓴다.
  double get eyeSpan {
    final l = leftEye, r = rightEye;
    if (l != null && r != null) {
      final d = (r - l).distance;
      if (d > 1e-4) return d;
    }
    return bounds.width * 0.42;
  }

  /// 두 눈의 중점. 눈이 없으면 경계 상자 상단 1/3 지점.
  Offset get eyeMidpoint {
    final l = leftEye, r = rightEye;
    if (l != null && r != null) return Offset.lerp(l, r, 0.5)!;
    return Offset(bounds.center.dx, bounds.top + bounds.height * 0.38);
  }

  /// 턱 끝. 윤곽선에서 가장 아래 점, 없으면 경계 상자 하단 중앙.
  Offset get chin {
    if (faceContour.isNotEmpty) {
      var lowest = faceContour.first;
      for (final p in faceContour) {
        if (p.dy > lowest.dy) lowest = p;
      }
      return lowest;
    }
    return Offset(bounds.center.dx, bounds.bottom);
  }

  /// 입 중심.
  Offset get mouthCenter {
    final l = mouthLeft, r = mouthRight;
    if (l != null && r != null) return Offset.lerp(l, r, 0.5)!;
    final b = mouthBottom;
    if (b != null) return b;
    return Offset(bounds.center.dx, bounds.top + bounds.height * 0.75);
  }

  double get mouthWidth {
    final l = mouthLeft, r = mouthRight;
    if (l != null && r != null) {
      final d = (r - l).distance;
      if (d > 1e-4) return d;
    }
    return eyeSpan * 0.85;
  }

  /// 얼굴 외곽선. 윤곽이 없으면 경계 상자에 내접하는 타원을 생성한다.
  List<Offset> resolvedContour({int fallbackPoints = 24}) {
    if (faceContour.length >= 4) return faceContour;
    final c = bounds.center;
    final rx = bounds.width / 2;
    final ry = bounds.height / 2;
    return List.generate(fallbackPoints, (i) {
      final t = 2 * math.pi * i / fallbackPoints;
      return Offset(c.dx + rx * math.sin(t), c.dy - ry * math.cos(t));
    });
  }

  /// 정규화 좌표를 [width] × [height] 픽셀 좌표로 변환한 사본.
  FaceLandmarks toPixels(int width, int height) {
    Offset? sc(Offset? p) =>
        p == null ? null : Offset(p.dx * width, p.dy * height);
    return FaceLandmarks(
      bounds: Rect.fromLTRB(
        bounds.left * width,
        bounds.top * height,
        bounds.right * width,
        bounds.bottom * height,
      ),
      leftEye: sc(leftEye),
      rightEye: sc(rightEye),
      noseBase: sc(noseBase),
      mouthLeft: sc(mouthLeft),
      mouthRight: sc(mouthRight),
      mouthBottom: sc(mouthBottom),
      faceContour: [
        for (final p in faceContour) Offset(p.dx * width, p.dy * height),
      ],
    );
  }
}
