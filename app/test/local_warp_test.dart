import 'package:flutter_test/flutter_test.dart';
import 'package:image/image.dart' as img;
import 'package:photo_app/core/face/local_warp.dart';

img.Image checkerboard(int size) {
  final image = img.Image(width: size, height: size);
  for (var y = 0; y < size; y++) {
    for (var x = 0; x < size; x++) {
      final on = ((x ~/ 4) + (y ~/ 4)).isEven;
      image.setPixelRgb(x, y, on ? 255 : 0, on ? 255 : 0, on ? 255 : 0);
    }
  }
  return image;
}

void main() {
  group('LocalWarp.sourceOf', () {
    test('leaves points outside the radius untouched', () {
      const warp = LocalWarp(
        center: Offset(50, 50),
        radius: 10,
        expand: 0.5,
      );
      const far = Offset(90, 90);
      expect(warp.sourceOf(far), far);
    });

    test('expand samples closer to the centre, magnifying the region', () {
      const warp = LocalWarp(
        center: Offset(50, 50),
        radius: 20,
        expand: 0.4,
      );
      const p = Offset(58, 50);
      final source = warp.sourceOf(p);
      // 결과 픽셀이 중심에 더 가까운 원본을 읽으면 확대되어 보인다.
      expect(source.dx, greaterThan(50));
      expect(source.dx, lessThan(p.dx));
      expect(source.dy, closeTo(50, 1e-9));
    });

    test('negative expand shrinks the region', () {
      const warp = LocalWarp(
        center: Offset(50, 50),
        radius: 20,
        expand: -0.4,
      );
      final source = warp.sourceOf(const Offset(58, 50));
      expect(source.dx, greaterThan(58));
    });

    test('the centre pixel is a fixed point of expand', () {
      const warp = LocalWarp(
        center: Offset(50, 50),
        radius: 20,
        expand: 0.5,
      );
      final source = warp.sourceOf(const Offset(50, 50));
      expect(source.dx, closeTo(50, 1e-9));
      expect(source.dy, closeTo(50, 1e-9));
    });

    test('pull displaces the sample against the pull direction', () {
      const warp = LocalWarp(
        center: Offset(50, 50),
        radius: 20,
        pull: Offset(4, 0),
      );
      final source = warp.sourceOf(const Offset(50, 50));
      // 중심에서 가장 강하게 당겨진다: pull 반대편 원본을 읽는다.
      expect(source.dx, lessThan(50));
    });

    test('pull falls off to zero at the radius boundary', () {
      const warp = LocalWarp(
        center: Offset(50, 50),
        radius: 20,
        pull: Offset(4, 0),
      );
      final near = warp.sourceOf(const Offset(69, 50));
      expect(near.dx, closeTo(69, 0.2));
    });

    test('isNoop detects warps with no effect', () {
      expect(
        const LocalWarp(center: Offset.zero, radius: 10).isNoop,
        isTrue,
      );
      expect(
        const LocalWarp(center: Offset.zero, radius: 0, expand: 0.5).isNoop,
        isTrue,
      );
      expect(
        const LocalWarp(center: Offset.zero, radius: 10, expand: 0.5).isNoop,
        isFalse,
      );
    });
  });

  group('applyWarps', () {
    test('returns the source unchanged when there is nothing to do', () {
      final src = checkerboard(32);
      expect(identical(applyWarps(src, const []), src), isTrue);
      expect(
        identical(
          applyWarps(src, const [LocalWarp(center: Offset.zero, radius: 5)]),
          src,
        ),
        isTrue,
      );
    });

    test('only touches pixels inside the warp radius', () {
      final src = checkerboard(64);
      final out = applyWarps(src, const [
        LocalWarp(center: Offset(32, 32), radius: 10, expand: 0.5),
      ]);

      // 반경 밖 모서리는 원본 그대로여야 한다.
      for (final (x, y) in const [(0, 0), (63, 0), (0, 63), (63, 63)]) {
        expect(out.getPixel(x, y).r, src.getPixel(x, y).r,
            reason: 'pixel ($x, $y) outside the radius changed');
      }
    });

    test('actually modifies pixels inside the radius', () {
      final src = checkerboard(64);
      final out = applyWarps(src, const [
        LocalWarp(center: Offset(32, 32), radius: 12, expand: 0.6),
      ]);

      var changed = 0;
      for (var y = 22; y < 42; y++) {
        for (var x = 22; x < 42; x++) {
          if (out.getPixel(x, y).r != src.getPixel(x, y).r) changed++;
        }
      }
      expect(changed, greaterThan(0));
    });

    test('keeps the output the same size as the input', () {
      final src = checkerboard(48);
      final out = applyWarps(src, const [
        LocalWarp(center: Offset(0, 0), radius: 30, expand: 0.5),
      ]);
      expect(out.width, 48);
      expect(out.height, 48);
    });
  });
}
