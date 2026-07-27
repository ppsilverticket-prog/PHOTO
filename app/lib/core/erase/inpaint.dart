import 'dart:math' as math;
import 'dart:typed_data';

import 'package:image/image.dart' as img;

import 'erase_stroke.dart';

/// 칠해진 영역을 주변에서 가져온 텍스처로 메운다.
///
/// Criminisi 등의 exemplar-based inpainting이다. 채울 영역의 경계에서
/// 우선순위가 가장 높은 지점을 골라, 주변 알려진 영역에서 가장 비슷한
/// 패치를 찾아 복사하는 일을 반복한다.
///
/// 우선순위는 두 항의 곱이다:
/// - **신뢰도**: 이미 알려진 픽셀에 많이 둘러싸인 곳부터 채운다 (바깥→안쪽).
/// - **구조항(isophote)**: 경계를 가로지르는 윤곽선이 강한 곳을 먼저 채워
///   선이나 경계가 끊기지 않고 이어지게 한다.
///
/// 비용은 마스크 크기에 비례하므로, 큰 마스크는 [maxMaskDimension]에 맞춰
/// 축소해 계산한 뒤 되돌린다. 덕분에 사진이 아무리 커도 처리 시간이
/// 일정 범위 안에 머문다.
img.Image inpaintMasked(
  img.Image image,
  Uint8List mask, {
  int patchRadius = 4,
  int searchRadius = 48,
  int maxMaskDimension = 160,
}) {
  // 지울 대상의 경계에는 JPEG 압축 잔물결이나 반투명 테두리가 남기 마련이라,
  // 칠한 자리를 아주 조금 넓혀야 지운 자리에 윤곽선 잔상이 남지 않는다.
  mask = _dilate(mask, image.width, image.height,
      math.max(1, (math.min(image.width, image.height) * 0.002).round()));

  final bounds = _maskBounds(mask, image.width, image.height);
  if (bounds == null) return image;

  // 관심 영역(ROI): 마스크 + 패치를 찾아올 여유 공간.
  // 전체 이미지를 훑지 않으므로 큰 사진에서도 비용이 마스크 크기에만 걸린다.
  final margin = searchRadius + patchRadius + 2;
  final roi = _Rect(
    math.max(0, bounds.x - margin),
    math.max(0, bounds.y - margin),
    0,
    0,
  );
  roi.w = math.min(image.width, bounds.x + bounds.w + margin) - roi.x;
  roi.h = math.min(image.height, bounds.y + bounds.h + margin) - roi.y;
  if (roi.w < 3 || roi.h < 3) return image;

  var work = img.copyCrop(image,
      x: roi.x, y: roi.y, width: roi.w, height: roi.h);
  var workMask = _cropMask(mask, image.width, roi);
  var workW = roi.w;
  var workH = roi.h;

  final longestSide = math.max(bounds.w, bounds.h);
  final scale =
      longestSide > maxMaskDimension ? maxMaskDimension / longestSide : 1.0;
  if (scale < 1.0) {
    final scaledW = math.max(3, (roi.w * scale).round());
    final scaledH = math.max(3, (roi.h * scale).round());
    work = img.copyResize(work,
        width: scaledW,
        height: scaledH,
        interpolation: img.Interpolation.average);
    workMask = _resizeMask(workMask, workW, workH, scaledW, scaledH);
    workW = scaledW;
    workH = scaledH;
  }

  _inpaintInPlace(work, workMask, workW, workH, patchRadius, searchRadius);

  if (scale < 1.0) {
    work = img.copyResize(work,
        width: roi.w,
        height: roi.h,
        interpolation: img.Interpolation.cubic);
  }

  _compositeMasked(image, work, mask, roi);
  return image;
}

// ---------------------------------------------------------------------------
// 마스크
// ---------------------------------------------------------------------------

