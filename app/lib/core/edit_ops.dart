import 'dart:ui';

/// 편집기에서 수행하는 하나의 편집 연산.
///
/// 연산은 순서대로 적용된다. 좌표를 갖는 연산(예: [CropOp])은
/// 항상 "이전 연산이 모두 적용된 이미지" 기준의 정규화 좌표를 쓴다.
sealed class EditOp {
  const EditOp();

  String get label;
}

/// 시계 방향 90도 단위 회전.
class RotateOp extends EditOp {
  const RotateOp(this.turns) : assert(turns >= 1 && turns <= 3);

  /// 시계 방향 90도 회전 횟수 (1 = 90°, 3 = 270° = 반시계 90°).
  final int turns;

  @override
  String get label => '회전';
}

/// 좌우 또는 상하 반전.
class FlipOp extends EditOp {
  const FlipOp({required this.horizontal});

  final bool horizontal;

  @override
  String get label => horizontal ? '좌우 반전' : '상하 반전';
}

/// 정규화(0.0~1.0) 좌표 기준 자르기.
class CropOp extends EditOp {
  const CropOp(this.rect);

  final Rect rect;

  @override
  String get label => '자르기';
}
