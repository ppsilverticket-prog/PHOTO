import 'dart:math' as math;
import 'dart:typed_data';

import 'package:image/image.dart' as img;

/// 화질 개선(업스케일) 설정.
class UpscaleSettings {
  const UpscaleSettings({this.factor = 1, this.sharpen = 0.35});

  static const UpscaleSettings off = UpscaleSettings();

  /// 배율 (1 = 끄기, 2, 4).
  final int factor;

  /// 선명도 (0~1).
  final double sharpen;

  bool get isNoop => factor <= 1;

  UpscaleSettings copyWith({int? factor, double? sharpen}) =>
      UpscaleSettings(
        factor: factor ?? this.factor,
        sharpen: sharpen ?? this.sharpen,
      );

  @override
  bool operator ==(Object other) =>
      other is UpscaleSettings &&
      other.factor == factor &&
      other.sharpen == sharpen;

  @override
  int get hashCode => Object.hash(factor, sharpen);
}

/// 출력 긴 변 상한. 순수 Dart 처리라 이보다 커지면 시간·메모리가
/// 모바일/웹에서 감당하기 어렵다. 이미 큰 사진은 배율이 자동으로 줄어든다.
const int kMaxUpscaleLongSide = 3200;

/// [factor] 요청 시 실제로 적용될 배율. 출력이 [maxLongSide]를 넘지 않도록
/// 줄어들 수 있으며, 1.05 이하로 떨어지면 업스케일은 의미가 없어 1을 준다.
double effectiveUpscale(
  int width,
  int height,
  int factor, {
  int maxLongSide = kMaxUpscaleLongSide,
}) {
  if (factor <= 1 || width <= 0 || height <= 0) return 1;
  final longSide = math.max(width, height);
  var scale = factor.toDouble();
  if (longSide * scale > maxLongSide) scale = maxLongSide / longSide;
  return scale <= 1.05 ? 1 : scale;
}

/// 업스케일 본체: Lanczos-3 확대 → 반복 역투영 → 적응 샤픈.
///
/// - **Lanczos-3**: bicubic보다 선명한 확대. 여기서 잃는 건 없다.
/// - **반복 역투영(iterative back-projection)**: "결과를 다시 축소하면
///   원본과 같아야 한다"는 제약을 반복적으로 강제하는 고전 초해상도 기법.
///   확대 과정에서 뭉개진 대비를 원본과의 오차만큼 되살린다.
/// - **적응 샤픈**: 언샤프 마스크에 이웃 최소/최대 클램프를 걸어,
///   경계 주변에 밝은 띠(헤일로)가 생기지 않게 한다.
///
/// 신경망 모델이 아니므로 없는 디테일을 만들어내지는 않는다. 대신 결과가
/// 원본에 충실하다는 것이 수학적으로 보장되고, 모든 기기·웹에서 돈다.
img.Image upscaleImage(
  img.Image src,
  UpscaleSettings settings, {
  int maxLongSide = kMaxUpscaleLongSide,
}) {
  final scale = effectiveUpscale(
    src.width,
    src.height,
    settings.factor,
    maxLongSide: maxLongSide,
  );
  if (scale == 1) return src;

  final dstW = (src.width * scale).round();
  final dstH = (src.height * scale).round();

  // 채널 추출 (0~1 부동소수).
  final n = src.width * src.height;
  final srcR = Float32List(n);
  final srcG = Float32List(n);
  final srcB = Float32List(n);
  var i = 0;
  for (final p in src) {
    srcR[i] = p.rNormalized.toDouble();
    srcG[i] = p.gNormalized.toDouble();
    srcB[i] = p.bNormalized.toDouble();
    i++;
  }

  final channels = <Float32List>[];
  for (final channel in [srcR, srcG, srcB]) {
    var up = _resample(channel, src.width, src.height, dstW, dstH);

    // 역투영 2회: 오차(원본 - 축소본)를 확대해 되먹인다.
    for (var iteration = 0; iteration < 2; iteration++) {
      final down = _resample(up, dstW, dstH, src.width, src.height);
      final err = Float32List(n);
      for (var k = 0; k < n; k++) {
        err[k] = channel[k] - down[k];
      }
      final errUp = _resample(err, src.width, src.height, dstW, dstH);
      for (var k = 0; k < up.length; k++) {
        up[k] = (up[k] + 0.75 * errUp[k]).clamp(0.0, 1.0);
      }
    }

    // Lanczos 링잉(경계 옆 진동)은 역투영으로 증폭되므로, 각 픽셀을
    // 대응하는 원본 3x3 이웃의 최소~최대 범위로 잘라낸다. 경계 픽셀은
    // 이웃에 밝고 어두운 값이 다 있어 범위가 넓으니 선명함은 유지된다.
    _clampToSourceRange(up, channel, src.width, src.height, dstW, dstH);

    if (settings.sharpen > 0) {
      up = _adaptiveSharpen(up, dstW, dstH, settings.sharpen);
    }
    channels.add(up);
  }

  final dst = img.Image(width: dstW, height: dstH);
  i = 0;
  for (final p in dst) {
    p.rNormalized = channels[0][i];
    p.gNormalized = channels[1][i];
    p.bNormalized = channels[2][i];
    i++;
  }
  return dst;
}

