import 'package:flutter_test/flutter_test.dart';
import 'package:photo_app/core/color_adjustments.dart';
import 'package:photo_app/core/edit_ops.dart';
import 'package:photo_app/core/edit_state.dart';

void main() {
  group('HistoryStack', () {
    test('starts at initial value with no undo/redo', () {
      final history = HistoryStack(EditSnapshot.initial);
      expect(history.current.isPristine, isTrue);
      expect(history.canUndo, isFalse);
      expect(history.canRedo, isFalse);
    });

    test('push advances, undo/redo walk the stack', () {
      final history = HistoryStack(EditSnapshot.initial);
      final a = EditSnapshot.initial.addGeometry(const RotateOp(1));
      final b = a.addGeometry(const FlipOp(horizontal: true));
      history.push(a);
      history.push(b);

      expect(history.current, b);
      expect(history.undo(), a);
      expect(history.current, a);
      expect(history.redo(), b);
      expect(history.canRedo, isFalse);
    });

    test('push after undo discards redo branch', () {
      final history = HistoryStack(EditSnapshot.initial);
      final a = EditSnapshot.initial.addGeometry(const RotateOp(1));
      history.push(a);
      history.undo();

      final c = EditSnapshot.initial
          .copyWith(adjustments: const ColorAdjustments(brightness: 0.5));
      history.push(c);

      expect(history.canRedo, isFalse);
      expect(history.current, c);
      expect(history.undo(), EditSnapshot.initial);
    });

    test('undo/redo at bounds return null', () {
      final history = HistoryStack(EditSnapshot.initial);
      expect(history.undo(), isNull);
      expect(history.redo(), isNull);
    });
  });

  group('EditSnapshot', () {
    test('copyWith clearFilter removes filter', () {
      const snapshot = EditSnapshot(filterId: 'mono');
      expect(snapshot.copyWith(clearFilter: true).filterId, isNull);
      expect(snapshot.copyWith().filterId, 'mono');
    });

    test('addGeometry appends without mutating original', () {
      const snapshot = EditSnapshot();
      final next = snapshot.addGeometry(const RotateOp(1));
      expect(snapshot.geometry, isEmpty);
      expect(next.geometry.single, isA<RotateOp>());
    });
  });
}