/// 붓질들을 [width] x [height] 마스크로 그린다 (255 = 채울 곳).
Uint8List rasterizeStrokes(
  List<EraseStroke> strokes,
  int width,
  int height,
) {
  final mask = Uint8List(width * height);
  for (final stroke in strokes) {
    if (stroke.isEmpty) continue;
    final radius = stroke.radius * width;
    if (radius <= 0) continue;

    if (stroke.points.length == 1) {
      final p = stroke.points.first;
      _stampDisc(mask, width, height, p.dx * width, p.dy * height, radius);
      continue;
    }
    for (var i = 1; i < stroke.points.length; i++) {
      final a = stroke.points[i - 1];
      final b = stroke.points[i];
      _stampSegment(
        mask,
        width,
        height,
        a.dx * width,
        a.dy * height,
        b.dx * width,
        b.dy * height,
        radius,
      );
    }
  }
  return mask;
}

void _stampDisc(Uint8List mask, int w, int h, double cx, double cy, double r) {
  final x0 = math.max(0, (cx - r).floor());
  final x1 = math.min(w - 1, (cx + r).ceil());
  final y0 = math.max(0, (cy - r).floor());
  final y1 = math.min(h - 1, (cy + r).ceil());
  final r2 = r * r;
  for (var y = y0; y <= y1; y++) {
    final dy = y - cy;
    for (var x = x0; x <= x1; x++) {
      final dx = x - cx;
      if (dx * dx + dy * dy <= r2) mask[y * w + x] = 255;
    }
  }
}

/// 선분을 따라 원을 찍어 굵은 선을 만든다. 간격은 반지름의 1/3로 잡아
/// 붓이 빠르게 움직여도 끊기지 않게 한다.
void _stampSegment(Uint8List mask, int w, int h, double x0, double y0,
    double x1, double y1, double r) {
  final dx = x1 - x0;
  final dy = y1 - y0;
  final length = math.sqrt(dx * dx + dy * dy);
  final steps = math.max(1, (length / math.max(r / 3, 0.5)).ceil());
  for (var i = 0; i <= steps; i++) {
    final t = i / steps;
    _stampDisc(mask, w, h, x0 + dx * t, y0 + dy * t, r);
  }
}

class _Rect {
  _Rect(this.x, this.y, this.w, this.h);

  int x;
  int y;
  int w;
  int h;
}

_Rect? _maskBounds(Uint8List mask, int width, int height) {
  var minX = width;
  var minY = height;
  var maxX = -1;
  var maxY = -1;
  for (var y = 0; y < height; y++) {
    final row = y * width;
    for (var x = 0; x < width; x++) {
      if (mask[row + x] == 0) continue;
      if (x < minX) minX = x;
      if (x > maxX) maxX = x;
      if (y < minY) minY = y;
      if (y > maxY) maxY = y;
    }
  }
  if (maxX < 0) return null;
  return _Rect(minX, minY, maxX - minX + 1, maxY - minY + 1);
}

Uint8List _cropMask(Uint8List mask, int sourceWidth, _Rect roi) {
  final out = Uint8List(roi.w * roi.h);
  for (var y = 0; y < roi.h; y++) {
    final src = (roi.y + y) * sourceWidth + roi.x;
    out.setRange(y * roi.w, y * roi.w + roi.w, mask, src);
  }
  return out;
}

/// 최근접 이웃으로 마스크를 축소한다. 축소 후에도 채워야 할 영역이
/// 사라지지 않도록, 원본에서 조금이라도 칠해진 블록은 칠해진 것으로 본다.
Uint8List _resizeMask(
    Uint8List mask, int srcW, int srcH, int dstW, int dstH) {
  final out = Uint8List(dstW * dstH);
  for (var y = 0; y < dstH; y++) {
    final sy0 = y * srcH ~/ dstH;
    final sy1 = math.max(sy0 + 1, (y + 1) * srcH ~/ dstH);
    for (var x = 0; x < dstW; x++) {
      final sx0 = x * srcW ~/ dstW;
      final sx1 = math.max(sx0 + 1, (x + 1) * srcW ~/ dstW);
      var hit = false;
      for (var sy = sy0; sy < sy1 && !hit; sy++) {
        for (var sx = sx0; sx < sx1; sx++) {
          if (mask[sy * srcW + sx] != 0) {
            hit = true;
            break;
          }
        }
      }
      if (hit) out[y * dstW + x] = 255;
    }
  }
  return out;
}