// ---------------------------------------------------------------------------
// Lanczos-3 분리형 리샘플
// ---------------------------------------------------------------------------

class _ResampleKernel {
  _ResampleKernel(this.starts, this.weights, this.taps);

  final Int32List starts;
  final Float32List weights;
  final int taps;
}

double _lanczos3(double x) {
  x = x.abs();
  if (x < 1e-9) return 1;
  if (x >= 3) return 0;
  final pix = math.pi * x;
  return 3 * math.sin(pix) * math.sin(pix / 3) / (pix * pix);
}

/// 목적지 인덱스마다 (시작 원본 인덱스, 정규화된 가중치)를 미리 계산한다.
/// 축소할 때는 커널 폭을 배율만큼 넓혀 저역 통과를 겸한다 (앨리어싱 방지).
_ResampleKernel _buildKernel(int srcSize, int dstSize) {
  final scale = dstSize / srcSize;
  final filterScale = scale < 1 ? 1 / scale : 1.0;
  final support = 3.0 * filterScale;
  final taps = 2 * support.ceil() + 1;

  final starts = Int32List(dstSize);
  final weights = Float32List(dstSize * taps);

  for (var i = 0; i < dstSize; i++) {
    final center = (i + 0.5) / scale - 0.5;
    final start = (center - support).ceil();
    starts[i] = start;

    var sum = 0.0;
    for (var t = 0; t < taps; t++) {
      final x = start + t;
      final w =
          x - center > support ? 0.0 : _lanczos3((x - center) / filterScale);
      weights[i * taps + t] = w;
      sum += w;
    }
    if (sum != 0) {
      for (var t = 0; t < taps; t++) {
        weights[i * taps + t] /= sum;
      }
    }
  }
  return _ResampleKernel(starts, weights, taps);
}

Float32List _resample(
  Float32List src,
  int srcW,
  int srcH,
  int dstW,
  int dstH,
) {
  // 가로 패스: (srcW x srcH) -> (dstW x srcH)
  final kx = _buildKernel(srcW, dstW);
  final mid = Float32List(dstW * srcH);
  for (var y = 0; y < srcH; y++) {
    final row = y * srcW;
    final midRow = y * dstW;
    for (var x = 0; x < dstW; x++) {
      final start = kx.starts[x];
      final wBase = x * kx.taps;
      var acc = 0.0;
      for (var t = 0; t < kx.taps; t++) {
        final sx = (start + t).clamp(0, srcW - 1);
        acc += kx.weights[wBase + t] * src[row + sx];
      }
      mid[midRow + x] = acc;
    }
  }

  // 세로 패스: (dstW x srcH) -> (dstW x dstH)
  final ky = _buildKernel(srcH, dstH);
  final out = Float32List(dstW * dstH);
  for (var y = 0; y < dstH; y++) {
    final start = ky.starts[y];
    final wBase = y * ky.taps;
    final outRow = y * dstW;
    for (var t = 0; t < ky.taps; t++) {
      final sy = (start + t).clamp(0, srcH - 1);
      final w = ky.weights[wBase + t];
      if (w == 0) continue;
      final midRow = sy * dstW;
      for (var x = 0; x < dstW; x++) {
        out[outRow + x] += w * mid[midRow + x];
      }
    }
  }
  return out;
}

/// [up]의 각 픽셀을, 그 픽셀이 유래한 원본 위치의 3x3 이웃 범위로 클램프한다.
void _clampToSourceRange(
  Float32List up,
  Float32List src,
  int srcW,
  int srcH,
  int dstW,
  int dstH,
) {
  const margin = 0.015;

  // 원본의 3x3 최소/최대 맵.
  final lo = Float32List(srcW * srcH);
  final hi = Float32List(srcW * srcH);
  for (var y = 0; y < srcH; y++) {
    for (var x = 0; x < srcW; x++) {
      var mn = 1.0;
      var mx = 0.0;
      for (var dy = -1; dy <= 1; dy++) {
        final ny = (y + dy).clamp(0, srcH - 1);
        for (var dx = -1; dx <= 1; dx++) {
          final nx = (x + dx).clamp(0, srcW - 1);
          final v = src[ny * srcW + nx];
          if (v < mn) mn = v;
          if (v > mx) mx = v;
        }
      }
      lo[y * srcW + x] = mn;
      hi[y * srcW + x] = mx;
    }
  }

  final scaleX = srcW / dstW;
  final scaleY = srcH / dstH;
  for (var y = 0; y < dstH; y++) {
    final sy = ((y + 0.5) * scaleY).floor().clamp(0, srcH - 1);
    final row = y * dstW;
    final srcRow = sy * srcW;
    for (var x = 0; x < dstW; x++) {
      final sx = ((x + 0.5) * scaleX).floor().clamp(0, srcW - 1);
      up[row + x] = up[row + x]
          .clamp(lo[srcRow + sx] - margin, hi[srcRow + sx] + margin)
          .clamp(0.0, 1.0);
    }
  }
}

