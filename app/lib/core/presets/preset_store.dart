import 'dart:convert';

import 'package:shared_preferences/shared_preferences.dart';

import 'user_preset.dart';

/// 사용자 프리셋 저장소. shared_preferences에 JSON 배열로 보관한다
/// (모바일·웹 공통).
class PresetStore {
  PresetStore._();

  static final PresetStore instance = PresetStore._();

  static const String _storageKey = 'user_presets_v1';
  static const int maxPresets = 30;

  Future<List<UserPreset>> load() async {
    final prefs = await SharedPreferences.getInstance();
    final raw = prefs.getString(_storageKey);
    if (raw == null || raw.isEmpty) return const [];
    try {
      final list = jsonDecode(raw) as List<dynamic>;
      return [
        for (final item in list)
          UserPreset.fromJson(item as Map<String, dynamic>),
      ];
    } catch (_) {
      // 손상된 저장값은 버린다 — 프리셋 때문에 앱이 죽어서는 안 된다.
      return const [];
    }
  }

  Future<void> _saveAll(List<UserPreset> presets) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(
      _storageKey,
      jsonEncode([for (final p in presets) p.toJson()]),
    );
  }

  /// 프리셋을 추가하고 갱신된 전체 목록을 돌려준다.
  /// 같은 이름이 있으면 덮어쓴다. 최대 개수를 넘으면 가장 오래된 것을 밀어낸다.
  Future<List<UserPreset>> add(UserPreset preset) async {
    final presets = [...await load()]
      ..removeWhere((p) => p.name == preset.name)
      ..add(preset);
    while (presets.length > maxPresets) {
      presets.removeAt(0);
    }
    await _saveAll(presets);
    return presets;
  }

  /// id로 삭제하고 갱신된 전체 목록을 돌려준다.
  Future<List<UserPreset>> remove(String id) async {
    final presets = [...await load()]..removeWhere((p) => p.id == id);
    await _saveAll(presets);
    return presets;
  }
}
