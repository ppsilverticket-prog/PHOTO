import 'package:flutter/material.dart';

import '../../core/color_adjustments.dart';

enum _AdjustKind {
  brightness('밝기', Icons.brightness_6_outlined),
  contrast('대비', Icons.contrast),
  saturation('채도', Icons.water_drop_outlined),
  temperature('온도', Icons.thermostat),
  tint('색조', Icons.colorize_outlined),
  highlights('하이라이트', Icons.flare),
  shadows('그림자', Icons.tonality);

  const _AdjustKind(this.label, this.icon);

  final String label;
  final IconData icon;

  double valueOf(ColorAdjustments a) => switch (this) {
        brightness => a.brightness,
        contrast => a.contrast,
        saturation => a.saturation,
        temperature => a.temperature,
        tint => a.tint,
        highlights => a.highlights,
        shadows => a.shadows,
      };

  ColorAdjustments applyTo(ColorAdjustments a, double v) => switch (this) {
        brightness => a.copyWith(brightness: v),
        contrast => a.copyWith(contrast: v),
        saturation => a.copyWith(saturation: v),
        temperature => a.copyWith(temperature: v),
        tint => a.copyWith(tint: v),
        highlights => a.copyWith(highlights: v),
        shadows => a.copyWith(shadows: v),
      };
}

/// 색보정 패널: 항목 선택 칩 + 슬라이더.
///
/// [onChanged]는 드래그 중 실시간으로, [onCommitted]는 드래그가 끝났을 때
/// (undo 히스토리에 기록할 시점에) 호출된다.
class AdjustPanel extends StatefulWidget {
  const AdjustPanel({
    super.key,
    required this.adjustments,
    required this.onChanged,
    required this.onCommitted,
    required this.onReset,
  });

  final ColorAdjustments adjustments;
  final ValueChanged<ColorAdjustments> onChanged;
  final ValueChanged<ColorAdjustments> onCommitted;
  final VoidCallback onReset;

  @override
  State<AdjustPanel> createState() => _AdjustPanelState();
}

class _AdjustPanelState extends State<AdjustPanel> {
  _AdjustKind _kind = _AdjustKind.brightness;

  @override
  Widget build(BuildContext context) {
    final value = _kind.valueOf(widget.adjustments);
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        Row(
          children: [
            const SizedBox(width: 4),
            Expanded(
              child: Slider(
                value: value.clamp(-1.0, 1.0),
                min: -1,
                max: 1,
                onChanged: (v) =>
                    widget.onChanged(_kind.applyTo(widget.adjustments, v)),
                onChangeEnd: (v) =>
                    widget.onCommitted(_kind.applyTo(widget.adjustments, v)),
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
              tooltip: '보정 초기화',
              iconSize: 20,
              onPressed:
                  widget.adjustments.isNeutral ? null : widget.onReset,
              icon: const Icon(Icons.restart_alt),
            ),
          ],
        ),
        SizedBox(
          height: 64,
          child: ListView.separated(
            scrollDirection: Axis.horizontal,
            padding: const EdgeInsets.symmetric(horizontal: 12),
            itemCount: _AdjustKind.values.length,
            separatorBuilder: (_, _) => const SizedBox(width: 4),
            itemBuilder: (context, index) {
              final kind = _AdjustKind.values[index];
              final selected = kind == _kind;
              final active = kind.valueOf(widget.adjustments) != 0;
              final scheme = Theme.of(context).colorScheme;
              final color = selected
                  ? scheme.primary
                  : (active ? scheme.onSurface : scheme.onSurfaceVariant);
              return InkWell(
                onTap: () => setState(() => _kind = kind),
                borderRadius: BorderRadius.circular(10),
                child: Padding(
                  padding: const EdgeInsets.symmetric(
                      horizontal: 10, vertical: 6),
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Icon(kind.icon, size: 22, color: color),
                      const SizedBox(height: 4),
                      Text(
                        kind.label,
                        style: TextStyle(fontSize: 11, color: color),
                      ),
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
}