// ---------------------------------------------------------------------------
// 적응 샤픈 (헤일로 억제)
// ---------------------------------------------------------------------------

/// 언샤프 마스크 + 이웃 3x3 최소/최대 클램프.
///
/// 일반 샤픈은 경계 양옆에 원본에 없던 밝은/어두운 띠(헤일로)를 만든다.
/// 샤픈 결과를 이웃 픽셀의 최소~최대 범위(약간의 여유 포함)로 잘라내면
/// 대비는 올라가되 띠는 생기지 않는다.
Float32List _adaptiveSharpen(
  Float32List src,
  int w,
  int h,
  double strength,
) {
  final blurred = _gaussian3x3(src, w, h);
  final out = Float32List(w * h);
  final amount = strength * 1.2;
  const margin = 0.015;

  for (var y = 0; y < h; y++) {
    for (var x = 0; x < w; x++) {
      final index = y * w + x;
      final value = src[index] + amount * (src[index] - blurred[index]);

      var lo = src[index];
      var hi = src[index];
      for (var dy = -1; dy <= 1; dy++) {
        final ny = (y + dy).clamp(0, h - 1);
        for (var dx = -1; dx <= 1; dx++) {
          final nx = (x + dx).clamp(0, w - 1);
          final neighbor = src[ny * w + nx];
          if (neighbor < lo) lo = neighbor;
          if (neighbor > hi) hi = neighbor;
        }
      }
      out[index] = value.clamp(lo - margin, hi + margin).clamp(0.0, 1.0);
    }
  }
  return out;
}

Float32List _gaussian3x3(Float32List src, int w, int h) {
  // 분리형 (1 2 1)/4.
  final mid = Float32List(w * h);
  for (var y = 0; y < h; y++) {
    final row = y * w;
    for (var x = 0; x < w; x++) {
      final x0 = math.max(x - 1, 0);
      final x1 = math.min(x + 1, w - 1);
      mid[row + x] =
          (src[row + x0] + 2 * src[row + x] + src[row + x1]) / 4;
    }
  }
  final out = Float32List(w * h);
  for (var y = 0; y < h; y++) {
    final y0 = math.max(y - 1, 0) * w;
    final y1 = math.min(y + 1, h - 1) * w;
    final row = y * w;
    for (var x = 0; x < w; x++) {
      out[row + x] = (mid[y0 + x] + 2 * mid[row + x] + mid[y1 + x]) / 4;
    }
  }
  return out;
}

// ---------------------------------------------------------------------------
// 미리보기 패치 (isolate용)
// ---------------------------------------------------------------------------

class UpscalePatchRequest {
  const UpscalePatchRequest({
    required this.sourceBytes,
    required this.settings,
    this.patchSize = 96,
  });

  final Uint8List sourceBytes;
  final UpscaleSettings settings;

  /// 원본에서 잘라낼 중앙 정사각형 한 변 (업스케일 전 기준).
  final int patchSize;
}

class UpscalePatchResult {
  const UpscalePatchResult({
    required this.originalPatch,
    required this.upscaledPatch,
    required this.appliedScale,
  });

  /// 원본 중앙 크롭 (PNG).
  final Uint8List originalPatch;

  /// 같은 크롭을 업스케일한 결과 (PNG).
  final Uint8List upscaledPatch;

  /// 실제 적용 배율 (상한에 걸리면 요청 배율보다 작다).
  final double appliedScale;
}

/// 전/후 비교용 중앙 패치를 만든다. compute()로 실행하는 최상위 함수.
UpscalePatchResult buildUpscalePatch(UpscalePatchRequest request) {
  final image = img.decodeImage(request.sourceBytes);
  if (image == null) {
    throw const FormatException('이미지를 디코딩할 수 없습니다.');
  }

  final side =
      math.min(request.patchSize, math.min(image.width, image.height));
  final crop = img.copyCrop(
    image,
    x: (image.width - side) ~/ 2,
    y: (image.height - side) ~/ 2,
    width: side,
    height: side,
  );

  // 패치는 항상 요청 배율 그대로 보여준다 (전체 저장 시의 상한과 무관하게
  // "이 배율이면 이런 느낌"을 보여주는 것이 목적).
  final upscaled = upscaleImage(crop, request.settings,
      maxLongSide: side * math.max(request.settings.factor, 1));

  // 실제 저장 시 적용될 배율 (전체 이미지 기준).
  final applied = effectiveUpscale(
    image.width,
    image.height,
    request.settings.factor,
  );

  return UpscalePatchResult(
    originalPatch: Uint8List.fromList(img.encodePng(crop)),
    upscaledPatch: Uint8List.fromList(img.encodePng(upscaled)),
    appliedScale: applied,
  );
}
