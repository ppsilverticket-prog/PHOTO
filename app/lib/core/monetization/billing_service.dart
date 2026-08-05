import 'package:shared_preferences/shared_preferences.dart';

/// 결제 백엔드 인터페이스.
///
/// 실제 인앱결제(RevenueCat)는 애플/구글 개발자 계정과 스토어 상품 등록이
/// 있어야 연동할 수 있다. 그때까지는 [LocalBillingService]가 자리를 지키며,
/// 과금 게이트 전체(횟수 제한·워터마크·페이월 흐름)를 미리 검증할 수 있게
/// 한다. 연동 시점에 RevenueCatBillingService 구현체로 교체하면 된다.
abstract class BillingService {
  /// 저장된 구독 상태를 불러온다.
  Future<bool> loadPremium();

  /// [productId] 구매를 시도한다. 성공 여부를 돌려준다.
  Future<bool> purchase(String productId);

  /// 구매 복원. 복원 후의 구독 상태를 돌려준다.
  Future<bool> restore();
}

/// 로컬 시뮬레이션 결제. **실제 과금은 일어나지 않으며**, 페이월 UI에도
/// 테스트 모드임이 명시된다.
class LocalBillingService implements BillingService {
  static const String _key = 'premium_simulated_v1';

  @override
  Future<bool> loadPremium() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getBool(_key) ?? false;
  }

  @override
  Future<bool> purchase(String productId) async {
    // 스토어 결제창이 뜨는 시간을 흉내 낸다.
    await Future<void>.delayed(const Duration(milliseconds: 400));
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(_key, true);
    return true;
  }

  @override
  Future<bool> restore() => loadPremium();

  /// 테스트 편의를 위한 구독 해제 (실서비스에는 없는 동작).
  Future<void> deactivate() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(_key, false);
  }
}
