import 'package:flutter/foundation.dart';
import 'package:flutter/painting.dart' show Offset;

/// 지우개 붓질 하나. 좌표는 이미지 크기로 정규화(0.0~1.0)되어 있어
/// 프리뷰에서 칠한 자리가 원본 해상도에서도 같은 곳을 가리킨다.
@immutable
class EraseStroke {
  const EraseStroke({required this.points, required this.radius});

  /// 붓이 지나간 경로. 점 사이는 선분으로 이어 칠한다.
  final List<Offset> points;

  /// 붓 반지름. 이미지 **폭** 기준으로 정규화한다 (세로 기준이 아니라
  /// 폭 하나로 통일해야 가로/세로 사진에서 붓이 타원이 되지 않는다).
  final double radius;

  bool get isEmpty => points.isEmpty || radius <= 0;

  @override
  bool operator ==(Object other) =>
      other is EraseStroke &&
      other.radius == radius &&
      listEquals(other.points, points);

  @override
  int get hashCode => Object.hash(radius, Object.hashAll(points));
}