/// 채워진 ROI를 원본에 되돌린다. 마스크 안쪽은 전부 덮어쓴다.
///
/// 경계에서 원본과 섞지 않는 것이 중요하다. 그 자리의 원본은 바로 지우려던
/// 대상이라, 섞으면 지운 자리에 그 물체의 윤곽이 반쯤 남는다. 메운 픽셀은
/// 주변 픽셀을 보고 고른 것이라 경계에서 이미 자연스럽게 이어진다.
void _compositeMasked(
    img.Image target, img.Image patch, Uint8List mask, _Rect roi) {
  for (var y = 0; y < roi.h; y++) {
    final ty = roi.y + y;
    for (var x = 0; x < roi.w; x++) {
      final tx = roi.x + x;
      if (mask[ty * target.width + tx] == 0) continue;
      final src = patch.getPixel(x, y);
      target.setPixelRgb(tx, ty, src.r, src.g, src.b);
    }
  }
}

/// 마스크를 [radius] 픽셀만큼 넓힌다.
Uint8List _dilate(Uint8List mask, int width, int height, int radius) {
  if (radius <= 0) return mask;
  final out = Uint8List(mask.length);
  final r2 = radius * radius;
  for (var y = 0; y < height; y++) {
    for (var x = 0; x < width; x++) {
      if (mask[y * width + x] == 0) continue;
      final y0 = math.max(0, y - radius);
      final y1 = math.min(height - 1, y + radius);
      final x0 = math.max(0, x - radius);
      final x1 = math.min(width - 1, x + radius);
      for (var ny = y0; ny <= y1; ny++) {
        final dy = ny - y;
        for (var nx = x0; nx <= x1; nx++) {
          final dx = nx - x;
          if (dx * dx + dy * dy <= r2) out[ny * width + nx] = 255;
        }
      }
    }
  }
  return out;
}

// ---------------------------------------------------------------------------
// 핵심 루프
// ---------------------------------------------------------------------------

void _inpaintInPlace(
  img.Image image,
  Uint8List mask,
  int width,
  int height,
  int patchRadius,
  int searchRadius,
) {
  final count = width * height;
  final r = Uint8List(count);
  final g = Uint8List(count);
  final b = Uint8List(count);
  final gray = Uint8List(count);
  final known = Uint8List(count);
  final confidence = Float32List(count);

  var i = 0;
  for (final pixel in image) {
    r[i] = pixel.r.toInt();
    g[i] = pixel.g.toInt();
    b[i] = pixel.b.toInt();
    gray[i] = (0.299 * r[i] + 0.587 * g[i] + 0.114 * b[i]).round();
    final filled = mask[i] == 0;
    known[i] = filled ? 1 : 0;
    confidence[i] = filled ? 1 : 0;
    i++;
  }

  var remaining = 0;
  for (var k = 0; k < count; k++) {
    if (known[k] == 0) remaining++;
  }
  if (remaining == 0) return;

  // 채울 픽셀 하나당 최소 한 번은 진행하므로, 그 이상 돌면 뭔가 잘못된 것.
  final maxIterations = remaining + 8;
  for (var iteration = 0; iteration < maxIterations && remaining > 0; iteration++) {
    final target = _pickTarget(
        known, confidence, gray, width, height, patchRadius);
    if (target < 0) break;

    final source = _findBestPatch(
        r, g, b, known, width, height, target, patchRadius, searchRadius);
    if (source < 0) break;

    remaining -= _copyPatch(r, g, b, gray, known, confidence, width, height,
        target, source, patchRadius);
  }

  // 패치를 못 찾아 남은 자리는 주변 평균으로 메워 구멍을 남기지 않는다.
  if (remaining > 0) {
    _fillRemaining(r, g, b, known, width, height);
  }

  i = 0;
  for (final pixel in image) {
    pixel.setRgb(r[i], g[i], b[i]);
    i++;
  }
}

