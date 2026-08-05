import 'package:flutter/material.dart';

import '../../core/monetization/entitlement_service.dart';

enum _Plan {
  monthly('월간', '₩4,900', '/월', 'photo_premium_monthly'),
  yearly('연간', '₩29,000', '/년 (50% 할인)', 'photo_premium_yearly');

  const _Plan(this.label, this.price, this.suffix, this.productId);

  final String label;
  final String price;
  final String suffix;
  final String productId;
}

/// 프리미엄 구독 페이월.
///
/// 결제 백엔드가 [EntitlementService] 뒤의 [BillingService] 인터페이스로
/// 추상화되어 있어, 지금은 로컬 테스트 모드로 동작하고 스토어 결제
/// (RevenueCat) 연동 시 이 화면은 그대로 쓴다.
class PaywallScreen extends StatefulWidget {
  const PaywallScreen({super.key});

  @override
  State<PaywallScreen> createState() => _PaywallScreenState();
}

class _PaywallScreenState extends State<PaywallScreen> {
  _Plan _plan = _Plan.yearly;
  bool _busy = false;

  Future<void> _purchase() async {
    setState(() => _busy = true);
    try {
      final ok = await EntitlementService.instance.purchase(_plan.productId);
      if (!mounted) return;
      if (ok) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('프리미엄이 활성화되었습니다 (테스트 모드).')),
        );
        Navigator.of(context).pop(true);
      } else {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('구매에 실패했습니다.')),
        );
      }
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Scaffold(
      appBar: AppBar(
        leading: const CloseButton(),
        title: const Text('PHOTO 프리미엄'),
      ),
      body: ListenableBuilder(
        listenable: EntitlementService.instance,
        builder: (context, _) {
          final premium = EntitlementService.instance.isPremium;
          return SafeArea(
            child: ListView(
              padding: const EdgeInsets.fromLTRB(24, 8, 24, 24),
              children: [
                Icon(Icons.auto_awesome, size: 48, color: scheme.primary),
                const SizedBox(height: 16),
                if (premium) ...[
                  const Text(
                    '프리미엄 이용 중',
                    textAlign: TextAlign.center,
                    style:
                        TextStyle(fontSize: 20, fontWeight: FontWeight.w700),
                  ),
                  const SizedBox(height: 8),
                  Text(
                    '모든 기능이 열려 있습니다.',
                    textAlign: TextAlign.center,
                    style: TextStyle(color: scheme.onSurfaceVariant),
                  ),
                  const SizedBox(height: 24),
                  OutlinedButton(
                    onPressed: () =>
                        EntitlementService.instance.deactivateSimulated(),
                    child: const Text('테스트 구독 해제'),
                  ),
                ] else ...[
                  const Text(
                    '모든 기능을 제한 없이',
                    textAlign: TextAlign.center,
                    style:
                        TextStyle(fontSize: 20, fontWeight: FontWeight.w700),
                  ),
                  const SizedBox(height: 20),
                  const _Benefit(icon: Icons.auto_fix_high, text: '지우개 무제한'),
                  const _Benefit(
                      icon: Icons.high_quality, text: '화질 개선 무제한 + 4배'),
                  const _Benefit(
                      icon: Icons.auto_awesome, text: '프리미엄 필터 전체 해금'),
                  const _Benefit(
                      icon: Icons.branding_watermark_outlined,
                      text: '저장 시 워터마크 제거'),
                  const _Benefit(
                      icon: Icons.rocket_launch_outlined,
                      text: '향후 생성형 AI 기능 우선 이용'),
                  const SizedBox(height: 20),
                  for (final plan in _Plan.values) ...[
                    _PlanCard(
                      plan: plan,
                      selected: _plan == plan,
                      onTap: () => setState(() => _plan = plan),
                    ),
                    const SizedBox(height: 10),
                  ],
                  const SizedBox(height: 8),
                  FilledButton(
                    onPressed: _busy ? null : _purchase,
                    style: FilledButton.styleFrom(
                      padding: const EdgeInsets.symmetric(vertical: 16),
                    ),
                    child: _busy
                        ? const SizedBox(
                            width: 18,
                            height: 18,
                            child: CircularProgressIndicator(strokeWidth: 2),
                          )
                        : const Text('구독 시작하기'),
                  ),
                  const SizedBox(height: 10),
                  Text(
                    '아직 실제 결제가 연동되지 않았습니다.\n'
                    '지금은 테스트 모드로 활성화되며, 스토어 출시 시 '
                    '인앱결제(RevenueCat)로 교체됩니다.',
                    textAlign: TextAlign.center,
                    style: TextStyle(
                      fontSize: 11,
                      color: scheme.onSurfaceVariant,
                    ),
                  ),
                  TextButton(
                    onPressed: () => EntitlementService.instance.restore(),
                    child: const Text('구매 복원'),
                  ),
                ],
              ],
            ),
          );
        },
      ),
    );
  }
}

class _Benefit extends StatelessWidget {
  const _Benefit({required this.icon, required this.text});

  final IconData icon;
  final String text;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 6),
      child: Row(
        children: [
          Icon(icon, size: 20, color: Theme.of(context).colorScheme.primary),
          const SizedBox(width: 12),
          Expanded(child: Text(text, style: const TextStyle(fontSize: 14))),
        ],
      ),
    );
  }
}

class _PlanCard extends StatelessWidget {
  const _PlanCard({
    required this.plan,
    required this.selected,
    required this.onTap,
  });

  final _Plan plan;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(14),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(14),
          border: Border.all(
            width: 2,
            color: selected ? scheme.primary : scheme.outlineVariant,
          ),
        ),
        child: Row(
          children: [
            Icon(
              selected
                  ? Icons.radio_button_checked
                  : Icons.radio_button_off,
              size: 20,
              color: selected ? scheme.primary : scheme.onSurfaceVariant,
            ),
            const SizedBox(width: 12),
            Text(plan.label,
                style: const TextStyle(fontWeight: FontWeight.w600)),
            const Spacer(),
            Text(plan.price,
                style: const TextStyle(fontWeight: FontWeight.w700)),
            const SizedBox(width: 4),
            Text(
              plan.suffix,
              style: TextStyle(
                fontSize: 12,
                color: scheme.onSurfaceVariant,
              ),
            ),
          ],
        ),
      ),
    );
  }
}
