import 'dart:math' as math;
import 'dart:ui' show Offset;

import 'face_landmarks.dart';
import 'local_warp.dart';
import 'retouch_settings.dart';

/// 얼굴 하나에 적용할 워프 목록을 만든다.
///
/// [face]는 픽셀 좌표계여야 한다 ([FaceLandmarks.toPixels] 참고).
/// 모든 변형량은 얼굴 크기(눈 사이 거리, 얼굴 폭)에 비례하므로 해상도와
/// 무관하게 같은 결과를 낸다.
List<LocalWarp> buildFaceWarps(
  FaceLandmarks face,
  FaceRetouchSettings settings,
) {
  if (!settings.hasWarp) return const [];

  final warps = <LocalWarp>[];
  final eyeSpan = face.eyeSpan;
  final faceWidth = face.bounds.width;
  final faceHeight = face.bounds.height;
  if (eyeSpan <= 0 || faceWidth <= 0) return const [];

  // 눈 크기: 눈 중심에서 방사 확대.
  if (settings.eyeEnlarge > 0) {
    final radius = eyeSpan * 0.34;
    final expand = 0.22 * settings.eyeEnlarge;
    for (final eye in [face.leftEye, face.rightEye]) {
      if (eye == null) continue;
      warps.add(LocalWarp(center: eye, radius: radius, expand: expand));
    }
  }

  // 얼굴 슬림: 턱선 아래쪽 윤곽점을 얼굴 중심축 쪽으로 당긴다.
  if (settings.faceSlim > 0) {
    final axisX = face.center.dx;
    final eyeLine = face.eyeMidpoint.dy;
    final radius = faceWidth * 0.30;
    final amount = faceWidth * 0.055 * settings.faceSlim;

    for (final point in _sampleJawPoints(face, eyeLine)) {
      final dir = point.dx < axisX ? 1.0 : -1.0;
      // 턱 끝으로 갈수록 강하게, 광대 쪽은 약하게.
      final depth = ((point.dy - eyeLine) / math.max(faceHeight * 0.5, 1e-6))
          .clamp(0.0, 1.0);
      final weight = 0.45 + 0.55 * depth;
      warps.add(LocalWarp(
        center: point,
        radius: radius,
        pull: Offset(dir * amount * weight, 0),
      ));
    }
  }

  // 코 슬림: 콧볼 양옆을 안쪽으로.
  if (settings.noseSlim > 0) {
    final nose = face.noseBase ??
        Offset(face.center.dx, face.eyeMidpoint.dy + eyeSpan * 0.55);
    final halfWidth = eyeSpan * 0.24;
    final radius = eyeSpan * 0.26;
    final amount = eyeSpan * 0.05 * settings.noseSlim;
    warps.add(LocalWarp(
      center: Offset(nose.dx - halfWidth, nose.dy),
      radius: radius,
      pull: Offset(amount, 0),
    ));
    warps.add(LocalWarp(
      center: Offset(nose.dx + halfWidth, nose.dy),
      radius: radius,
      pull: Offset(-amount, 0),
    ));
  }

  // 턱 길이: 턱 끝을 위아래로.
  if (settings.chinShape != 0) {
    warps.add(LocalWarp(
      center: face.chin,
      radius: faceWidth * 0.34,
      pull: Offset(0, faceHeight * 0.06 * settings.chinShape),
    ));
  }

  // 입술 볼륨.
  if (settings.lipFullness != 0) {
    warps.add(LocalWarp(
      center: face.mouthCenter,
      radius: face.mouthWidth * 0.62,
      expand: 0.16 * settings.lipFullness,
    ));
  }

  return warps;
}

/// 여러 얼굴의 워프를 하나로 모은다.
List<LocalWarp> buildAllFaceWarps(
  List<FaceLandmarks> faces,
  FaceRetouchSettings settings,
) {
  return [
    for (final face in faces) ...buildFaceWarps(face, settings),
  ];
}

/// 눈높이 아래 턱선 윤곽에서 좌우 각 3점씩 골라낸다.
/// 윤곽점이 너무 많으면 워프 수가 늘어 느려지므로 균등 샘플링한다.
List<Offset> _sampleJawPoints(FaceLandmarks face, double eyeLine) {
  const perSide = 3;
  final contour = face.resolvedContour();
  final axisX = face.center.dx;

  final left = <Offset>[];
  final right = <Offset>[];
  for (final p in contour) {
    if (p.dy <= eyeLine) continue;
    (p.dx < axisX ? left : right).add(p);
  }

  List<Offset> pick(List<Offset> side) {
    if (side.isEmpty) return const [];
    side.sort((a, b) => a.dy.compareTo(b.dy));
    if (side.length <= perSide) return side;
    return List.generate(perSide, (i) {
      final index = ((i + 0.5) * side.length / perSide).floor();
      return side[index.clamp(0, side.length - 1)];
    });
  }

  return [...pick(left), ...pick(right)];
}