/// 채울 영역의 경계에서 우선순위(신뢰도 x 구조항)가 가장 높은 지점.
int _pickTarget(
  Uint8List known,
  Float32List confidence,
  Uint8List gray,
  int width,
  int height,
  int patchRadius,
) {
  var best = -1;
  var bestPriority = -1.0;

  for (var y = 0; y < height; y++) {
    for (var x = 0; x < width; x++) {
      final index = y * width + x;
      if (known[index] != 0) continue;
      if (!_onFront(known, width, height, x, y)) continue;

      final priority = _confidenceOf(
              confidence, known, width, height, x, y, patchRadius) *
          (_dataTerm(known, gray, width, height, x, y) + 0.001);
      if (priority > bestPriority) {
        bestPriority = priority;
        best = index;
      }
    }
  }
  return best;
}

bool _onFront(Uint8List known, int width, int height, int x, int y) {
  if (x > 0 && known[y * width + x - 1] != 0) return true;
  if (x < width - 1 && known[y * width + x + 1] != 0) return true;
  if (y > 0 && known[(y - 1) * width + x] != 0) return true;
  if (y < height - 1 && known[(y + 1) * width + x] != 0) return true;
  return false;
}

double _confidenceOf(
  Float32List confidence,
  Uint8List known,
  int width,
  int height,
  int cx,
  int cy,
  int patchRadius,
) {
  var sum = 0.0;
  var total = 0;
  for (var y = cy - patchRadius; y <= cy + patchRadius; y++) {
    if (y < 0 || y >= height) continue;
    for (var x = cx - patchRadius; x <= cx + patchRadius; x++) {
      if (x < 0 || x >= width) continue;
      sum += confidence[y * width + x];
      total++;
    }
  }
  return total == 0 ? 0 : sum / total;
}

/// 경계를 가로지르는 윤곽선의 세기. 선·경계가 만나는 곳을 먼저 채워
/// 구조가 이어지게 한다.
double _dataTerm(
  Uint8List known,
  Uint8List gray,
  int width,
  int height,
  int x,
  int y,
) {
  if (x <= 0 || y <= 0 || x >= width - 1 || y >= height - 1) return 0;

  // 채울 영역 경계의 법선 = known 필드의 기울기
  final nx = (known[y * width + x + 1] - known[y * width + x - 1]).toDouble();
  final ny =
      (known[(y + 1) * width + x] - known[(y - 1) * width + x]).toDouble();
  final nLen = math.sqrt(nx * nx + ny * ny);
  if (nLen == 0) return 0;

  // 이미지 기울기는 알려진 픽셀만으로 구한다.
  final gx = _grayGradient(known, gray, width, y * width + x, 1);
  final gy = _grayGradient(known, gray, width, y * width + x, width);

  // 등광도선(isophote)은 기울기에 수직이다.
  final dot = (-gy * (nx / nLen)) + (gx * (ny / nLen));
  return dot.abs() / 255;
}

double _grayGradient(
    Uint8List known, Uint8List gray, int width, int index, int step) {
  final before = known[index - step] != 0;
  final after = known[index + step] != 0;
  if (before && after) {
    return (gray[index + step] - gray[index - step]) / 2;
  }
  if (after) return (gray[index + step] - gray[index]).toDouble();
  if (before) return (gray[index] - gray[index - step]).toDouble();
  return 0;
}

