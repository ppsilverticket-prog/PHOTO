import 'dart:typed_data';
import 'dart:ui' show Rect;

import 'package:image/image.dart' as img;

import 'color_adjustments.dart';
import 'edit_ops.dart';
import 'erase/erase_stroke.dart';
import 'erase/inpaint.dart';
import 'face/face_landmarks.dart';
import 'face/face_warp.dart';
import 'face/local_warp.dart';
import 'face/retouch_settings.dart';
import 'face/skin_smooth.dart';
import 'filter_presets.dart';
import 'upscale/upscaler.dart';
import 'watermark.dart';

/// [runPipeline]에 넘기는 요청. compute() 격리(isolate)로 전달되므로
/// 순수 데이터만 담는다.
class PipelineRequest {
  const PipelineRequest({
    required this.sourceBytes,
    required this.ops,
    this.erasures = const [],
    this.retouch = FaceRetouchSettings.neutral,
    this.faces = const [],
    this.adjustments = ColorAdjustments.neutral,
    this.filterId,
    this.filterStrength = 1.0,
    this.upscale = UpscaleSettings.off,
    this.watermark = false,
    this.maxDimension,
    this.jpegQuality = 90,
  });

  /// 인코딩된 원본 이미지 바이트 (JPEG/PNG 등).
  final Uint8List sourceBytes;

  /// 순서대로 적용할 기하 연산 (자르기/회전/반전).
  final List<EditOp> ops;

  /// 지우개 붓질. 기하 연산이 적용된 이미지 기준 정규화 좌표다.
  final List<EraseStroke> erasures;

  /// 얼굴 보정 설정 (기하 연산 이후, 색보정 이전에 적용).
  final FaceRetouchSettings retouch;

  /// 기하 연산이 적용된 이미지 기준으로 정규화된 얼굴 랜드마크.
  final List<FaceLandmarks> faces;

  /// 얼굴 보정 이후 적용할 색보정.
  final ColorAdjustments adjustments;

  /// 적용할 필터 프리셋 id (null이면 필터 없음).
  final String? filterId;

  final double filterStrength;

  /// 화질 개선(업스케일). 파이프라인 마지막에 적용되므로 저장 경로에서만
  /// 켜야 한다 — 프리뷰에 켜면 프리뷰 자체가 커져 버린다.
  final UpscaleSettings upscale;

  /// 무료 사용자 저장본에 워터마크를 얹을지. 저장 경로에서만 켠다.
  final bool watermark;

  /// 지정하면 연산 적용 전에 긴 변 기준으로 다운스케일한다.
  /// 정규화 좌표 연산은 스케일과 무관하므로 결과는 동일한 구도를 유지한다.
  final int? maxDimension;

  final int jpegQuality;
}

/// 디코딩 → EXIF 방향 보정 → (선택) 다운스케일 → 기하 연산 → 지우개
/// → 얼굴 보정 → 색보정/필터 → JPEG 인코딩.
/// compute()로 백그라운드 isolate에서 실행하는 최상위 함수.
Uint8List runPipeline(PipelineRequest request) {
  var image = _decodeBase(request.sourceBytes, request.maxDimension);
  image = applyOps(image, request.ops);
  image = applyErasures(image, request.erasures);
  image = applyRetouch(image, request.retouch, request.faces);
  image = applyAdjustmentsCpu(
    image,
    adjustments: request.adjustments,
    preset: filterPresetById(request.filterId),
    strength: request.filterStrength,
  );
  if (!request.upscale.isNoop) {
    image = upscaleImage(image, request.upscale);
  }
  if (request.watermark) {
    image = applyWatermark(image);
  }
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

/// 붓질을 마스크로 그린 뒤 그 영역을 주변 텍스처로 메운다.
img.Image applyErasures(img.Image image, List<EraseStroke> strokes) {
  if (strokes.isEmpty) return image;
  final mask = rasterizeStrokes(strokes, image.width, image.height);
  return inpaintMasked(image, mask);
}

/// 얼굴 워핑 → 피부 보정 순으로 적용한다.
///
/// [faces]는 [image] 기준 정규화 좌표여야 한다. 워핑은 랜드마크가 있어야
/// 동작하지만, 피부 보정은 얼굴이 검출되지 않아도 색상 마스크만으로
/// 동작한다.
img.Image applyRetouch(
  img.Image image,
  FaceRetouchSettings retouch,
  List<FaceLandmarks> faces,
) {
  if (retouch.isNeutral) return image;

  if (retouch.hasWarp && faces.isNotEmpty) {
    final pixelFaces = [
      for (final face in faces) face.toPixels(image.width, image.height),
    ];
    image = applyWarps(image, buildAllFaceWarps(pixelFaces, retouch));
  }

  if (retouch.hasSkinWork) {
    image = applySkinRetouch(
      image,
      faces: faces,
      smooth: retouch.skinSmooth,
      tone: retouch.skinTone,
    );
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
