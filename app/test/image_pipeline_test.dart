import 'dart:typed_data';
import 'dart:ui' show Rect;

import 'package:flutter_test/flutter_test.dart';
import 'package:image/image.dart' as img;
import 'package:photo_app/core/edit_ops.dart';
import 'package:photo_app/core/image_pipeline.dart';

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
  });
}
