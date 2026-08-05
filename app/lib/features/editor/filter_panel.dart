import 'dart:typed_data';

import 'package:flutter/material.dart';

import '../../core/filter_presets.dart';
import '../../core/presets/user_preset.dart';

/// 필터 패널: 내 프리셋 행 + 썸네일 목록 + (필터 선택 시) 강도 슬라이더.
class FilterPanel extends StatelessWidget {
  const FilterPanel({
    super.key,
    required this.thumbnails,
    required this.selectedId,
    required this.strength,
    required this.onSelect,
    required this.onStrengthChanged,
    required this.onStrengthCommitted,
    required this.userPresets,
    required this.canSavePreset,
    required this.onSavePreset,
    required this.onApplyPreset,
    required this.onDeletePreset,
    this.lockedFilterIds = const {},
    required this.onLockedSelect,
  });

  /// [0] = 원본, 이후는 [kFilterPresets] 순서. null이면 로딩 중.
  final List<Uint8List>? thumbnails;
  final String? selectedId;
  final double strength;
  final ValueChanged<String?> onSelect;
  final ValueChanged<double> onStrengthChanged;
  final ValueChanged<double> onStrengthCommitted;

  /// 사용자가 저장한 프리셋. 탭하면 적용, 길게 누르면 삭제.
  final List<UserPreset> userPresets;

  /// 현재 편집에 저장할 만한 색보정/필터가 있는지.
  final bool canSavePreset;
  final VoidCallback onSavePreset;
  final ValueChanged<UserPreset> onApplyPreset;
  final ValueChanged<UserPreset> onDeletePreset;

  /// 프리미엄 전용이라 잠긴 필터 id. 잠긴 필터를 탭하면 [onLockedSelect].
  final Set<String> lockedFilterIds;
  final ValueChanged<String> onLockedSelect;

  @override
  Widget build(BuildContext context) {
    final thumbs = thumbnails;
    final scheme = Theme.of(context).colorScheme;
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        // 내 프리셋: 현재 색감을 저장하고 다른 사진에 재사용한다.
        SizedBox(
          height: 40,
          child: ListView(
            scrollDirection: Axis.horizontal,
            padding: const EdgeInsets.symmetric(horizontal: 12),
            children: [
              Center(
                child: ActionChip(
                  avatar: Icon(Icons.add, size: 16, color: scheme.primary),
                  label: const Text('프리셋 저장'),
                  labelStyle:
                      TextStyle(fontSize: 12, color: scheme.primary),
                  onPressed: canSavePreset ? onSavePreset : null,
                ),
              ),
              for (final preset in userPresets) ...[
                const SizedBox(width: 8),
                Center(
                  child: GestureDetector(
                    onLongPress: () => onDeletePreset(preset),
                    child: ActionChip(
                      label: Text(preset.name),
                      labelStyle: const TextStyle(fontSize: 12),
                      onPressed: () => onApplyPreset(preset),
                    ),
                  ),
                ),
              ],
            ],
          ),
        ),
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
                    final locked =
                        id != null && lockedFilterIds.contains(id);
                    return GestureDetector(
                      onTap: () =>
                          locked ? onLockedSelect(id) : onSelect(id),
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
                            child: Stack(
                              fit: StackFit.expand,
                              children: [
                                if (index < thumbs.length)
                                  Image.memory(
                                    thumbs[index],
                                    fit: BoxFit.cover,
                                    gaplessPlayback: true,
                                  )
                                else
                                  const ColoredBox(color: Colors.black26),
                                if (locked)
                                  const Align(
                                    alignment: Alignment.topRight,
                                    child: Padding(
                                      padding: EdgeInsets.all(3),
                                      child: Icon(Icons.lock,
                                          size: 14, color: Colors.white),
                                    ),
                                  ),
                              ],
                            ),
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
