import 'dart:math' as math;
import 'dart:typed_data';

import 'package:image/image.dart' as img;

import 'face_landmarks.dart';

/// 피부 보정 (스무딩 + 톤).
///
/// **fast guided filter** (He & Sun)를 쓴다. 축소한 이미지에서 선형 계수
/// (a, b)만 구한 뒤 원본 해상도에서 `q = a·I + b`로 복원하므로,
/// 원본 크기의 부동소수 버퍼를 전혀 만들지 않는다 — 1200만 화소 사진도
/// 수십 MB가 아니라 수백 KB의 작업 메모리로 처리된다.
///
/// 스무딩은 주파수 분리 방식이다. guided filter 결과 `q`가 저주파(톤),
/// `I - q`가 고주파(피부결)이며 고주파를 [textureRetain] 비율만큼 되살려
/// 플라스틱처럼 뭉개지지 않게 한다.
img.Image applySkinRetouch(
  img.Image image, {
  required List<FaceLandmarks> faces,
  required double smooth,
  required double tone,
  double textureRetain = 0.35,
}) {
  if (smooth <= 0 && tone == 0) return image;
  if (image.width < 8 || image.height < 8) return image;

  final low = _downsample(image);
  final lw = low.width;
  final lh = low.height;
  final n = lw * lh;

  final rL = Float32List(n);
  final gL = Float32List(n);
  final bL = Float32List(n);
  var i = 0;
  for (final p in low) {
    rL[i] = p.rNormalized.toDouble();
    gL[i] = p.gNormalized.toDouble();
    bL[i] = p.bNormalized.toDouble();
    i++;
  }

  final mask = _buildSkinMask(rL, gL, bL, lw, lh, faces);
  final tmp = Float32List(n);

  final radius = _guidedRadius(faces, lw, lh);
  final eps = math.pow(0.012 + 0.055 * smooth.clamp(0.0, 1.0), 2).toDouble();

  final guided = smooth > 0
      ? [
          _guidedCoefficients(rL, lw, lh, radius, eps, tmp),
          _guidedCoefficients(gL, lw, lh, radius, eps, tmp),
          _guidedCoefficients(bL, lw, lh, radius, eps, tmp),
        ]
      : null;

  final scaleX = lw / image.width;
  final scaleY = lh / image.height;
  final lift = tone * 0.16;

  for (final pixel in image) {
    final fx = pixel.x * scaleX;
    final fy = pixel.y * scaleY;
    final m = _sampleBilinear(mask, lw, lh, fx, fy);
    if (m <= 0.004) continue;

    var r = pixel.rNormalized.toDouble();
    var g = pixel.gNormalized.toDouble();
    var b = pixel.bNormalized.toDouble();

    if (guided != null) {
      final blend = smooth * m;
      r = _blendChannel(guided[0], lw, lh, fx, fy, r, blend, textureRetain);
      g = _blendChannel(guided[1], lw, lh, fx, fy, g, blend, textureRetain);
      b = _blendChannel(guided[2], lw, lh, fx, fy, b, blend, textureRetain);
    }

    if (lift != 0) {
      final amount = lift * m;
      r += amount;
      g += amount;
      b += amount;
      if (tone > 0) {
        // 붉은 기를 살짝 눌러 톤을 고르게 한다.
        final luma = 0.299 * r + 0.587 * g + 0.114 * b;
        r -= (r - luma) * 0.15 * tone * m;
      }
    }

    pixel.rNormalized = r.clamp(0.0, 1.0);
    pixel.gNormalized = g.clamp(0.0, 1.0);
    pixel.bNormalized = b.clamp(0.0, 1.0);
  }

  return image;
}

double _blendChannel(
  _GuidedMaps maps,
  int lw,
  int lh,
  double fx,
  double fy,
  double value,
  double blend,
  double retain,
) {
  final a = _sampleBilinear(maps.a, lw, lh, fx, fy);
  final b = _sampleBilinear(maps.b, lw, lh, fx, fy);
  final base = a * value + b;
  final detail = value - base;
  final smoothed = base + detail * retain;
  return value + (smoothed - value) * blend;
}

// ---------------------------------------------------------------------------
// guided filter
// ---------------------------------------------------------------------------

class _GuidedMaps {
  const _GuidedMaps(this.a, this.b);

  final Float32List a;
  final Float32List b;
}

