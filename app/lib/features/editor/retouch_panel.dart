import 'package:flutter/material.dart';

import '../../core/face/retouch_settings.dart';

enum _RetouchKind {
  skinSmooth('피부결', Icons.blur_on, min: 0),
  skinTone('피부톤', Icons.wb_sunny_outlined, min: -1),
  eyeEnlarge('눈 크기', Icons.remove_red_eye_outlined, min: 0),
  faceSlim('얼굴 슬림', Icons.face_retouching_natural, min: 0),
  noseSlim('코', Icons.change_history, min: 0),
  chinShape('턱', Icons.expand_more, min: -1),
  lipFullness('입술', Icons.favorite_outline, min: -1);

  const _RetouchKind(this.label, this.icon, {required this.min});

  final String label;
  final IconData icon;
  final double min;

  double valueOf(FaceRetouchSettings s) => switch (this) {
        skinSmooth => s.skinSmooth,
        skinTone => s.skinTone,
        eyeEnlarge => s.eyeEnlarge,
        faceSlim => s.faceSlim,
        noseSlim => s.noseSlim,
        chinShape => s.chinShape,
        lipFullness => s.lipFullness,
      };

  FaceRetouchSettings applyTo(FaceRetouchSettings s, double v) =>
      switch (this) {
        skinSmooth => s.copyWith(skinSmooth: v),
        skinTone => s.copyWith(skinTone: v),
        eyeEnlarge => s.copyWith(eyeEnlarge: v),
        faceSlim => s.copyWith(faceSlim: v),
        noseSlim => s.copyWith(noseSlim: v),
        chinShape => s.copyWith(chinShape: v),
        lipFullness => s.copyWith(lipFullness: v),
      };

  /// 랜드마크 워핑이 필요한 항목인지 (얼굴 미검출 시 비활성화).
  bool get needsFace => this != skinSmooth && this != skinTone;
}

/// 얼굴 보정 패널.
///
/// [onChanged]는 드래그 중 실시간으로, [onCommitted]는 드래그가 끝나
/// 히스토리에 기록할 시점에 호출된다.
class RetouchPanel extends StatefulWidget {
  const RetouchPanel({
    super.key,
    required this.settings,
    required this.faceCount,
    required this.detecting,
    required this.onChanged,
    required this.onCommitted,
  });

  final FaceRetouchSettings settings;
  final int faceCount;
  final bool detecting;
  final ValueChanged<FaceRetouchSettings> onChanged;
  final ValueChanged<FaceRetouchSettings> onCommitted;

  @override
  State<RetouchPanel> createState() => _RetouchPanelState();
}

class _RetouchPanelState extends State<RetouchPanel> {
  _RetouchKind _kind = _RetouchKind.skinSmooth;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final hasFace = widget.faceCount > 0;
    final enabled = !_kind.needsFace || hasFace;
    final value = _kind.valueOf(widget.settings);

    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        SizedBox(
          height: 28,
          child: Center(child: _buildStatus(context, hasFace)),
        ),
        Row(
          children: [
            const SizedBox(width: 4),
            Expanded(
              child: Slider(
                value: value.clamp(_kind.min, 1.0),
                min: _kind.min,
                max: 1,
                onChanged: enabled
                    ? (v) =>
                        widget.onChanged(_kind.applyTo(widget.settings, v))
                    : null,
                onChangeEnd: (v) =>
                    widget.onCommitted(_kind.applyTo(widget.settings, v)),
              ),
            ),
            SizedBox(
              width: 44,
              child: Text(
                (value * 100).round().toString(),
                textAlign: TextAlign.center,
                style: const TextStyle(fontSize: 12),
              ),
            ),
            IconButton(
              tooltip: '얼굴 보정 초기화',
              iconSize: 20,
              onPressed: widget.settings.isNeutral
                  ? null
                  : () => widget.onCommitted(FaceRetouchSettings.neutral),
              icon: const Icon(Icons.restart_alt),
            ),
          ],
        ),
        SizedBox(
          height: 60,
          child: ListView.separated(
            scrollDirection: Axis.horizontal,
            padding: const EdgeInsets.symmetric(horizontal: 12),
            itemCount: _RetouchKind.values.length,
            separatorBuilder: (_, _) => const SizedBox(width: 4),
            itemBuilder: (context, index) {
              final kind = _RetouchKind.values[index];
              final selected = kind == _kind;
              final usable = !kind.needsFace || hasFace;
              final active = kind.valueOf(widget.settings) != 0;
              final color = !usable
                  ? Theme.of(context).disabledColor
                  : selected
                      ? scheme.primary
                      : (active ? scheme.onSurface : scheme.onSurfaceVariant);
              return InkWell(
                onTap: () => setState(() => _kind = kind),
                borderRadius: BorderRadius.circular(10),
                child: Padding(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Icon(kind.icon, size: 21, color: color),
                      const SizedBox(height: 4),
                      Text(kind.label,
                          style: TextStyle(fontSize: 11, color: color)),
                    ],
                  ),
                ),
              );
            },
          ),
        ),
      ],
    );
  }

  Widget _buildStatus(BuildContext context, bool hasFace) {
    if (widget.detecting) {
      return const Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          SizedBox(
            width: 12,
            height: 12,
            child: CircularProgressIndicator(strokeWidth: 2),
          ),
          SizedBox(width: 8),
          Text('얼굴을 찾는 중…', style: TextStyle(fontSize: 12)),
        ],
      );
    }
    if (!hasFace) {
      return Text(
        '얼굴을 찾지 못했어요 · 피부 보정만 사용할 수 있어요',
        style: TextStyle(
          fontSize: 12,
          color: Theme.of(context).colorScheme.onSurfaceVariant,
        ),
      );
    }
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Text(
          '얼굴 ${widget.faceCount}개 인식',
          style: TextStyle(
            fontSize: 12,
            color: Theme.of(context).colorScheme.onSurfaceVariant,
          ),
        ),
        const SizedBox(width: 12),
        _PresetChip(
          label: '자연스럽게',
          onTap: () => widget.onCommitted(FaceRetouchSettings.natural),
        ),
        const SizedBox(width: 6),
        _PresetChip(
          label: '또렷하게',
          onTap: () => widget.onCommitted(FaceRetouchSettings.defined),
        ),
      ],
    );
  }
}

class _PresetChip extends StatelessWidget {
  const _PresetChip({required this.label, required this.onTap});

  final String label;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(20),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(20),
          border: Border.all(color: scheme.primary.withValues(alpha: 0.6)),
        ),
        child: Text(
          label,
          style: TextStyle(fontSize: 11, color: scheme.primary),
        ),
      ),
    );
  }
}
