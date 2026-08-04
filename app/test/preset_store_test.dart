import 'package:flutter_test/flutter_test.dart';
import 'package:photo_app/core/color_adjustments.dart';
import 'package:photo_app/core/presets/preset_store.dart';
import 'package:photo_app/core/presets/user_preset.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() {
    SharedPreferences.setMockInitialValues({});
  });

  group('ColorAdjustments json', () {
    test('round-trips every field', () {
      const original = ColorAdjustments(
        brightness: 0.1,
        contrast: -0.2,
        saturation: 0.3,
        temperature: -0.4,
        tint: 0.5,
        highlights: -0.6,
        shadows: 0.7,
      );
      expect(ColorAdjustments.fromJson(original.toJson()), original);
    });

    test('neutral serialises to an empty map and back', () {
      expect(ColorAdjustments.neutral.toJson(), isEmpty);
      expect(
        ColorAdjustments.fromJson(const {}),
        ColorAdjustments.neutral,
      );
    });
  });

  group('UserPreset json', () {
    test('round-trips with a filter', () {
      const preset = UserPreset(
        id: '42',
        name: '노을 감성',
        adjustments: ColorAdjustments(brightness: 0.2, temperature: 0.3),
        filterId: 'sunset',
        filterStrength: 0.7,
      );
      expect(UserPreset.fromJson(preset.toJson()), preset);
    });

    test('round-trips without a filter', () {
      const preset = UserPreset(
        id: '43',
        name: '밝게만',
        adjustments: ColorAdjustments(brightness: 0.4),
      );
      final restored = UserPreset.fromJson(preset.toJson());
      expect(restored, preset);
      expect(restored.filterId, isNull);
    });
  });

  group('PresetStore', () {
    test('starts empty', () async {
      expect(await PresetStore.instance.load(), isEmpty);
    });

    test('add persists and load restores', () async {
      const preset = UserPreset(
        id: '1',
        name: '테스트',
        adjustments: ColorAdjustments(contrast: 0.2),
        filterId: 'mono',
      );
      await PresetStore.instance.add(preset);

      final loaded = await PresetStore.instance.load();
      expect(loaded.single, preset);
    });

    test('adding the same name overwrites instead of duplicating', () async {
      await PresetStore.instance.add(const UserPreset(
        id: '1',
        name: '같은이름',
        adjustments: ColorAdjustments(brightness: 0.1),
      ));
      final presets = await PresetStore.instance.add(const UserPreset(
        id: '2',
        name: '같은이름',
        adjustments: ColorAdjustments(brightness: 0.9),
      ));

      expect(presets.length, 1);
      expect(presets.single.id, '2');
      expect(presets.single.adjustments.brightness, 0.9);
    });

    test('remove deletes by id', () async {
      await PresetStore.instance.add(const UserPreset(id: 'a', name: 'A'));
      await PresetStore.instance.add(const UserPreset(id: 'b', name: 'B'));

      final presets = await PresetStore.instance.remove('a');
      expect(presets.single.id, 'b');
      expect((await PresetStore.instance.load()).single.id, 'b');
    });

    test('caps the list at maxPresets, dropping the oldest', () async {
      for (var i = 0; i < PresetStore.maxPresets + 3; i++) {
        await PresetStore.instance.add(UserPreset(id: '$i', name: '프리셋$i'));
      }
      final presets = await PresetStore.instance.load();
      expect(presets.length, PresetStore.maxPresets);
      expect(presets.first.id, '3', reason: '가장 오래된 것부터 밀려나야 한다');
    });

    test('corrupted storage is treated as empty, not a crash', () async {
      SharedPreferences.setMockInitialValues(
          {'user_presets_v1': '{broken json'});
      expect(await PresetStore.instance.load(), isEmpty);
    });
  });
}