/// 자기 안내(self-guided) 필터 계수. 분산이 큰 곳(눈썹·윤곽)은 a→1이 되어
/// 원본이 그대로 남고, 평탄한 피부는 a→0이 되어 지역 평균으로 대체된다.
_GuidedMaps _guidedCoefficients(
  Float32List src,
  int w,
  int h,
  int radius,
  double eps,
  Float32List tmp,
) {
  final n = w * h;
  final square = Float32List(n);
  for (var i = 0; i < n; i++) {
    square[i] = src[i] * src[i];
  }

  final meanI = Float32List(n);
  final meanII = Float32List(n);
  _boxBlur(src, meanI, tmp, w, h, radius);
  _boxBlur(square, meanII, tmp, w, h, radius);

  final a = Float32List(n);
  final b = Float32List(n);
  for (var i = 0; i < n; i++) {
    final mean = meanI[i];
    final variance = math.max(meanII[i] - mean * mean, 0.0);
    final ai = variance / (variance + eps);
    a[i] = ai;
    b[i] = mean * (1 - ai);
  }

  final meanA = Float32List(n);
  final meanB = Float32List(n);
  _boxBlur(a, meanA, tmp, w, h, radius);
  _boxBlur(b, meanB, tmp, w, h, radius);
  return _GuidedMaps(meanA, meanB);
}

int _guidedRadius(List<FaceLandmarks> faces, int lw, int lh) {
  if (faces.isEmpty) return math.max(2, (lw * 0.012).round());
  var widest = 0.0;
  for (final face in faces) {
    widest = math.max(widest, face.bounds.width * lw);
  }
  return math.max(2, (widest * 0.05).round());
}

/// 분리형 박스 블러. 이동 합(running sum)을 써서 반경과 무관하게 픽셀당
/// 상수 시간에 동작한다.
void _boxBlur(
  Float32List src,
  Float32List dst,
  Float32List tmp,
  int w,
  int h,
  int radius,
) {
  _blurHorizontal(src, tmp, w, h, radius);
  _blurVertical(tmp, dst, w, h, radius);
}

void _blurHorizontal(Float32List src, Float32List dst, int w, int h, int r) {
  final norm = 1.0 / (2 * r + 1);
  for (var y = 0; y < h; y++) {
    final row = y * w;
    var sum = 0.0;
    for (var i = -r; i <= r; i++) {
      sum += src[row + i.clamp(0, w - 1)];
    }
    for (var x = 0; x < w; x++) {
      dst[row + x] = sum * norm;
      sum += src[row + math.min(x + r + 1, w - 1)] -
          src[row + math.max(x - r, 0)];
    }
  }
}

void _blurVertical(Float32List src, Float32List dst, int w, int h, int r) {
  final norm = 1.0 / (2 * r + 1);
  for (var x = 0; x < w; x++) {
    var sum = 0.0;
    for (var i = -r; i <= r; i++) {
      sum += src[i.clamp(0, h - 1) * w + x];
    }
    for (var y = 0; y < h; y++) {
      dst[y * w + x] = sum * norm;
      sum += src[math.min(y + r + 1, h - 1) * w + x] -
          src[math.max(y - r, 0) * w + x];
    }
  }
}

double _sampleBilinear(
    Float32List map, int w, int h, double fx, double fy) {
  final cx = fx.clamp(0.0, (w - 1).toDouble());
  final cy = fy.clamp(0.0, (h - 1).toDouble());
  final x0 = cx.floor();
  final y0 = cy.floor();
  final x1 = math.min(x0 + 1, w - 1);
  final y1 = math.min(y0 + 1, h - 1);
  final tx = cx - x0;
  final ty = cy - y0;
  final top = map[y0 * w + x0] * (1 - tx) + map[y0 * w + x1] * tx;
  final bottom = map[y1 * w + x0] * (1 - tx) + map[y1 * w + x1] * tx;
  return top * (1 - ty) + bottom * ty;
}

// ---------------------------------------------------------------------------
// 피부 마스크
// ---------------------------------------------------------------------------

