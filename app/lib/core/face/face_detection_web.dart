import 'dart:typed_data';

import 'face_landmarks.dart';

/// 웹용 스텁. ML Kit에 대응하는 웹 구현이 없으므로 항상 빈 목록을 돌려준다.
///
/// 호출하는 쪽은 얼굴이 검출되지 않은 경우를 이미 처리하고 있어
/// (피부 보정은 색상 마스크로 동작, 워핑 슬라이더는 비활성화)
/// 추가 분기가 필요 없다.
class FaceDetectionService {
  FaceDetectionService._();

  static final FaceDetectionService instance = FaceDetectionService._();

  Future<List<FaceLandmarks>> detect(
    Uint8List jpegBytes,
    int width,
    int height,
  ) async {
    return const [];
  }

  Future<void> dispose() async {}
}
