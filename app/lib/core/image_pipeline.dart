import 'dart:typed_data';
import 'dart:ui' show Rect;

import 'package:image/image.dart' as img;

import 'color_adjustments.dart';
import 'edit_ops.dart';
import 'filter_presets.dart';

/// [runPipeline]에 넘기는 요청. compute() 격리(isolate)로 전달되므로
/// 순수 데이터만 담는다.
class PipelineRequest {
  const PipelineRequest({
    required this.sourceBytes,
    required this.ops,
    this.adjustments = ColorAdjustments.neutral,
    this.filterId,
    this.filterStrength = 1.0,
    this.maxDimension,
    this.jpegQuality = 90,
  });

  /// 인코딩된 원본 이미지 바이트 (JPEG/PNG 등).
  final Uint8List sourceBytes;

  /// 순서대로 적용할 기하 연산 (자르기/회전/반전).
  final List<EditOp> ops;

  /// 기하 연산 이후 적용할 색보정.
  final ColorAdjustments adjustments;

  /// 적용할 필터 프리셋 id (null이면 필터 없음).
  final String? filterId;

  final double filterStrength;

  /// 지정하면 연산 적용 전에 긴 변 기준으로 다운스케일한다.
  /// 정규화 좌표 연산은 스케일과 무관하므로 결과는 동일한 구도를 유지한다.
  final int? maxDimension;

  final int jpegQuality;
}

/// 디코딩 → EXIF 방향 보정 → (선택) 다운스케일 → 기하 연산 → 색보정/필터
/// → JPEG 인코딩. compute()로 백그라운드 isolate에서 실행하는 최상위 함수.
Uint8List runPipeline(PipelineRequest request) {
  var image = _decodeBase(request.sourceBytes, request.maxDimension);
  image = applyOps(image, request.ops);
  image = applyAdjustmentsCpu(
    image,
    adjustments: request.adjustments,
    preset: filterPresetById(request.filterId),
    strength: request.filterStrength,
  );
  return Uint8List.fromList(
    img.encodeJpg(image, quality: request.jpegQuality),
  );
}

img.Image _decodeBase(Uint8List bytes, int? maxDimension) {
  var image = img.decodeImage(bytes);
  if (image == null) {
    throw const FormatException('이미지를 디코딩할 수 없습니다.');
  }
  image = img.bakeOrientation(image);
  if (maxDimension != null &&
      (image.width > maxDimension || image.height > maxDimension)) {
    image = image.width >= image.height
        ? img.copyResize(image,
            width: maxDimension, interpolation: img.Interpolation.linear)
        : img.copyResize(image,
            height: maxDimension, interpolation: img.Interpolation.linear);
  }
  return image;
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

// ---------------------------------------------------------------------------
// 필터 썸네일
// ---------------------------------------------------------------------------

class ThumbnailRequest {
  const ThumbnailRequest({
    required this.sourceBytes,
    this.size = 96,
    this.jpegQuality = 80,
  });

  /// 기하 연산이 이미 적용된 프리뷰 바이트.
  final Uint8List sourceBytes;
  final int size;
  final int jpegQuality;
}

/// "원본"을 포함해 [kFilterPresets] 순서대로 썸네일 JPEG 목록을 만든다.
/// 반환 목록의 첫 번째 항목이 원본(필터 없음)이다.
List<Uint8List> generateFilterThumbnails(ThumbnailRequest request) {
  var base = img.decodeImage(request.sourceBytes);
  if (base == null) {
    throw const FormatException('이미지를 디코딩할 수 없습니다.');
  }
  base = base.width >= base.height
      ? img.copyResize(base, width: request.size)
      : img.copyResize(base, height: request.size);

  final results = <Uint8List>[
    Uint8List.fromList(img.encodeJpg(base, quality: request.jpegQuality)),
  ];
  for (final preset in kFilterPresets) {
    final filtered = applyAdjustmentsCpu(base.clone(), preset: preset);
    results.add(
      Uint8List.fromList(
        img.encodeJpg(filtered, quality: request.jpegQuality),
      ),
    );
  }
  return results;
}