/// [target] 패치와 가장 잘 맞는 알려진 패치를 찾는다.
/// 부분 합이 이미 최선을 넘으면 즉시 중단해 탐색을 크게 줄인다.
int _findBestPatch(
  Uint8List r,
  Uint8List g,
  Uint8List b,
  Uint8List known,
  int width,
  int height,
  int target,
  int patchRadius,
  int searchRadius,
) {
  final tx = target % width;
  final ty = target ~/ width;

  final x0 = math.max(patchRadius, tx - searchRadius);
  final x1 = math.min(width - patchRadius - 1, tx + searchRadius);
  final y0 = math.max(patchRadius, ty - searchRadius);
  final y1 = math.min(height - patchRadius - 1, ty + searchRadius);

  var best = -1;
  var bestCost = double.infinity;

  for (var cy = y0; cy <= y1; cy++) {
    for (var cx = x0; cx <= x1; cx++) {
      var cost = 0.0;
      var compared = 0;
      var usable = true;

      for (var dy = -patchRadius; dy <= patchRadius && usable; dy++) {
        final sy = cy + dy;
        final tyy = ty + dy;
        if (tyy < 0 || tyy >= height) continue;
        for (var dx = -patchRadius; dx <= patchRadius; dx++) {
          final sx = cx + dx;
          final txx = tx + dx;
          if (txx < 0 || txx >= width) continue;

          final sIndex = sy * width + sx;
          // 후보 패치는 전부 알려진 픽셀이어야 한다.
          if (known[sIndex] == 0) {
            usable = false;
            break;
          }
          final tIndex = tyy * width + txx;
          if (known[tIndex] == 0) continue;

          final dr = (r[sIndex] - r[tIndex]).toDouble();
          final dg = (g[sIndex] - g[tIndex]).toDouble();
          final db = (b[sIndex] - b[tIndex]).toDouble();
          cost += dr * dr + dg * dg + db * db;
          compared++;

          if (cost >= bestCost) {
            usable = false;
            break;
          }
        }
      }

      if (usable && compared > 0 && cost < bestCost) {
        bestCost = cost;
        best = cy * width + cx;
      }
    }
  }
  return best;
}

/// [source] 패치의 픽셀을 [target] 패치의 빈 자리에 복사한다.
/// 새로 채운 픽셀 수를 반환한다.
int _copyPatch(
  Uint8List r,
  Uint8List g,
  Uint8List b,
  Uint8List gray,
  Uint8List known,
  Float32List confidence,
  int width,
  int height,
  int target,
  int source,
  int patchRadius,
) {
  final tx = target % width;
  final ty = target ~/ width;
  final sx = source % width;
  final sy = source ~/ width;
  // Criminisi의 C(p̂): 새로 채운 픽셀은 채운 패치의 신뢰도를 물려받아,
  // 나중에 채워진 곳일수록 신뢰도가 낮아진다.
  final patchConfidence =
      _confidenceOf(confidence, known, width, height, tx, ty, patchRadius);

  var filled = 0;
  for (var dy = -patchRadius; dy <= patchRadius; dy++) {
    final tyy = ty + dy;
    final syy = sy + dy;
    if (tyy < 0 || tyy >= height || syy < 0 || syy >= height) continue;
    for (var dx = -patchRadius; dx <= patchRadius; dx++) {
      final txx = tx + dx;
      final sxx = sx + dx;
      if (txx < 0 || txx >= width || sxx < 0 || sxx >= width) continue;

      final tIndex = tyy * width + txx;
      if (known[tIndex] != 0) continue;
      final sIndex = syy * width + sxx;

      r[tIndex] = r[sIndex];
      g[tIndex] = g[sIndex];
      b[tIndex] = b[sIndex];
      gray[tIndex] = gray[sIndex];
      known[tIndex] = 1;
      confidence[tIndex] = patchConfidence;
      filled++;
    }
  }
  return filled;
}

/// 후보 패치를 찾지 못해 남은 픽셀을 이웃 평균으로 반복해 메운다.
void _fillRemaining(
  Uint8List r,
  Uint8List g,
  Uint8List b,
  Uint8List known,
  int width,
  int height,
) {
  for (var pass = 0; pass < 64; pass++) {
    var changed = false;
    for (var y = 0; y < height; y++) {
      for (var x = 0; x < width; x++) {
        final index = y * width + x;
        if (known[index] != 0) continue;

        var sr = 0, sg = 0, sb = 0, n = 0;
        void take(int nx, int ny) {
          if (nx < 0 || ny < 0 || nx >= width || ny >= height) return;
          final k = ny * width + nx;
          if (known[k] == 0) return;
          sr += r[k];
          sg += g[k];
          sb += b[k];
          n++;
        }

        take(x - 1, y);
        take(x + 1, y);
        take(x, y - 1);
        take(x, y + 1);
        if (n == 0) continue;

        r[index] = sr ~/ n;
        g[index] = sg ~/ n;
        b[index] = sb ~/ n;
        known[index] = 1;
        changed = true;
      }
    }
    if (!changed) return;
  }
}
