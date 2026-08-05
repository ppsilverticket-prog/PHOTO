import 'package:flutter_test/flutter_test.dart';
import 'package:image/image.dart' as img;
import 'package:photo_app/core/filter_presets.dart';
import 'package:photo_app/core/monetization/billing_service.dart';
import 'package:photo_app/core/monetization/entitlement_service.dart';
import 'package:photo_app/core/monetization/usage_meter.dart';
import 'package:photo_app/core/watermark.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() {
    SharedPreferences.setMockInitialValues({});
  });

  group('UsageMeter', () {
    test('counts per feature independently', () async {
      final meter = UsageMeter();
      await meter.increment('eraser');
      await meter.increment('eraser');
      await meter.increment('upscale');

      expect(await meter.usedToday('eraser'), 2);
      expect(await meter.usedToday('upscale'), 1);
    });

    test('resets when the date rolls over', () async {
      var today = DateTime(2026, 8, 5);
      final meter = UsageMeter(now: () => today);
      await meter.increment('eraser');
      await meter.increment('eraser');
      expect(await meter.usedToday('eraser'), 2);

      today = DateTime(2026, 8, 6);
      expect(await meter.usedToday('eraser'), 0,
          reason: '날짜가 바뀌면 0부터 다시 세야 한다');
      expect(await meter.increment('eraser'), 1);
    });
  });

  group('EntitlementService', () {
    test('free tier allows dailyFreeLimit uses then blocks', () async {
      final service = EntitlementService(billing: LocalBillingService());
      await service.init();

      for (var i = 0; i < EntitlementService.dailyFreeLimit; i++) {
        expect(await service.consume(PaidFeature.eraser), isTrue,
            reason: '${i + 1}번째 사용은 허용돼야 한다');
      }
      expect(await service.consume(PaidFeature.eraser), isFalse);
      expect(await service.remainingToday(PaidFeature.eraser), 0);
    });

    test('features have independent quotas', () async {
      final service = EntitlementService(billing: LocalBillingService());
      await service.init();

      for (var i = 0; i < EntitlementService.dailyFreeLimit; i++) {
        await service.consume(PaidFeature.eraser);
      }
      expect(await service.remainingToday(PaidFeature.upscale),
          EntitlementService.dailyFreeLimit);
    });

    test('purchase unlocks unlimited use and clears watermark', () async {
      final service = EntitlementService(billing: LocalBillingService());
      await service.init();
      expect(service.needsWatermark, isTrue);

      expect(await service.purchase('photo_premium_monthly'), isTrue);
      expect(service.isPremium, isTrue);
      expect(service.needsWatermark, isFalse);

      for (var i = 0; i < 20; i++) {
        expect(await service.consume(PaidFeature.eraser), isTrue);
      }
    });

    test('premium state persists across service instances', () async {
      final first = EntitlementService(billing: LocalBillingService());
      await first.init();
      await first.purchase('photo_premium_yearly');

      final second = EntitlementService(billing: LocalBillingService());
      await second.init();
      expect(second.isPremium, isTrue);
    });

    test('filter lock follows premium state', () async {
      final service = EntitlementService(billing: LocalBillingService());
      await service.init();

      expect(service.isFilterLocked('noir'), isTrue);
      expect(service.isFilterLocked('film'), isFalse);
      expect(service.isFilterLocked(null), isFalse);

      await service.purchase('photo_premium_monthly');
      expect(service.isFilterLocked('noir'), isFalse);
    });

    test('every premium filter id exists in the filter list', () {
      final ids = kFilterPresets.map((p) => p.id).toSet();
      for (final id in EntitlementService.premiumFilterIds) {
        expect(ids, contains(id));
      }
      // 무료 필터도 남아 있어야 한다.
      expect(ids.difference(EntitlementService.premiumFilterIds),
          isNotEmpty);
    });
  });

  group('applyWatermark', () {
    img.Image solid(int size) {
      final image = img.Image(width: size, height: size);
      for (final p in image) {
        p.setRgb(30, 30, 30);
      }
      return image;
    }

    test('marks the bottom-right corner and leaves the rest alone', () {
      final image = applyWatermark(solid(400));

      var cornerChanged = 0;
      for (var y = 340; y < 395; y++) {
        for (var x = 300; x < 395; x++) {
          if (image.getPixel(x, y).r != 30) cornerChanged++;
        }
      }
      expect(cornerChanged, greaterThan(50),
          reason: '우하단에 워터마크가 찍혀야 한다');

      // 좌상단은 그대로.
      for (var y = 0; y < 100; y++) {
        for (var x = 0; x < 100; x++) {
          expect(image.getPixel(x, y).r, 30);
        }
      }
    });

    test('scales with image width', () {
      final small = applyWatermark(solid(200));
      final large = applyWatermark(solid(1000));

      int changedWidth(img.Image image) {
        var minX = image.width;
        for (var y = 0; y < image.height; y++) {
          for (var x = 0; x < image.width; x++) {
            if (image.getPixel(x, y).r != 30 && x < minX) minX = x;
          }
        }
        return image.width - minX;
      }

      final smallMark = changedWidth(small);
      final largeMark = changedWidth(large);
      expect(largeMark, greaterThan(smallMark));
      // 대략 폭의 16% + 여백 수준이어야 한다 (과하게 크지 않게).
      expect(largeMark, lessThan(1000 * 0.3));
    });

    test('tiny images do not crash', () {
      expect(() => applyWatermark(solid(24)), returnsNormally);
    });
  });
}
