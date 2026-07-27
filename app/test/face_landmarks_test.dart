import 'dart:math' show Point;
import 'dart:ui';

import 'package:flutter_test/flutter_test.dart';
import 'package:google_mlkit_face_detection/google_mlkit_face_detection.dart'
    as mlkit;
import 'package:photo_app/core/face/face_detection_service.dart';
import 'package:photo_app/core/face/face_landmarks.dart';

void main() {
  group('FaceLandmarks fallbacks', () {
    test('eyeSpan uses the eye distance when both eyes are known', () {
      const face = FaceLandmarks(
        bounds: Rect.fromLTWH(0, 0, 100, 120),
        leftEye: Offset(40, 50),
        rightEye: Offset(70, 50),
      );
      expect(face.eyeSpan, closeTo(30, 1e-9));
    });

    test('eyeSpan falls back to the bounding box width', () {
      const face = FaceLandmarks(bounds: Rect.fromLTWH(0, 0, 100, 120));
      expect(face.eyeSpan, closeTo(42, 1e-9));
    });

    test('chin uses the lowest contour point when available', () {
      const face = FaceLandmarks(
        bounds: Rect.fromLTWH(0, 0, 100, 120),
        faceContour: [Offset(20, 40), Offset(50, 118), Offset(80, 40)],
      );
      expect(face.chin, const Offset(50, 118));
    });

    test('chin falls back to the bottom centre of the bounds', () {
      const face = FaceLandmarks(bounds: Rect.fromLTWH(0, 0, 100, 120));
      expect(face.chin, const Offset(50, 120));
    });

    test('mouthCenter is the midpoint of the mouth corners', () {
      const face = FaceLandmarks(
        bounds: Rect.fromLTWH(0, 0, 100, 120),
        mouthLeft: Offset(40, 90),
        mouthRight: Offset(60, 90),
      );
      expect(face.mouthCenter, const Offset(50, 90));
    });

    test('resolvedContour synthesises an ellipse inside the bounds', () {
      const face = FaceLandmarks(bounds: Rect.fromLTWH(10, 20, 100, 120));
      final contour = face.resolvedContour();

      expect(contour.length, greaterThanOrEqualTo(4));
      for (final p in contour) {
        expect(p.dx, inInclusiveRange(9.9, 110.1));
        expect(p.dy, inInclusiveRange(19.9, 140.1));
      }
    });

    test('toPixels scales normalised coordinates to the image size', () {
      const face = FaceLandmarks(
        bounds: Rect.fromLTRB(0.25, 0.1, 0.75, 0.6),
        leftEye: Offset(0.4, 0.3),
        faceContour: [Offset(0.5, 0.5)],
      );
      final pixels = face.toPixels(400, 200);

      expect(pixels.bounds.left, closeTo(100, 1e-9));
      expect(pixels.bounds.top, closeTo(20, 1e-9));
      expect(pixels.bounds.right, closeTo(300, 1e-9));
      expect(pixels.leftEye, const Offset(160, 60));
      expect(pixels.faceContour.single, const Offset(200, 100));
    });
  });

  group('faceLandmarksFromMlKit', () {
    test('normalises the bounding box, landmarks and contour', () {
      final face = mlkit.Face(
        boundingBox: const Rect.fromLTRB(100, 50, 300, 250),
        landmarks: {
          mlkit.FaceLandmarkType.leftEye: mlkit.FaceLandmark(
            type: mlkit.FaceLandmarkType.leftEye,
            position: const Point(150, 120),
          ),
        },
        contours: {
          mlkit.FaceContourType.face: mlkit.FaceContour(
            type: mlkit.FaceContourType.face,
            points: const [Point(120, 80), Point(200, 240)],
          ),
        },
      );

      final result = faceLandmarksFromMlKit(face, 400, 500);

      expect(result.bounds.left, closeTo(0.25, 1e-9));
      expect(result.bounds.top, closeTo(0.10, 1e-9));
      expect(result.bounds.right, closeTo(0.75, 1e-9));
      expect(result.bounds.bottom, closeTo(0.50, 1e-9));
      expect(result.leftEye!.dx, closeTo(0.375, 1e-9));
      expect(result.leftEye!.dy, closeTo(0.24, 1e-9));
      expect(result.faceContour.length, 2);
      expect(result.faceContour.first.dx, closeTo(0.3, 1e-9));
    });

    test('missing landmarks and contours stay null or empty', () {
      final face = mlkit.Face(
        boundingBox: const Rect.fromLTRB(0, 0, 100, 100),
        landmarks: const {},
        contours: const {},
      );

      final result = faceLandmarksFromMlKit(face, 200, 200);

      expect(result.leftEye, isNull);
      expect(result.noseBase, isNull);
      expect(result.faceContour, isEmpty);
      // 폴백 덕분에 워프 계산에 필요한 값은 여전히 얻을 수 있다.
      expect(result.eyeSpan, greaterThan(0));
    });
  });
}
