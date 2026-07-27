import 'package:flutter/foundation.dart';

/// 얼굴 보정 설정. 사용자 의도(숫자)만 담으며 랜드마크는 포함하지 않는다.
/// 랜드마크는 기하 편집이 바뀔 때마다 다시 검출되는 파생 상태다.
@immutable
class FaceRetouchSettings {
  const FaceRetouchSettings({
    this.skinSmooth = 0,
    this.skinTone = 0,
    this.eyeEnlarge = 0,
    this.faceSlim = 0,
    this.noseSlim = 0,
    this.chinShape = 0,
    this.lipFullness = 0,
  });

  static const FaceRetouchSettings neutral = FaceRetouchSettings();

  /// 자연스러운 인물 보정 프리셋 (SODA 계열의 과하지 않은 값).
  static const FaceRetouchSettings natural = FaceRetouchSettings(
    skinSmooth: 0.45,
    skinTone: 0.12,
    eyeEnlarge: 0.15,
    faceSlim: 0.18,
  );

  /// 또렷한 보정 프리셋.
  static const FaceRetouchSettings defined = FaceRetouchSettings(
    skinSmooth: 0.65,
    skinTone: 0.2,
    eyeEnlarge: 0.35,
    faceSlim: 0.4,
    noseSlim: 0.25,
  );

  /// 피부결 스무딩 강도 (0~1).
  final double skinSmooth;

  /// 피부 톤 밝기 (-1~1).
  final double skinTone;

  /// 눈 크기 (0~1).
  final double eyeEnlarge;

  /// 얼굴 슬림 (0~1).
  final double faceSlim;

  /// 코 슬림 (0~1).
  final double noseSlim;

  /// 턱 길이 (-1 짧게 ~ 1 길게).
  final double chinShape;

  /// 입술 볼륨 (-1 얇게 ~ 1 도톰하게).
  final double lipFullness;

  bool get isNeutral =>
      skinSmooth == 0 &&
      skinTone == 0 &&
      eyeEnlarge == 0 &&
      faceSlim == 0 &&
      noseSlim == 0 &&
      chinShape == 0 &&
      lipFullness == 0;

  /// 랜드마크 기반 워핑이 필요한지 (피부 보정만이면 false).
  bool get hasWarp =>
      eyeEnlarge != 0 ||
      faceSlim != 0 ||
      noseSlim != 0 ||
      chinShape != 0 ||
      lipFullness != 0;

  bool get hasSkinWork => skinSmooth != 0 || skinTone != 0;

  FaceRetouchSettings copyWith({
    double? skinSmooth,
    double? skinTone,
    double? eyeEnlarge,
    double? faceSlim,
    double? noseSlim,
    double? chinShape,
    double? lipFullness,
  }) {
    return FaceRetouchSettings(
      skinSmooth: skinSmooth ?? this.skinSmooth,
      skinTone: skinTone ?? this.skinTone,
      eyeEnlarge: eyeEnlarge ?? this.eyeEnlarge,
      faceSlim: faceSlim ?? this.faceSlim,
      noseSlim: noseSlim ?? this.noseSlim,
      chinShape: chinShape ?? this.chinShape,
      lipFullness: lipFullness ?? this.lipFullness,
    );
  }

  @override
  bool operator ==(Object other) =>
      other is FaceRetouchSettings &&
      other.skinSmooth == skinSmooth &&
      other.skinTone == skinTone &&
      other.eyeEnlarge == eyeEnlarge &&
      other.faceSlim == faceSlim &&
      other.noseSlim == noseSlim &&
      other.chinShape == chinShape &&
      other.lipFullness == lipFullness;

  @override
  int get hashCode => Object.hash(skinSmooth, skinTone, eyeEnlarge, faceSlim,
      noseSlim, chinShape, lipFullness);
}
