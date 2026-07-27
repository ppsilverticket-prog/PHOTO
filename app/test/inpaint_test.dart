import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:image/image.dart' as img;
import 'package:photo_app/core/erase/erase_stroke.dart';
import 'package:photo_app/core/erase/inpaint.dart';

img.Image solid(int r, int g, int b, {int size = 64}) {
  final image = img.Image(width: size, height: size);
  for (final p in image) {
    p.setRgb(r, g, b);
  }
  return image;
}

/// 세로 줄무늬. 구조가 이어지는지 보기 위한 패턴.
img.Image verticalStripes({int size = 64, int period = 8}) {
  final image = img.Image(width: size, height: size);
  for (var y = 0; y < size; y++) {
    for (var x = 0; x < size; x++) {
      final on = (x ~/ period).isEven;
      image.setPixelRgb(x, y, on ? 240 : 20, on ? 60 : 200, on ? 40 : 180);
    }
  }
  return image;
}

Uint8List rectMask(int width, int height, int x0, int y0, int w, int h) {
  final mask = Uint8List(width * height);
  for (var y = y0; y < y0 + h; y++) {
    for (var x = x0; x < x0 + w; x++) {
      mask[y * width + x] = 255;
    }
  }
  return mask;
}

void main() {
  group('rasterizeStrokes', () {
    test('a single point paints a disc', () {
      final mask = rasterizeStrokes(
        const [
          EraseStroke(points: [Offset(0.5, 0.5)], radius: 0.1),
        ],
        100,
        100,
      );
      expect(mask[50 * 100 + 50], 255);
      expect(mask[50 * 100 + 55], 255, reason: '반지름 10px 안');
      expect(mask[50 * 100 + 70], 0, reason: '반지름 밖');
    });

    test('a line paints a connected band with no gaps', () {
      final mask = rasterizeStrokes(
        const [
          EraseStroke(
            points: [Offset(0.1, 0.5), Offset(0.9, 0.5)],
            radius: 0.03,
          ),
        ],
        100,
        100,
      );
      for (var x = 12; x <= 88; x++) {
        expect(mask[50 * 100 + x], 255, reason: 'x=$x 에서 선이 끊겼다');
      }
    });

    test('radius is normalised to width so the brush stays round', () {
      // 가로로 긴 이미지에서도 붓의 가로/세로 반지름이 같아야 한다.
      final mask = rasterizeStrokes(
        const [
          EraseStroke(points: [Offset(0.5, 0.5)], radius: 0.1),
        ],
        200,
        100,
      );
      // 폭 200 -> 반지름 20px. 중심 (100, 50).
      expect(mask[50 * 200 + 118], 255);
      expect(mask[(50 + 18) * 200 + 100], 255);
      expect(mask[50 * 200 + 122], 0);
      expect(mask[(50 + 22) * 200 + 100], 0);
    });

    test('empty strokes produce an empty mask', () {
      final mask = rasterizeStrokes(
        const [EraseStroke(points: [], radius: 0.1)],
        32,
        32,
      );
      expect(mask.every((v) => v == 0), isTrue);
    });
  });

  group('inpaintMasked', () {
    test('an empty mask leaves the image untouched', () {
      final image = verticalStripes();
      final before = image.getPixel(30, 30).r;
      inpaintMasked(image, Uint8List(64 * 64));
      expect(image.getPixel(30, 30).r, before);
    });

    test('fills a hole in a flat region with the surrounding colour', () {
      final image = solid(120, 90, 200);
      inpaintMasked(image, rectMask(64, 64, 26, 26, 12, 12));

      for (var y = 26; y < 38; y++) {
        for (var x = 26; x < 38; x++) {
          final p = image.getPixel(x, y);
          expect(p.r, closeTo(120, 12), reason: '($x, $y)');
          expect(p.g, closeTo(90, 12), reason: '($x, $y)');
          expect(p.b, closeTo(200, 12), reason: '($x, $y)');
        }
      }
    });

    test('continues vertical stripes across the hole', () {
      final image = verticalStripes(size: 64, period: 8);
      final expected = [
        for (var x = 0; x < 64; x++) image.getPixel(x, 0).r,
      ];

      inpaintMasked(image, rectMask(64, 64, 24, 24, 16, 16));

      // 채워진 자리도 원래 줄무늬 색이어야 한다 (경계 1px은 섞이므로 제외).
      for (var y = 25; y < 39; y++) {
        for (var x = 25; x < 39; x++) {
          expect(image.getPixel(x, y).r, closeTo(expected[x], 40),
              reason: '($x, $y) 에서 줄무늬가 끊겼다');
        }
      }
    });

    test('leaves no unfilled pixels behind', () {
      // 확실히 눈에 띄는 색으로 칠했다가 지워, 잔여 픽셀이 남는지 본다.
      final image = solid(10, 200, 30);
      for (var y = 20; y < 44; y++) {
        for (var x = 20; x < 44; x++) {
          image.setPixelRgb(x, y, 255, 0, 255);
        }
      }
      inpaintMasked(image, rectMask(64, 64, 20, 20, 24, 24));

      for (var y = 20; y < 44; y++) {
        for (var x = 20; x < 44; x++) {
          final p = image.getPixel(x, y);
          final isMagenta = p.r > 200 && p.g < 60 && p.b > 200;
          expect(isMagenta, isFalse, reason: '($x, $y) 가 그대로 남았다');
        }
      }
    });

    test('leaves no dark fringe at the mask boundary', () {
      // 지우는 대상과 경계를 섞으면 그 물체의 윤곽이 반쯤 남는다.
      // 밝은 배경 위 검은 막대를 지우고, 테두리까지 어둡지 않은지 본다.
      final image = solid(220, 210, 200, size: 80);
      const x0 = 20, y0 = 34, w = 40, h = 12;
      for (var y = y0; y < y0 + h; y++) {
        for (var x = x0; x < x0 + w; x++) {
          image.setPixelRgb(x, y, 10, 10, 12);
        }
      }

      inpaintMasked(image, rectMask(80, 80, x0, y0, w, h));

      for (var y = y0 - 1; y < y0 + h + 1; y++) {
        for (var x = x0 - 1; x < x0 + w + 1; x++) {
          final p = image.getPixel(x, y);
          expect(p.r, greaterThan(150),
              reason: '($x, $y) 에 지운 물체의 잔상이 남았다');
        }
      }
    });

    test('a mask covering everything does not crash or hang', () {
      final image = solid(80, 80, 80, size: 32);
      final mask = Uint8List(32 * 32)..fillRange(0, 32 * 32, 255);
      expect(() => inpaintMasked(image, mask), returnsNormally);
    });

    test('a mask touching the border is handled', () {
      final image = verticalStripes(size: 48);
      expect(
        () => inpaintMasked(image, rectMask(48, 48, 0, 0, 10, 10)),
        returnsNormally,
      );
    });

    test('large masks take the downscaled path and still fill fully', () {
      final image = solid(200, 120, 60, size: 400);
      for (var y = 60; y < 340; y++) {
        for (var x = 60; x < 340; x++) {
          image.setPixelRgb(x, y, 0, 0, 0);
        }
      }
      inpaintMasked(
        image,
        rectMask(400, 400, 60, 60, 280, 280),
        maxMaskDimension: 80,
      );

      for (var y = 62; y < 338; y += 7) {
        for (var x = 62; x < 338; x += 7) {
          final p = image.getPixel(x, y);
          expect(p.r + p.g + p.b, greaterThan(60), reason: '($x, $y) 가 검게 남았다');
        }
      }
    });

    test('pixels well outside the mask are never modified', () {
      // 마스크는 잔상 방지를 위해 몇 px 넓혀지므로, 충분히 떨어진 행으로 본다.
      final image = verticalStripes(size: 64);
      final untouched = [
        for (var x = 0; x < 64; x++) image.getPixel(x, 5).r,
      ];
      inpaintMasked(image, rectMask(64, 64, 24, 24, 16, 16));

      for (var x = 0; x < 64; x++) {
        expect(image.getPixel(x, 5).r, untouched[x], reason: 'x=$x');
      }
    });
  });
}
