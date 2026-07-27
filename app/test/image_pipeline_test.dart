import 'dart:typed_data';
import 'dart:ui' show Rect;

import 'package:flutter_test/flutter_test.dart';
import 'package:image/image.dart' as img;
import 'package:photo_app/core/edit_ops.dart';
import 'package:photo_app/core/face/retouch_settings.dart';
import 'package:photo_app/core/filter_presets.dart';
import 'package:photo_app/core/image_pipeline.dart';
import 'package:photo_app/core/upscale/upscaler.dart';

/// 4x2 테스트 이미지. 왼쪽 절반은 빨강, 오른쪽 절반은 파랑.
Uint8List makeTestImage() {
  final image = img.Image(width: 4, height: 2);
  for (var y = 0; y < 2; y++) {
    for (var x = 0; x < 4; x++) {
      if (x < 2) {
        image.setPixelRgb(x, y, 255, 0, 0);
      } else {
        image.setPixelRgb(x, y, 0, 0, 255);
      }
    }
  }
  return Uint8List.fromList(img.encodePng(image));
}

img.Image decode(Uint8List bytes) => img.decodeImage(bytes)!;

void main() {
  group('runPipeline', () {
    test('no ops keeps dimensions', () {
      final out = decode(runPipeline(
        PipelineRequest(sourceBytes: makeTestImage(), ops: const []),
      ));
      expect(out.width, 4);
      expect(out.height, 2);
    });

    test('rotate 90 swaps dimensions', () {
      final out = decode(runPipeline(
        PipelineRequest(
          sourceBytes: makeTestImage(),
          ops: const [RotateOp(1)],
        ),
      ));
      expect(out.width, 2);
      expect(out.height, 4);
    });

    test('crop left half keeps red pixels only', () {
      final out = decode(runPipeline(
        PipelineRequest(
          sourceBytes: makeTestImage(),
          ops: const [CropOp(Rect.fromLTWH(0, 0, 0.5, 1))],
          jpegQuality: 100,
        ),
      ));
      expect(out.width, 2);
      expect(out.height, 2);
      final pixel = out.getPixel(0, 0);
      expect(pixel.r, greaterThan(200));
      expect(pixel.b, lessThan(60));
    });

    test('flip horizontal moves blue to the left', () {
      final out = decode(runPipeline(
        PipelineRequest(
          sourceBytes: makeTestImage(),
          ops: const [FlipOp(horizontal: true)],
          jpegQuality: 100,
        ),
      ));
      final pixel = out.getPixel(0, 0);
      expect(pixel.b, greaterThan(200));
      expect(pixel.r, lessThan(60));
    });

    test('maxDimension downscales before ops', () {
      final out = decode(runPipeline(
        PipelineRequest(
          sourceBytes: makeTestImage(),
          ops: const [],
          maxDimension: 2,
        ),
      ));
      expect(out.width, 2);
      expect(out.height, 1);
    });

    test('sequential ops apply in order', () {
      // 회전(4x2 → 2x4) 후 상단 절반 크롭 → 2x2.
      final out = decode(runPipeline(
        PipelineRequest(
          sourceBytes: makeTestImage(),
          ops: const [
            RotateOp(1),
            CropOp(Rect.fromLTWH(0, 0, 1, 0.5)),
          ],
        ),
      ));
      expect(out.width, 2);
      expect(out.height, 2);
    });

    test('adjustments and filter run after geometry ops', () {
      // 모노 필터: 결과가 무채색이어야 한다.
      final out = decode(runPipeline(
        PipelineRequest(
          sourceBytes: makeTestImage(),
          ops: const [RotateOp(1)],
          filterId: 'mono',
          jpegQuality: 100,
        ),
      ));
      expect(out.width, 2);
      expect(out.height, 4);
      final pixel = out.getPixel(0, 0);
      expect((pixel.r - pixel.g).abs(), lessThan(8));
      expect((pixel.g - pixel.b).abs(), lessThan(8));
    });

    test('retouch runs on the geometry result and keeps its size', () {
      // 피부색 잡음 패치를 회전 + 스무딩한다.
      final source = img.Image(width: 80, height: 40);
      for (var y = 0; y < 40; y++) {
        for (var x = 0; x < 80; x++) {
          final d = (x + y).isEven ? 18 : -18;
          source.setPixelRgb(x, y, 230 + d, 180 + d, 150 + d);
        }
      }
      final bytes = Uint8List.fromList(img.encodePng(source));

      img.Image run(FaceRetouchSettings retouch) => decode(runPipeline(
            PipelineRequest(
              sourceBytes: bytes,
              ops: const [RotateOp(1)],
              retouch: retouch,
              jpegQuality: 100,
            ),
          ));

      double energy(img.Image image) {
        var total = 0.0;
        for (var y = 0; y < image.height; y++) {
          for (var x = 1; x < image.width; x++) {
            total +=
                (image.getPixel(x, y).r - image.getPixel(x - 1, y).r).abs();
          }
        }
        return total / (image.height * (image.width - 1));
      }

      final plain = run(FaceRetouchSettings.neutral);
      final smoothed = run(const FaceRetouchSettings(skinSmooth: 1));

      // 회전은 그대로 반영되고,
      expect(smoothed.width, 40);
      expect(smoothed.height, 80);
      // 피부결은 눈에 띄게 줄되 완전히 뭉개지지는 않아야 한다.
      expect(energy(smoothed), lessThan(energy(plain) * 0.8));
      expect(energy(smoothed), greaterThan(0.5));
    });

    test('neutral retouch leaves the pipeline output untouched', () {
      final plain = decode(runPipeline(
        PipelineRequest(sourceBytes: makeTestImage(), ops: const []),
      ));
      final withNeutral = decode(runPipeline(
        PipelineRequest(
          sourceBytes: makeTestImage(),
          ops: const [],
          retouch: FaceRetouchSettings.neutral,
        ),
      ));
      expect(withNeutral.getPixel(0, 0).r, plain.getPixel(0, 0).r);
      expect(withNeutral.getPixel(3, 1).b, plain.getPixel(3, 1).b);
    });

    test('upscale runs last and doubles the output dimensions', () {
      final out = decode(runPipeline(
        PipelineRequest(
          sourceBytes: makeTestImage(),
          ops: const [RotateOp(1)],
          upscale: const UpscaleSettings(factor: 2),
          jpegQuality: 100,
        ),
      ));
      // 4x2 → 회전(2x4) → 2배(4x8)
      expect(out.width, 4);
      expect(out.height, 8);
    });

    test('upscale off keeps dimensions unchanged', () {
      final out = decode(runPipeline(
        PipelineRequest(
          sourceBytes: makeTestImage(),
          ops: const [],
          upscale: UpscaleSettings.off,
        ),
      ));
      expect(out.width, 4);
      expect(out.height, 2);
    });

    test('generateFilterThumbnails returns original + all presets', () {
      final thumbs = generateFilterThumbnails(
        ThumbnailRequest(sourceBytes: makeTestImage(), size: 4),
      );
      expect(thumbs.length, kFilterPresets.length + 1);
      for (final bytes in thumbs) {
        expect(img.decodeImage(bytes), isNotNull);
      }
    });
  });
}
