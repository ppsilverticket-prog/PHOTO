import 'package:shared_preferences/shared_preferences.dart';

/// 기능별 일일 사용 횟수. shared_preferences에 `날짜:횟수`로 저장하고,
/// 날짜가 바뀌면 자동으로 0부터 다시 센다.
class UsageMeter {
  UsageMeter({DateTime Function()? now}) : _now = now ?? DateTime.now;

  final DateTime Function() _now;

  String _todayKey() {
    final t = _now();
    return '${t.year}-${t.month.toString().padLeft(2, '0')}'
        '-${t.day.toString().padLeft(2, '0')}';
  }

  String _prefsKey(String feature) => 'usage_$feature';

  Future<int> usedToday(String feature) async {
    final prefs = await SharedPreferences.getInstance();
    final raw = prefs.getString(_prefsKey(feature));
    if (raw == null) return 0;
    final parts = raw.split(':');
    if (parts.length != 2 || parts[0] != _todayKey()) return 0;
    return int.tryParse(parts[1]) ?? 0;
  }

  /// 오늘 사용 횟수를 1 올리고 새 값을 돌려준다.
  Future<int> increment(String feature) async {
    final prefs = await SharedPreferences.getInstance();
    final next = await usedToday(feature) + 1;
    await prefs.setString(_prefsKey(feature), '${_todayKey()}:$next');
    return next;
  }
}
