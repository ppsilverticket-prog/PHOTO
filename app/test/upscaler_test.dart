import 'package:flutter_test/flutter_test.dart';
import 'package:image/image.dart' as img;
import 'package:photo_app/core/upscale/upscaler.dart';

img.Image solid(int r, int g, int b, {int w = 40, int h = 30}) {
  final image = img.Image(width: w, height: h);
  for (final p in image) {
    p.setRgb(r, g, b);
  }
  return image;
}

/// 왼쪽 절반 어둡고 오른쪽 절반 밝은 수직 경계.
img.Image verticalEdge({int w = 60, int h = 40}) {
  final image = img.Image(width: w, height: h);
  for (var y = 0; y < h; y++) {
    for (var x = 0; x < w; x++) {
      final v = x < w ~/ 2 ? 40 : 220;
      image.setPixelRgb(x, y, v, v, v);
    }
  }
  return image;
}

/// 경계에서의 최대 인접 픽셀 차 — 선명도의 척도.
double edgeContrast(img.Image image) {
  var best = 0.0;
  final y = image.height ~/ 2;
  for (var x = 1; x < image.width; x++) {
    final d =
        (image.getPixel(x, y).r - image.getPixel(x - 1, y).r).abs().toDouble();
    if (d > best) best = d;
  }
  return best;
}

void main() {
  group('effectiveUpscale', () {
    test('factor 1 is always a no-op', () {
      expect(effectiveUpscale(1000, 800, 1), 1);
    });

    test('small images get the full factor', () {
      expect(effectiveUpscale(800, 600, 2), 2);
      expect(effectiveUpscale(700, 500, 4), 4);
    });

    test('large images are clamped to the output cap', () {
      final scale = effectiveUpscale(2400, 1800, 4);
      expect(scale, closeTo(kMaxUpscaleLongSide / 2400, 1e-9));
      expect(scale, lessThan(4));
    });

    test('images already near the cap skip upscaling entirely', () {
      expect(effectiveUpscale(3100, 2000, 4), 1);
      expect(effectiveUpscale(4000, 3000, 2), 1);
    });
  });

  group('upscaleImage', () {
    test('factor 2 doubles the dimensions', () {
      final out = upscaleImage(
        verticalEdge(w: 40, h: 30),
        const UpscaleSettings(factor: 2),
      );
      expect(out.width, 80);
      expect(out.height, 60);
    });

    test('factor 1 returns the source untouched', () {
      final src = verticalEdge();
      expect(identical(upscaleImage(src, UpscaleSettings.off), src), isTrue);
    });

    test('flat colour stays flat — no ringing artifacts', () {
      final out = upscaleImage(
        solid(120, 90, 200),
        const UpscaleSettings(factor: 2, sharpen: 0.8),
      );
      for (final p in out) {
        expect(p.r.toInt(), inInclusiveRange(118, 122));
        expect(p.g.toInt(), inInclusiveRange(88, 92));
        expect(p.b.toInt(), inInclusiveRange(198, 202));
      }
    });

    test('downscaling the result recovers the original (back-projection)', () {
      final src = verticalEdge(w: 40, h: 40);
      final out = upscaleImage(src, const UpscaleSettings(factor: 2, sharpen: 0));
      final down = img.copyResize(out,
          width: 40, height: 40, interpolation: img.Interpolation.average);

      var totalError = 0.0;
      for (var y = 0; y < 40; y++) {
        for (var x = 0; x < 40; x++) {
          totalError += (down.getPixel(x, y).r - src.getPixel(x, y).r).abs();
        }
      }
      expect(totalError / (40 * 40), lessThan(6),
          reason: '축소하면 원본과 거의 같아야 한다');
    });

    test('result is sharper than plain bilinear upscaling', () {
      final src = verticalEdge(w: 40, h: 40);
      final ours = upscaleImage(src, const UpscaleSettings(factor: 2));
      final bilinear = img.copyResize(src,
          width: 80, height: 80, interpolation: img.Interpolation.linear);

      expect(edgeContrast(ours), greaterThanOrEqualTo(edgeContrast(bilinear)));
    });

    test('sharpen never pushes values outside the valid range', () {
      final out = upscaleImage(
        verticalEdge(),
        const UpscaleSettings(factor: 2, sharpen: 1),
      );
      for (final p in out) {
        expect(p.r, inInclusiveRange(0, 255));
      }
    });

    test('anti-halo clamp keeps overshoot near edges small', () {
      // 40 / 220 경계 근처에서 220을 크게 넘거나 40을 크게 밑돌면 헤일로다.
      final out = upscaleImage(
        verticalEdge(w: 60, h: 40),
        const UpscaleSettings(factor: 2, sharpen: 1),
      );
      final y = out.height ~/ 2;
      for (var x = 0; x < out.width; x++) {
        final v = out.getPixel(x, y).r;
        expect(v, lessThanOrEqualTo(230), reason: 'x=$x 밝은 헤일로');
        expect(v, greaterThanOrEqualTo(30), reason: 'x=$x 어두운 헤일로');
      }
    });

    test('cap keeps oversized sources untouched', () {
      final src = solid(100, 100, 100, w: 320, h: 200);
      final out =
          upscaleImage(src, const UpscaleSettings(factor: 4), maxLongSide: 330);
      expect(identical(out, src), isTrue);
    });

    test('fractional clamp lands exactly on the cap', () {
      final src = solid(100, 100, 100, w: 100, h: 60);
      final out =
          upscaleImage(src, const UpscaleSettings(factor: 4), maxLongSide: 300);
      expect(out.width, 300);
      expect(out.height, 180);
    });
  });

  group('buildUpscalePatch', () {
    test('returns decodable before/after patches at the right sizes', () {
      final src = verticalEdge(w: 200, h: 150);
      final result = buildUpscalePatch(UpscalePatchRequest(
        sourceBytes: img.encodePng(src),
        settings: const UpscaleSettings(factor: 2),
        patchSize: 64,
      ));

      final original = img.decodeImage(result.originalPatch)!;
      final upscaled = img.decodeImage(result.upscaledPatch)!;
      expect(original.width, 64);
      expect(original.height, 64);
      expect(upscaled.width, 128);
      expect(upscaled.height, 128);
      expect(result.appliedScale, 2);
    });

    test('reports the clamped scale for oversized sources', () {
      final src = solid(50, 50, 50, w: 3000, h: 100);
      final result = buildUpscalePatch(UpscalePatchRequest(
        sourceBytes: img.encodePng(src),
        settings: const UpscaleSettings(factor: 4),
        patchSize: 32,
      ));
      expect(result.appliedScale, closeTo(kMaxUpscaleLongSide / 3000, 1e-9));
    });
  });
}
