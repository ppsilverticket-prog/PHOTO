import 'package:flutter_test/flutter_test.dart';
import 'package:image/image.dart' as img;
import 'package:photo_app/core/color_adjustments.dart';
import 'package:photo_app/core/filter_presets.dart';

img.Image solid(int r, int g, int b, {int size = 4}) {
  final image = img.Image(width: size, height: size);
  for (final pixel in image) {
    pixel.setRgb(r, g, b);
  }
  return image;
}

void main() {
  group('applyAdjustmentsCpu', () {
    test('neutral adjustments leave pixels unchanged', () {
      final image = applyAdjustmentsCpu(solid(120, 80, 200));
      final pixel = image.getPixel(0, 0);
      expect(pixel.r, 120);
      expect(pixel.g, 80);
      expect(pixel.b, 200);
    });

    test('positive brightness raises all channels', () {
      final image = applyAdjustmentsCpu(
        solid(100, 100, 100),
        adjustments: const ColorAdjustments(brightness: 0.5),
      );
      final pixel = image.getPixel(0, 0);
      expect(pixel.r, greaterThan(100));
      expect(pixel.g, greaterThan(100));
      expect(pixel.b, greaterThan(100));
    });

    test('saturation -1 produces gray', () {
      final image = applyAdjustmentsCpu(
        solid(200, 50, 50),
        adjustments: const ColorAdjustments(saturation: -1),
      );
      final pixel = image.getPixel(0, 0);
      expect(pixel.r, pixel.g);
      expect(pixel.g, pixel.b);
    });

    test('warm temperature boosts red and cuts blue', () {
      final image = applyAdjustmentsCpu(
        solid(128, 128, 128),
        adjustments: const ColorAdjustments(temperature: 0.8),
      );
      final pixel = image.getPixel(0, 0);
      expect(pixel.r, greaterThan(pixel.b));
    });

    test('sepia preset shifts warm and desaturates', () {
      final preset = filterPresetById('sepia')!;
      final image = applyAdjustmentsCpu(solid(128, 128, 128), preset: preset);
      final pixel = image.getPixel(0, 0);
      expect(pixel.r, greaterThan(pixel.b));
    });

    test('strength 0 disables the filter entirely', () {
      final preset = filterPresetById('sepia')!;
      final image = applyAdjustmentsCpu(
        solid(128, 128, 128),
        preset: preset,
        strength: 0,
      );
      final pixel = image.getPixel(0, 0);
      expect(pixel.r, 128);
      expect(pixel.g, 128);
      expect(pixel.b, 128);
    });

    test('mono preset yields grayscale regardless of input color', () {
      final preset = filterPresetById('mono')!;
      final image = applyAdjustmentsCpu(solid(220, 40, 90), preset: preset);
      final pixel = image.getPixel(0, 0);
      expect(pixel.r, pixel.g);
      expect(pixel.g, pixel.b);
    });
  });

  group('filter presets', () {
    test('every preset has valid channel parameter lengths', () {
      for (final preset in kFilterPresets) {
        expect(preset.lift.length, 3, reason: preset.id);
        expect(preset.gamma.length, 3, reason: preset.id);
        expect(preset.gain.length, 3, reason: preset.id);
      }
    });

    test('ids are unique', () {
      final ids = kFilterPresets.map((p) => p.id).toSet();
      expect(ids.length, kFilterPresets.length);
    });

    test('filterPresetById resolves and rejects unknown ids', () {
      expect(filterPresetById('mono'), isNotNull);
      expect(filterPresetById('nope'), isNull);
      expect(filterPresetById(null), isNull);
    });
  });
}
