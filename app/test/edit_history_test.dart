import 'package:flutter_test/flutter_test.dart';
import 'package:photo_app/core/edit_history.dart';
import 'package:photo_app/core/edit_ops.dart';

void main() {
  group('EditHistory', () {
    test('push adds ops in order', () {
      final history = EditHistory();
      history.push(const RotateOp(1));
      history.push(const FlipOp(horizontal: true));

      expect(history.ops.length, 2);
      expect(history.ops.first, isA<RotateOp>());
      expect(history.ops.last, isA<FlipOp>());
      expect(history.canUndo, isTrue);
      expect(history.canRedo, isFalse);
    });

    test('undo moves op to redo stack', () {
      final history = EditHistory();
      history.push(const RotateOp(1));
      history.push(const RotateOp(2));

      final undone = history.undo();

      expect(undone, isA<RotateOp>());
      expect((undone! as RotateOp).turns, 2);
      expect(history.ops.length, 1);
      expect(history.canRedo, isTrue);
    });

    test('redo re-applies last undone op', () {
      final history = EditHistory();
      history.push(const RotateOp(1));
      history.undo();

      final redone = history.redo();

      expect(redone, isA<RotateOp>());
      expect(history.ops.length, 1);
      expect(history.canRedo, isFalse);
    });

    test('push clears redo stack', () {
      final history = EditHistory();
      history.push(const RotateOp(1));
      history.undo();
      history.push(const FlipOp(horizontal: false));

      expect(history.canRedo, isFalse);
      expect(history.ops.single, isA<FlipOp>());
    });

    test('undo/redo on empty history return null', () {
      final history = EditHistory();
      expect(history.undo(), isNull);
      expect(history.redo(), isNull);
    });
  });
}
