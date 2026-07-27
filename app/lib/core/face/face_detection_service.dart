import 'dart:io';
import 'dart:typed_data';
import 'dart:ui';

import 'package:google_mlkit_face_detection/google_mlkit_face_detection.dart'
    as mlkit;
import 'package:path_provider/path_provider.dart';

import 'face_landmarks.dart';

/// ML Kit 얼굴 검출 어댑터.
///
/// 검출 결과를 정규화 좌표의 [FaceLandmarks]로 바꿔 앱 나머지 부분이
/// ML Kit에 의존하지 않게 한다. 검출에 실패하면 빈 목록을 돌려주며,
/// 이 경우에도 피부 보정은 색상 기반 마스크로 계속 동작한다.
class FaceDetectionService {
  FaceDetectionService._();

  static final FaceDetectionService instance = FaceDetectionService._();

  mlkit.FaceDetector? _detector;

  mlkit.FaceDetector get _resolved => _detector ??= mlkit.FaceDetector(
        options: mlkit.FaceDetectorOptions(
          enableContours: true,
          enableLandmarks: true,
          performanceMode: mlkit.FaceDetectorMode.accurate,
          minFaceSize: 0.08,
        ),
      );

  /// [jpegBytes]에서 얼굴을 찾는다. [width]/[height]는 해당 이미지의 픽셀
  /// 크기이며 결과를 정규화하는 데 쓰인다.
  Future<List<FaceLandmarks>> detect(
    Uint8List jpegBytes,
    int width,
    int height,
  ) async {
    if (width <= 0 || height <= 0) return const [];
    File? scratch;
    try {
      final dir = await getTemporaryDirectory();
      scratch = File(
        '${dir.path}/face_detect_${DateTime.now().microsecondsSinceEpoch}.jpg',
      );
      await scratch.writeAsBytes(jpegBytes, flush: true);

      final faces = await _resolved.processImage(
        mlkit.InputImage.fromFilePath(scratch.path),
      );
      return [
        for (final face in faces) faceLandmarksFromMlKit(face, width, height),
      ];
    } catch (_) {
      // 검출 실패는 치명적이지 않다 — 얼굴 없이도 편집은 계속된다.
      return const [];
    } finally {
      if (scratch != null && scratch.existsSync()) {
        try {
          scratch.deleteSync();
        } catch (_) {
          // 임시 파일 정리 실패는 무시한다.
        }
      }
    }
  }

  Future<void> dispose() async {
    await _detector?.close();
    _detector = null;
  }
}

/// ML Kit [mlkit.Face]를 정규화 좌표의 [FaceLandmarks]로 변환한다.
FaceLandmarks faceLandmarksFromMlKit(mlkit.Face face, int width, int height) {
  final w = width.toDouble();
  final h = height.toDouble();

  Offset? landmark(mlkit.FaceLandmarkType type) {
    final point = face.landmarks[type]?.position;
    return point == null ? null : Offset(point.x / w, point.y / h);
  }

  final contour = face.contours[mlkit.FaceContourType.face]?.points ?? const [];

  return FaceLandmarks(
    bounds: Rect.fromLTRB(
      face.boundingBox.left / w,
      face.boundingBox.top / h,
      face.boundingBox.right / w,
      face.boundingBox.bottom / h,
    ),
    leftEye: landmark(mlkit.FaceLandmarkType.leftEye),
    rightEye: landmark(mlkit.FaceLandmarkType.rightEye),
    noseBase: landmark(mlkit.FaceLandmarkType.noseBase),
    mouthLeft: landmark(mlkit.FaceLandmarkType.leftMouth),
    mouthRight: landmark(mlkit.FaceLandmarkType.rightMouth),
    mouthBottom: landmark(mlkit.FaceLandmarkType.bottomMouth),
    faceContour: [
      for (final p in contour) Offset(p.x / w, p.y / h),
    ],
  );
}
