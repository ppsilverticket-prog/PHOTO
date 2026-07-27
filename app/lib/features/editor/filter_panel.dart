import 'dart:typed_data';

import 'package:flutter/material.dart';

import '../../core/filter_presets.dart';

/// 필터 패널: 썸네일 목록 + (필터 선택 시) 강도 슬라이더.
class FilterPanel extends StatelessWidget {
  const FilterPanel({
    super.key,
    required this.thumbnails,
    required this.selectedId,
    required this.strength,
    required this.onSelect,
    required this.onStrengthChanged,
    required this.onStrengthCommitted,
  });

  /// [0] = 원본, 이후는 [kFilterPresets] 순서. null이면 로딩 중.
  final List<Uint8List>? thumbnails;
  final String? selectedId;
  final double strength;
  final ValueChanged<String?> onSelect;
  final ValueChanged<double> onStrengthChanged;
  final ValueChanged<double> onStrengthCommitted;

  @override
  Widget build(BuildContext context) {
    final thumbs = thumbnails;
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        SizedBox(
          height: 34,
          child: selectedId == null
              ? null
              : Row(
                  children: [
                    const SizedBox(width: 16),
                    const Text('강도', style: TextStyle(fontSize: 12)),
                    Expanded(
                      child: Slider(
                        value: strength.clamp(0.0, 1.0),
                        onChanged: onStrengthChanged,
                        onChangeEnd: onStrengthCommitted,
                      ),
                    ),
                    SizedBox(
                      width: 40,
                      child: Text(
                        (strength * 100).round().toString(),
                        textAlign: TextAlign.center,
                        style: const TextStyle(fontSize: 12),
                      ),
                    ),
                  ],
                ),
        ),
        SizedBox(
          height: 92,
          child: thumbs == null
              ? const Center(
                  child: SizedBox(
                    width: 20,
                    height: 20,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  ),
                )
              : ListView.separated(
                  scrollDirection: Axis.horizontal,
                  padding: const EdgeInsets.symmetric(horizontal: 12),
                  itemCount: kFilterPresets.length + 1,
                  separatorBuilder: (_, _) => const SizedBox(width: 8),
                  itemBuilder: (context, index) {
                    final id =
                        index == 0 ? null : kFilterPresets[index - 1].id;
                    final name =
                        index == 0 ? '원본' : kFilterPresets[index - 1].name;
                    final selected = id == selectedId;
                    final scheme = Theme.of(context).colorScheme;
                    return GestureDetector(
                      onTap: () => onSelect(id),
                      child: Column(
                        children: [
                          Container(
                            width: 60,
                            height: 60,
                            decoration: BoxDecoration(
                              borderRadius: BorderRadius.circular(10),
                              border: Border.all(
                                width: 2,
                                color: selected
                                    ? scheme.primary
                                    : Colors.transparent,
                              ),
                            ),
                            clipBehavior: Clip.antiAlias,
                            child: index < thumbs.length
                                ? Image.memory(
                                    thumbs[index],
                                    fit: BoxFit.cover,
                                    gaplessPlayback: true,
                                  )
                                : const ColoredBox(color: Colors.black26),
                          ),
                          const SizedBox(height: 4),
                          Text(
                            name,
                            style: TextStyle(
                              fontSize: 11,
                              color: selected
                                  ? scheme.primary
                                  : scheme.onSurfaceVariant,
                            ),
                          ),
                        ],
                      ),
                    );
                  },
                ),
        ),
      ],
    );
  }
}
