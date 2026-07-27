/// 플랫폼별 얼굴 검출 구현을 고른다.
///
/// ML Kit은 Android/iOS 전용이라 웹에서는 빈 결과를 돌려주는 스텁을 쓴다.
/// 얼굴이 없어도 피부 보정은 색상 마스크만으로 계속 동작하므로, 웹에서는
/// 랜드마크 워핑(눈 크기·얼굴 슬림 등)만 비활성화된다.
library;

export 'face_detection_web.dart'
    if (dart.library.io) 'face_detection_native.dart';
