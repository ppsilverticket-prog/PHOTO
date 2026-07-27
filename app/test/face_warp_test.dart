import 'dart:ui';

import 'package:flutter_test/flutter_test.dart';
import 'package:photo_app/core/face/face_landmarks.dart';
import 'package:photo_app/core/face/face_warp.dart';
import 'package:photo_app/core/face/retouch_settings.dart';

/// 픽셀 좌표계의 테스트용 얼굴 (200x240 경계 상자).
const FaceLandmarks pixelFace = FaceLandmarks(
  bounds: Rect.fromLTWH(100, 60, 200, 240),
  leftEye: Offset(155, 150),
  rightEye: Offset(245, 150),
  noseBase: Offset(200, 200),
  mouthLeft: Offset(170, 250),
  mouthRight: Offset(230, 250),
);

void main() {
  group('buildFaceWarps', () {
    test('neutral settings produce no warps', () {
      expect(
        buildFaceWarps(pixelFace, FaceRetouchSettings.neutral),
        isEmpty,
      );
    });

    test('skin-only settings produce no warps', () {
      const settings = FaceRetouchSettings(skinSmooth: 0.8, skinTone: 0.3);
      expect(buildFaceWarps(pixelFace, settings), isEmpty);
    });

    test('eye enlarge creates one expanding warp per eye', () {
      const settings = FaceRetouchSettings(eyeEnlarge: 0.5);
      final warps = buildFaceWarps(pixelFace, settings);

      expect(warps.length, 2);
      for (final warp in warps) {
        expect(warp.expand, greaterThan(0));
        expect(warp.radius, greaterThan(0));
      }
      expect(warps.map((w) => w.center), contains(pixelFace.leftEye));
      expect(warps.map((w) => w.center), contains(pixelFace.rightEye));
    });

    test('face slim pulls each side toward the centre axis', () {
      const settings = FaceRetouchSettings(faceSlim: 0.6);
      final warps = buildFaceWarps(pixelFace, settings);

      expect(warps, isNotEmpty);
      final axisX = pixelFace.center.dx;
      for (final warp in warps) {
        expect(warp.pull.dx, isNot(0));
        // 왼쪽 점은 오른쪽으로, 오른쪽 점은 왼쪽으로 당겨야 한다.
        final towardAxis = warp.center.dx < axisX
            ? warp.pull.dx > 0
            : warp.pull.dx < 0;
        expect(towardAxis, isTrue,
            reason: 'warp at ${warp.center} pulls away from the axis');
      }
    });

    test('nose slim creates a symmetric inward pair', () {
      const settings = FaceRetouchSettings(noseSlim: 0.5);
      final warps = buildFaceWarps(pixelFace, settings);

      expect(warps.length, 2);
      final left = warps.firstWhere((w) => w.center.dx < 200);
      final right = warps.firstWhere((w) => w.center.dx > 200);
      expect(left.pull.dx, greaterThan(0));
      expect(right.pull.dx, lessThan(0));
      expect(left.pull.dx, closeTo(-right.pull.dx, 1e-9));
    });

    test('chin shape pulls vertically in the slider direction', () {
      final longer =
          buildFaceWarps(pixelFace, const FaceRetouchSettings(chinShape: 0.5));
      final shorter =
          buildFaceWarps(pixelFace, const FaceRetouchSettings(chinShape: -0.5));

      expect(longer.single.pull.dy, greaterThan(0));
      expect(shorter.single.pull.dy, lessThan(0));
    });

    test('lip fullness expands around the mouth centre', () {
      final warps = buildFaceWarps(
        pixelFace,
        const FaceRetouchSettings(lipFullness: 0.8),
      );
      expect(warps.single.expand, greaterThan(0));
      expect(warps.single.center, pixelFace.mouthCenter);
    });

    test('works without a contour by falling back to the bounding ellipse', () {
      const bare = FaceLandmarks(bounds: Rect.fromLTWH(100, 60, 200, 240));
      final warps =
          buildFaceWarps(bare, const FaceRetouchSettings(faceSlim: 0.5));
      expect(warps, isNotEmpty);
    });

    test('degenerate bounds produce no warps instead of crashing', () {
      const degenerate = FaceLandmarks(bounds: Rect.zero);
      expect(
        buildFaceWarps(degenerate, const FaceRetouchSettings(eyeEnlarge: 1)),
        isEmpty,
      );
    });

    test('warps stay well below the folding threshold at max strength', () {
      // LocalWarp의 감쇠 곡선은 변위가 반경의 65%를 넘으면 이미지를 접는다.
      const extreme = FaceRetouchSettings(
        eyeEnlarge: 1,
        faceSlim: 1,
        noseSlim: 1,
        chinShape: 1,
        lipFullness: 1,
      );
      final warps = buildFaceWarps(pixelFace, extreme);

      expect(warps, isNotEmpty);
      for (final warp in warps) {
        expect(warp.pull.distance, lessThan(warp.radius * 0.65),
            reason: '${warp.center} 의 이동량이 접힘 한계를 넘는다');
        expect(warp.expand.abs(), lessThan(1),
            reason: '${warp.center} 의 확대율이 특이점을 만든다');
      }
    });

    test('buildAllFaceWarps concatenates every face', () {
      const settings = FaceRetouchSettings(eyeEnlarge: 0.5);
      final warps = buildAllFaceWarps([pixelFace, pixelFace], settings);
      expect(warps.length, 4);
    });
  });
}
