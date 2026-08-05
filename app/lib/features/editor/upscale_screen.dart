import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';

import '../../core/monetization/entitlement_service.dart';
import '../../core/upscale/upscaler.dart';
import '../paywall/paywall_screen.dart';

/// 화질 개선 화면. 중앙 부분을 잘라 확대 전/후를 비교해 보여주고,
/// 배율과 선명도를 고르면 설정을 돌려준다. 실제 적용은 저장할 때
/// 원본 해상도에서 이루어진다.
class UpscaleScreen extends StatefulWidget {
  const UpscaleScreen({
    super.key,
    required this.imageBytes,
    required this.initialSettings,
  });

  /// 기하 연산 + 지우개까지 적용된 프리뷰 바이트.
  final Uint8List imageBytes;
  final UpscaleSettings initialSettings;

  @override
  State<UpscaleScreen> createState() => _UpscaleScreenState();
}

class _UpscaleScreenState extends State<UpscaleScreen> {
  late UpscaleSettings _settings = widget.initialSettings.factor < 2
      ? widget.initialSettings.copyWith(factor: 2)
      : widget.initialSettings;

  UpscalePatchResult? _patch;
  bool _building = false;
  bool _showOriginal = false;
  int _generation = 0;

  @override
  void initState() {
    super.initState();
    _rebuildPatch();
  }

  Future<void> _rebuildPatch() async {
    final generation = ++_generation;
    setState(() => _building = true);
    try {
      final result = await compute(
        buildUpscalePatch,
        UpscalePatchRequest(
          sourceBytes: widget.imageBytes,
          settings: _settings,
        ),
      );
      if (!mounted || generation != _generation) return;
      setState(() => _patch = result);
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('미리보기를 만들 수 없습니다: $e')),
      );
    } finally {
      if (mounted && generation == _generation) {
        setState(() => _building = false);
      }
    }
  }

  void _update(UpscaleSettings next) {
    if (next == _settings) return;
    setState(() => _settings = next);
    _rebuildPatch();
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final patch = _patch;
    final clamped =
        patch != null && patch.appliedScale < _settings.factor - 1e-9;

    return Scaffold(
      backgroundColor: Colors.black,
      appBar: AppBar(
        backgroundColor: Colors.black,
        title: const Text('화질 개선'),
        actions: [
          TextButton(
            onPressed: () =>
                Navigator.of(context).pop(UpscaleSettings.off),
            child: const Text('끄기'),
          ),
          TextButton(
            onPressed: _building
                ? null
                : () => Navigator.of(context).pop(_settings),
            child: const Text('적용'),
          ),
        ],
      ),
      body: Column(
        children: [
          Expanded(
            child: patch == null
                ? const Center(child: CircularProgressIndicator())
                : GestureDetector(
                    onLongPressStart: (_) =>
                        setState(() => _showOriginal = true),
                    onLongPressEnd: (_) =>
                        setState(() => _showOriginal = false),
                    child: Stack(
                      alignment: Alignment.center,
                      children: [
                        Padding(
                          padding: const EdgeInsets.all(24),
                          // 원본 패치는 픽셀이 그대로 보이도록 확대해
                          // "개선 전" 상태를 정직하게 보여준다.
                          child: Image.memory(
                            _showOriginal
                                ? patch.originalPatch
                                : patch.upscaledPatch,
                            fit: BoxFit.contain,
                            filterQuality: _showOriginal
                                ? FilterQuality.none
                                : FilterQuality.medium,
                            gaplessPlayback: true,
                          ),
                        ),
                        if (_building)
                          const Align(
                            alignment: Alignment.topCenter,
                            child: LinearProgressIndicator(minHeight: 2),
                          ),
                        Positioned(
                          top: 12,
                          child: Container(
                            padding: const EdgeInsets.symmetric(
                                horizontal: 12, vertical: 6),
                            decoration: BoxDecoration(
                              color: Colors.black54,
                              borderRadius: BorderRadius.circular(20),
                            ),
                            child: Text(
                              _showOriginal
                                  ? '개선 전'
                                  : '개선 후 · 길게 누르면 원본',
                              style: const TextStyle(fontSize: 12),
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
          ),
          SafeArea(
            top: false,
            child: Padding(
              padding: const EdgeInsets.fromLTRB(16, 4, 16, 12),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  if (clamped)
                    Padding(
                      padding: const EdgeInsets.only(bottom: 6),
                      child: Text(
                        '사진이 이미 커서 저장 시 약 '
                        '${patch.appliedScale.toStringAsFixed(1)}배로 적용됩니다',
                        style: TextStyle(
                          fontSize: 12,
                          color: scheme.onSurfaceVariant,
                        ),
                      ),
                    ),
                  // 4배는 프리미엄 전용. 구독하면 그 자리에서 바로 풀린다.
                  ListenableBuilder(
                    listenable: EntitlementService.instance,
                    builder: (context, _) {
                      final premium =
                          EntitlementService.instance.isPremium;
                      return Row(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          for (final factor in const [2, 4]) ...[
                            ChoiceChip(
                              avatar: factor == 4 && !premium
                                  ? const Icon(Icons.lock, size: 14)
                                  : null,
                              label: Text('$factor배'),
                              selected: _settings.factor == factor,
                              onSelected: (_) {
                                if (factor == 4 && !premium) {
                                  Navigator.of(context).push(
                                    MaterialPageRoute<void>(
                                      builder: (_) =>
                                          const PaywallScreen(),
                                    ),
                                  );
                                  return;
                                }
                                _update(
                                    _settings.copyWith(factor: factor));
                              },
                            ),
                            const SizedBox(width: 8),
                          ],
                        ],
                      );
                    },
                  ),
                  Row(
                    children: [
                      const Text('선명도', style: TextStyle(fontSize: 12)),
                      Expanded(
                        child: Slider(
                          value: _settings.sharpen.clamp(0.0, 1.0),
                          onChanged: (v) => setState(() =>
                              _settings = _settings.copyWith(sharpen: v)),
                          onChangeEnd: (_) => _rebuildPatch(),
                        ),
                      ),
                      SizedBox(
                        width: 36,
                        child: Text(
                          (_settings.sharpen * 100).round().toString(),
                          textAlign: TextAlign.center,
                          style: const TextStyle(fontSize: 12),
                        ),
                      ),
                    ],
                  ),
                  Text(
                    '저장할 때 원본 해상도에 적용됩니다. 시간이 조금 걸려요.',
                    style: TextStyle(
                      fontSize: 11,
                      color: scheme.onSurfaceVariant,
                    ),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}
