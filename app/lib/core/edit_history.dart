import 'edit_ops.dart';

/// 실행취소/다시실행이 가능한 편집 연산 스택.
class EditHistory {
  final List<EditOp> _ops = [];
  final List<EditOp> _redoStack = [];

  /// 현재 적용 중인 연산 목록 (오래된 것부터).
  List<EditOp> get ops => List.unmodifiable(_ops);

  bool get isEmpty => _ops.isEmpty;
  bool get canUndo => _ops.isNotEmpty;
  bool get canRedo => _redoStack.isNotEmpty;

  /// 새 연산을 추가한다. 다시실행 스택은 비워진다.
  void push(EditOp op) {
    _ops.add(op);
    _redoStack.clear();
  }

  /// 마지막 연산을 되돌린다. 되돌린 연산을 반환하며, 없으면 null.
  EditOp? undo() {
    if (_ops.isEmpty) return null;
    final op = _ops.removeLast();
    _redoStack.add(op);
    return op;
  }

  /// 마지막으로 되돌린 연산을 다시 적용한다. 없으면 null.
  EditOp? redo() {
    if (_redoStack.isEmpty) return null;
    final op = _redoStack.removeLast();
    _ops.add(op);
    return op;
  }

  void clear() {
    _ops.clear();
    _redoStack.clear();
  }
}
