import 'package:flutter/foundation.dart';

import '../color_adjustments.dart';

/// 사용자가 저장한 보정 프리셋: 색보정 + (선택) 필터 조합.
///
/// 기하 연산·지우개·얼굴 보정은 사진마다 다른 값이라 담지 않는다.
/// 프리셋은 "이 색감을 다른 사진에도" 를 위한 것이다.
@immutable
class UserPreset {
  const UserPreset({
    required this.id,
    required this.name,
    this.adjustments = ColorAdjustments.neutral,
    this.filterId,
    this.filterStrength = 1.0,
  });

  final String id;
  final String name;
  final ColorAdjustments adjustments;
  final String? filterId;
  final double filterStrength;

  Map<String, dynamic> toJson() => {
        'id': id,
        'name': name,
        'adjustments': adjustments.toJson(),
        if (filterId != null) 'filterId': filterId,
        'filterStrength': filterStrength,
      };

  factory UserPreset.fromJson(Map<String, dynamic> json) {
    return UserPreset(
      id: json['id'] as String,
      name: json['name'] as String,
      adjustments: ColorAdjustments.fromJson(
        (json['adjustments'] as Map<String, dynamic>?) ?? const {},
      ),
      filterId: json['filterId'] as String?,
      filterStrength: (json['filterStrength'] as num?)?.toDouble() ?? 1.0,
    );
  }

  @override
  bool operator ==(Object other) =>
      other is UserPreset &&
      other.id == id &&
      other.name == name &&
      other.adjustments == adjustments &&
      other.filterId == filterId &&
      other.filterStrength == filterStrength;

  @override
  int get hashCode =>
      Object.hash(id, name, adjustments, filterId, filterStrength);
}
