import 'dart:math' as math;

import 'package:flutter_test/flutter_test.dart';
import 'package:image/image.dart' as img;
import 'package:photo_app/core/face/skin_smooth.dart';

/// 격자 무늬 잡음이 섞인 단색 이미지. 잡음 진폭은 [noise] (0~255).
img.Image noisyPatch(int r, int g, int b, {int size = 64, int noise = 18}) {
  final image = img.Image(width: size, height: size);
  for (var y = 0; y < size; y++) {
    for (var x = 0; x < size; x++) {
      final delta = ((x + y).isEven ? noise : -noise);
      image.setPixelRgb(
        x,
        y,
        (r + delta).clamp(0, 255),
        (g + delta).clamp(0, 255),
        (b + delta).clamp(0, 255),
      );
    }
  }
  return image;
}

/// 이웃 픽셀 간 차이의 평균 — 고주파(피부결) 양의 척도.
double highFrequencyEnergy(img.Image image) {
  var total = 0.0;
  var count = 0;
  for (var y = 0; y < image.height; y++) {
    for (var x = 1; x < image.width; x++) {
      total += (image.getPixel(x, y).r - image.getPixel(x - 1, y).r).abs();
      count++;
    }
  }
  return count == 0 ? 0 : total / count;
}

double meanLuma(img.Image image) {
  var total = 0.0;
  for (final p in image) {
    total += 0.299 * p.r + 0.587 * p.g + 0.114 * p.b;
  }
  return total / (image.width * image.height);
}

void main() {
  group('applySkinRetouch', () {
    test('neutral settings leave the image untouched', () {
      final image = noisyPatch(230, 180, 150);
      final before = highFrequencyEnergy(image);
      applySkinRetouch(image, faces: const [], smooth: 0, tone: 0);
      expect(highFrequencyEnergy(image), before);
    });

    test('smoothing reduces high-frequency detail on skin tones', () {
      final image = noisyPatch(230, 180, 150);
      final before = highFrequencyEnergy(image);
      applySkinRetouch(image, faces: const [], smooth: 1, tone: 0);
      final after = highFrequencyEnergy(image);

      expect(after, lessThan(before * 0.75),
          reason: '피부 영역의 잡음이 충분히 줄어야 한다');
    });

    test('some texture survives — it must not flatten completely', () {
      final image = noisyPatch(230, 180, 150);
      applySkinRetouch(image, faces: const [], smooth: 1, tone: 0);
      expect(highFrequencyEnergy(image), greaterThan(0.5),
          reason: '주파수 분리로 피부결이 일부 남아야 자연스럽다');
    });

    test('stronger smoothing removes more detail than weaker smoothing', () {
      final light = noisyPatch(230, 180, 150);
      final heavy = noisyPatch(230, 180, 150);
      applySkinRetouch(light, faces: const [], smooth: 0.25, tone: 0);
      applySkinRetouch(heavy, faces: const [], smooth: 1, tone: 0);

      expect(highFrequencyEnergy(heavy),
          lessThan(highFrequencyEnergy(light)));
    });

    test('non-skin colours are left alone', () {
      final blue = noisyPatch(50, 80, 220);
      final before = highFrequencyEnergy(blue);
      applySkinRetouch(blue, faces: const [], smooth: 1, tone: 0.5);

      expect(highFrequencyEnergy(blue), closeTo(before, before * 0.05),
          reason: '피부색이 아니면 마스크가 0이라 변하지 않아야 한다');
    });

    test('positive tone brightens skin', () {
      final image = noisyPatch(230, 180, 150);
      final before = meanLuma(image);
      applySkinRetouch(image, faces: const [], smooth: 0, tone: 0.6);
      expect(meanLuma(image), greaterThan(before));
    });

    test('negative tone darkens skin', () {
      final image = noisyPatch(230, 180, 150);
      final before = meanLuma(image);
      applySkinRetouch(image, faces: const [], smooth: 0, tone: -0.6);
      expect(meanLuma(image), lessThan(before));
    });

    test('tiny images are returned unchanged instead of crashing', () {
      final tiny = img.Image(width: 4, height: 4);
      expect(
        () => applySkinRetouch(tiny, faces: const [], smooth: 1, tone: 0.5),
        returnsNormally,
      );
    });

    test('output stays within valid channel range', () {
      final image = noisyPatch(250, 210, 190);
      applySkinRetouch(image, faces: const [], smooth: 1, tone: 1);
      for (final p in image) {
        expect(p.r, inInclusiveRange(0, 255));
        expect(p.g, inInclusiveRange(0, 255));
        expect(p.b, inInclusiveRange(0, 255));
      }
    });

    test('handles images larger than the guided-filter working size', () {
      // 축소 경로(fast guided filter)가 도는지 확인한다.
      final large = noisyPatch(230, 180, 150, size: 600);
      final before = highFrequencyEnergy(large);
      applySkinRetouch(large, faces: const [], smooth: 1, tone: 0);
      expect(highFrequencyEnergy(large), lessThan(before));
      expect(math.min(large.width, large.height), 600);
    });
  });
}