/// 저해상도 피부 마스크 (0~1). 피부색(YCbCr) 판정 × 얼굴 영역 가중치이며,
/// 눈·입은 선명하게 남기려고 제외한다. 마지막에 흐려서 경계를 부드럽게 한다.
Float32List _buildSkinMask(
  Float32List r,
  Float32List g,
  Float32List b,
  int w,
  int h,
  List<FaceLandmarks> faces,
) {
  final n = w * h;
  final mask = Float32List(n);
  for (var y = 0; y < h; y++) {
    final ny = (y + 0.5) / h;
    for (var x = 0; x < w; x++) {
      final i = y * w + x;
      final chroma = _skinChroma(r[i], g[i], b[i]);
      if (chroma <= 0) continue;
      mask[i] = chroma * _faceWeight(faces, (x + 0.5) / w, ny);
    }
  }

  final blurred = Float32List(n);
  final tmp = Float32List(n);
  _boxBlur(mask, blurred, tmp, w, h, math.max(1, (w * 0.01).round()));
  return blurred;
}

/// YCbCr 색공간에서의 피부색 소속도. 경계는 부드럽게 감쇠시킨다.
double _skinChroma(double r, double g, double b) {
  final cb = -0.169 * r - 0.331 * g + 0.500 * b + 0.5;
  final cr = 0.500 * r - 0.419 * g - 0.081 * b + 0.5;
  final wCb = _band(cb, 0.28, 0.32, 0.47, 0.52);
  final wCr = _band(cr, 0.50, 0.54, 0.66, 0.71);
  return wCb * wCr;
}

/// [lo0]~[lo1] 구간에서 0→1, [hi1]~[hi0] 구간에서 1→0으로 변하는 사다리꼴.
double _band(double v, double lo0, double lo1, double hi1, double hi0) {
  return _smoothstep(lo0, lo1, v) * (1 - _smoothstep(hi1, hi0, v));
}

double _smoothstep(double edge0, double edge1, double x) {
  if (edge0 == edge1) return x < edge0 ? 0 : 1;
  final t = ((x - edge0) / (edge1 - edge0)).clamp(0.0, 1.0);
  return t * t * (3 - 2 * t);
}

/// 얼굴 영역 가중치 (정규화 좌표 기준). 얼굴이 검출되지 않았으면 색상
/// 판정만으로 동작하도록 1을 돌려준다.
double _faceWeight(List<FaceLandmarks> faces, double nx, double ny) {
  if (faces.isEmpty) return 1;
  var best = 0.0;
  for (final face in faces) {
    final bounds = face.bounds;
    final rx = bounds.width * 0.62;
    final ry = bounds.height * 0.62;
    if (rx <= 0 || ry <= 0) continue;
    final dx = (nx - bounds.center.dx) / rx;
    final dy = (ny - bounds.center.dy) / ry;
    final distance = math.sqrt(dx * dx + dy * dy);
    var weight = 1 - _smoothstep(0.75, 1.0, distance);
    if (weight <= 0) continue;
    weight *= _featureExclusion(face, nx, ny);
    best = math.max(best, weight);
  }
  return best;
}

/// 눈·입 주변을 마스크에서 빼서 스무딩이 번지지 않게 한다.
double _featureExclusion(FaceLandmarks face, double nx, double ny) {
  var keep = 1.0;
  final eyeRadius = face.eyeSpan * 0.30;
  for (final eye in [face.leftEye, face.rightEye]) {
    if (eye == null) continue;
    keep *= _holeAt(eye.dx, eye.dy, eyeRadius, nx, ny);
  }
  keep *= _holeAt(
    face.mouthCenter.dx,
    face.mouthCenter.dy,
    face.mouthWidth * 0.55,
    nx,
    ny,
  );
  return keep;
}

double _holeAt(double cx, double cy, double radius, double nx, double ny) {
  if (radius <= 0) return 1;
  final d = math.sqrt(
    (nx - cx) * (nx - cx) + (ny - cy) * (ny - cy),
  );
  return _smoothstep(radius * 0.55, radius, d);
}

// ---------------------------------------------------------------------------

/// guided filter 계수를 계산할 저해상도 이미지. 긴 변 512px로 제한한다.
img.Image _downsample(img.Image image, {int maxDimension = 512}) {
  if (image.width <= maxDimension && image.height <= maxDimension) {
    return image;
  }
  return image.width >= image.height
      ? img.copyResize(image,
          width: maxDimension, interpolation: img.Interpolation.average)
      : img.copyResize(image,
          height: maxDimension, interpolation: img.Interpolation.average);
}
