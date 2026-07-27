import 'dart:typed_data';
import 'dart:ui' show Rect;

import 'package:image/image.dart' as img;

import 'edit_ops.dart';

/// [runPipeline]에 넘기는 요청. compute() 격리(isolate)로 전달되므로
/// 순수 데이터만 담는다.
class PipelineRequest {
  const PipelineRequest({
    required this.sourceBytes,
    required this.ops,
    this.maxDimension,
    this.jpegQuality = 90,
  });

  /// 인코딩된 원본 이미지 바이트 (JPEG/PNG 등).
  final Uint8List sourceBytes;

  /// 순서대로 적용할 편집 연산.
  final List<EditOp> ops;

  /// 지정하면 연산 적용 전에 긴 변 기준으로 다운스케일한다.
  /// 정규화 좌표 연산은 스케일과 무관하므로 결과는 동일한 구도를 유지한다.
  final int? maxDimension;

  final int jpegQuality;
}

/// 디코딩 → EXIF 방향 보정 → (선택) 다운스케일 → 연산 적용 → JPEG 인코딩.
///
/// compute()로 백그라운드 isolate에서 실행하는 최상위 함수.
Uint8List runPipeline(PipelineRequest request) {
  var image = img.decodeImage(request.sourceBytes);
  if (image == null) {
    throw const FormatException('이미지를 디코딩할 수 없습니다.');
  }
  image = img.bakeOrientation(image);

  final maxDim = request.maxDimension;
  if (maxDim != null && (image.width > maxDim || image.height > maxDim)) {
    image = image.width >= image.height
        ? img.copyResize(image,
            width: maxDim, interpolation: img.Interpolation.linear)
        : img.copyResize(image,
            height: maxDim, interpolation: img.Interpolation.linear);
  }

  image = applyOps(image, request.ops);
  return Uint8List.fromList(
    img.encodeJpg(image, quality: request.jpegQuality),
  );
}

/// [ops]를 순서대로 [image]에 적용한다.
img.Image applyOps(img.Image image, List<EditOp> ops) {
  for (final op in ops) {
    image = switch (op) {
      RotateOp(:final turns) => img.copyRotate(image, angle: turns * 90),
      FlipOp(horizontal: true) => img.flipHorizontal(image),
      FlipOp(horizontal: false) => img.flipVertical(image),
      CropOp(:final rect) => _crop(image, rect),
    };
  }
  return image;
}

img.Image _crop(img.Image image, Rect rect) {
  final x = (rect.left * image.width).round().clamp(0, image.width - 1);
  final y = (rect.top * image.height).round().clamp(0, image.height - 1);
  final w = (rect.width * image.width).round().clamp(1, image.width - x);
  final h = (rect.height * image.height).round().clamp(1, image.height - y);
  return img.copyCrop(image, x: x, y: y, width: w, height: h);
}
