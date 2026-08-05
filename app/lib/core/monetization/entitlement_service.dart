import 'package:flutter/foundation.dart';

import 'billing_service.dart';
import 'usage_meter.dart';

/// 일일 무료 횟수가 걸린 기능.
enum PaidFeature {
  eraser('eraser'),
  upscale('upscale');

  const PaidFeature(this.key);

  final String key;
}

/// 무료/프리미엄 경계의 단일 진실 공급원.
///
/// 기획서의 경계를 그대로 구현한다:
/// - 지우개: 무료 일 3회, 프리미엄 무제한
/// - 화질 개선: 무료 2배 일 3회, 4배는 프리미엄 전용
/// - 필터: [premiumFilterIds]는 프리미엄 전용
/// - 저장: 무료는 워터마크 포함
class EntitlementService extends ChangeNotifier {
  EntitlementService({BillingService? billing, UsageMeter? meter})
      : _billing = billing ?? LocalBillingService(),
        _meter = meter ?? UsageMeter();

  static final EntitlementService instance = EntitlementService();

  static const int dailyFreeLimit = 3;

  /// 프리미엄 전용 필터 (kFilterPresets의 id).
  static const Set<String> premiumFilterIds = {
    'noir',
    'cinema',
    'teal_orange',
    'lavender',
    'neon',
    'fade',
  };

  final BillingService _billing;
  final UsageMeter _meter;

  bool _initialized = false;
  bool _premium = false;

  bool get isPremium => _premium;

  Future<void> init() async {
    if (_initialized) return;
    _premium = await _billing.loadPremium();
    _initialized = true;
    notifyListeners();
  }

  /// 오늘 남은 무료 횟수. 프리미엄이면 사실상 무제한.
  Future<int> remainingToday(PaidFeature feature) async {
    if (_premium) return 1 << 30;
    final used = await _meter.usedToday(feature.key);
    return (dailyFreeLimit - used).clamp(0, dailyFreeLimit);
  }

  /// 1회 사용을 기록한다. 무료 한도가 다 떨어졌으면 false.
  Future<bool> consume(PaidFeature feature) async {
    if (_premium) return true;
    if (await remainingToday(feature) <= 0) return false;
    await _meter.increment(feature.key);
    return true;
  }

  bool isFilterLocked(String? filterId) =>
      !_premium && filterId != null && premiumFilterIds.contains(filterId);

  /// 저장 시 워터마크가 필요한지.
  bool get needsWatermark => !_premium;

  Future<bool> purchase(String productId) async {
    final ok = await _billing.purchase(productId);
    if (ok) {
      _premium = true;
      notifyListeners();
    }
    return ok;
  }

  Future<void> restore() async {
    _premium = await _billing.restore();
    notifyListeners();
  }

  /// 테스트 구독 해제 (LocalBillingService 전용).
  Future<void> deactivateSimulated() async {
    final billing = _billing;
    if (billing is LocalBillingService) {
      await billing.deactivate();
      _premium = false;
      notifyListeners();
    }
  }
}
