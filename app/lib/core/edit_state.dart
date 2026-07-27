import 'package:flutter/foundation.dart';

import 'color_adjustments.dart';
import 'edit_ops.dart';
import 'erase/erase_stroke.dart';
import 'face/retouch_settings.dart';
import 'upscale/upscaler.dart';

/// 특정 시점의 전체 편집 상태.
///
/// 기하 연산(자르기/회전/반전)과 색보정/필터를 함께 스냅샷으로 관리해
/// 어떤 변경이든 undo/redo 한 번으로 되돌릴 수 있다.
@immutable
class EditSnapshot {
  const EditSnapshot({
    this.geometry = const [],
    this.erasures = const [],
    this.retouch = FaceRetouchSettings.neutral,
    this.adjustments = ColorAdjustments.neutral,
    this.filterId,
    this.filterStrength = 1.0,
    this.upscale = UpscaleSettings.off,
  });

  static const EditSnapshot initial = EditSnapshot();

  final List<EditOp> geometry;
  final List<EraseStroke> erasures;
  final FaceRetouchSettings retouch;
  final ColorAdjustments adjustments;
  final String? filterId;
  final double filterStrength;
  final UpscaleSettings upscale;

  bool get isPristine =>
      geometry.isEmpty &&
      erasures.isEmpty &&
      retouch.isNeutral &&
      adjustments.isNeutral &&
      filterId == null &&
      upscale.isNoop;

  EditSnapshot copyWith({
    List<EditOp>? geometry,
    List<EraseStroke>? erasures,
    FaceRetouchSettings? retouch,
    ColorAdjustments? adjustments,
    String? filterId,
    bool clearFilter = false,
    double? filterStrength,
    UpscaleSettings? upscale,
  }) {
    return EditSnapshot(
      geometry: geometry ?? this.geometry,
      erasures: erasures ?? this.erasures,
      retouch: retouch ?? this.retouch,
      adjustments: adjustments ?? this.adjustments,
      filterId: clearFilter ? null : (filterId ?? this.filterId),
      filterStrength: filterStrength ?? this.filterStrength,
      upscale: upscale ?? this.upscale,
    );
  }

  EditSnapshot addGeometry(EditOp op) =>
      copyWith(geometry: [...geometry, op]);
}

/// 스냅샷 기반 undo/redo 스택.
class HistoryStack<T> {
  HistoryStack(T initial) : _stack = [initial];

  final List<T> _stack;
  int _index = 0;

  T get current => _stack[_index];
  bool get canUndo => _index > 0;
  bool get canRedo => _index < _stack.length - 1;

  void push(T value) {
    _stack.removeRange(_index + 1, _stack.length);
    _stack.add(value);
    _index++;
  }

  T? undo() => canUndo ? _stack[--_index] : null;

  T? redo() => canRedo ? _stack[++_index] : null;
}
