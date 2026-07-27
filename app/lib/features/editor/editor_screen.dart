import 'dart:io';
import 'dart:ui' as ui;

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:gal/gal.dart';
import 'package:path_provider/path_provider.dart';
import 'package:share_plus/share_plus.dart';

import '../../core/color_adjustments.dart';
import '../../core/edit_ops.dart';
import '../../core/edit_state.dart';
import '../../core/filter_presets.dart';
import '../../core/image_pipeline.dart';
import 'adjust_panel.dart';
import 'crop_screen.dart';
import 'filter_panel.dart';
import 'shader_preview.dart';

enum _EditorMode { tools, filter, adjust }

/// 사진 편집 화면.
///
/// - 기하 연산(자르기/회전/반전)은 CPU isolate에서 프리뷰 바이트로 굽는다.
/// - 색보정/필터는 GPU 셰이더로 실시간 렌더링한다 (셰이더 로드 실패 시
///   CPU 폴백).
/// - 모든 변경은 [EditSnapshot]으로 undo/redo 된다.
/// - 저장/공유 시에만 원본 해상도로 전체 파이프라인을 실행한다.
class EditorScreen extends StatefulWidget {
  const EditorScreen({super.key, required this.originalBytes});

  final Uint8List originalBytes;

  @override
  State<EditorScreen> createState() => _EditorScreenState();
}

class _EditorScreenState extends State<EditorScreen> {
  static const int _previewMaxDimension = 1280;

  final HistoryStack<EditSnapshot> _history =
      HistoryStack(EditSnapshot.initial);

  /// 히스토리 확정 전의 실시간 상태 (슬라이더 드래그 중 포함).
  EditSnapshot _live = EditSnapshot.initial;

  /// 방향 보정 + 다운스케일만 적용된 프리뷰 원본 (비교 보기에도 사용).
  Uint8List? _basePreviewBytes;

  /// 기하 연산까지 적용된 프리뷰.
  Uint8List? _geomBytes;
  ui.Image? _geomImage;
  List<EditOp> _renderedGeometry = const [];

  ui.FragmentProgram? _program;
  bool _programResolved = false;

  /// 셰이더 폴백용: 기하 + 색보정까지 CPU로 적용된 프리뷰.
  Uint8List? _fallbackBytes;

  List<Uint8List>? _thumbnails;

  _EditorMode _mode = _EditorMode.tools;
  bool _busy = false;
  bool _saving = false;
  bool _comparing = false;
  int _generation = 0;
  int _thumbGeneration = 0;

  @override
  void initState() {
    super.initState();
    AdjustmentShaderProgram.load().then((program) {
      if (!mounted) return;
      setState(() {
        _program = program;
        _programResolved = true;
      });
      if (program == null) _recomputeFallback();
    });
    _prepareBase();
  }

  @override
  void dispose() {
    _geomImage?.dispose();
    super.dispose();
  }

  Future<void> _prepareBase() async {
    try {
      final base = await compute(
        runPipeline,
        PipelineRequest(
          sourceBytes: widget.originalBytes,
          ops: const [],
          maxDimension: _previewMaxDimension,
        ),
      );
      if (!mounted) return;
      setState(() => _basePreviewBytes = base);
      await _setGeometryPreview(base, const []);
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('이미지를 열 수 없습니다: $e')),
      );
      Navigator.of(context).pop();
    }
  }

  Future<void> _setGeometryPreview(
      Uint8List bytes, List<EditOp> geometry) async {
    final image = await decodeImageFromList(bytes);
    if (!mounted) {
      image.dispose();
      return;
    }
    setState(() {
      _geomImage?.dispose();
      _geomBytes = bytes;
      _geomImage = image;
      _renderedGeometry = geometry;
    });
    _regenerateThumbnails(bytes);
  }

  Future<void> _regenerateThumbnails(Uint8List geomBytes) async {
    final generation = ++_thumbGeneration;
    final thumbs = await compute(
      generateFilterThumbnails,
      ThumbnailRequest(sourceBytes: geomBytes),
    );
    if (!mounted || generation != _thumbGeneration) return;
    setState(() => _thumbnails = thumbs);
  }

  /// 스냅샷과 화면 상태를 동기화한다 (기하 프리뷰 / CPU 폴백 재계산).
  Future<void> _syncFromSnapshot(EditSnapshot snapshot) async {
    setState(() => _live = snapshot);

    if (!listEquals(snapshot.geometry, _renderedGeometry)) {
      final base = _basePreviewBytes;
      if (base == null) return;
      final generation = ++_generation;
      setState(() => _busy = true);
      try {
        final bytes = await compute(
          runPipeline,
          PipelineRequest(sourceBytes: base, ops: snapshot.geometry),
        );
        if (!mounted || generation != _generation) return;
        await _setGeometryPreview(bytes, snapshot.geometry);
      } finally {
        if (mounted && generation == _generation) {
          setState(() => _busy = false);
        }
      }
    }
    if (_programResolved && _program == null) _recomputeFallback();
  }

  /// 셰이더를 못 쓸 때: 색보정/필터까지 CPU로 구운 프리뷰를 만든다.
  Future<void> _recomputeFallback() async {
    final base = _basePreviewBytes;
    if (base == null) return;
    final snapshot = _live;
    final bytes = await compute(
      runPipeline,
      PipelineRequest(
        sourceBytes: base,
        ops: snapshot.geometry,
        adjustments: snapshot.adjustments,
        filterId: snapshot.filterId,
        filterStrength: snapshot.filterStrength,
      ),
    );
    if (!mounted || !identical(snapshot, _live)) return;
    setState(() => _fallbackBytes = bytes);
  }

  void _commit(EditSnapshot snapshot) {
    _history.push(snapshot);
    _syncFromSnapshot(snapshot);
  }

  void _undo() {
    final snapshot = _history.undo();
    if (snapshot != null) _syncFromSnapshot(snapshot);
  }

  void _redo() {
    final snapshot = _history.redo();
    if (snapshot != null) _syncFromSnapshot(snapshot);
  }

  Future<void> _openCrop() async {
    final geom = _geomBytes;
    if (geom == null || _busy) return;
    final rect = await Navigator.of(context).push<Rect>(
      MaterialPageRoute<Rect>(
        builder: (_) => CropScreen(imageBytes: geom),
      ),
    );
    if (rect != null) _commit(_history.current.addGeometry(CropOp(rect)));
  }

  Future<Uint8List> _renderFullResolution() {
    final snapshot = _history.current;
    return compute(
      runPipeline,
      PipelineRequest(
        sourceBytes: widget.originalBytes,
        ops: snapshot.geometry,
        adjustments: snapshot.adjustments,
        filterId: snapshot.filterId,
        filterStrength: snapshot.filterStrength,
        jpegQuality: 95,
      ),
    );
  }

  Future<void> _save() async {
    if (_saving) return;
    setState(() => _saving = true);
    try {
      final bytes = await _renderFullResolution();
      await Gal.putImageBytes(
        bytes,
        name: 'PHOTO_${DateTime.now().millisecondsSinceEpoch}',
      );
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('갤러리에 저장했습니다.')),
      );
    } on GalException catch (e) {
      if (!mounted) return;
      final message = e.type == GalExceptionType.accessDenied
          ? '사진 접근 권한을 허용해 주세요.'
          : '저장에 실패했습니다: ${e.type.message}';
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(message)),
      );
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('저장에 실패했습니다: $e')),
      );
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  Future<void> _share() async {
    if (_saving) return;
    setState(() => _saving = true);
    try {
      final bytes = await _renderFullResolution();
      final dir = await getTemporaryDirectory();
      final path =
          '${dir.path}/PHOTO_${DateTime.now().millisecondsSinceEpoch}.jpg';
      await File(path).writeAsBytes(bytes, flush: true);
      await SharePlus.instance.share(
        ShareParams(files: [XFile(path, mimeType: 'image/jpeg')]),
      );
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('공유에 실패했습니다: $e')),
      );
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  Future<bool> _confirmDiscard() async {
    if (_history.current.isPristine && !_history.canUndo) return true;
    final result = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('편집 내용을 버릴까요?'),
        content: const Text('저장하지 않은 편집 내용이 사라집니다.'),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(false),
            child: const Text('계속 편집'),
          ),
          TextButton(
            onPressed: () => Navigator.of(context).pop(true),
            child: const Text('버리기'),
          ),
        ],
      ),
    );
    return result ?? false;
  }

  Widget _buildPreview() {
    final base = _basePreviewBytes;
    if (base == null || !_programResolved) {
      return const Center(child: CircularProgressIndicator());
    }
    if (_comparing) {
      return Image.memory(base, gaplessPlayback: true);
    }
    final program = _program;
    final image = _geomImage;
    if (program != null && image != null) {
      return ShaderPreview(
        program: program,
        image: image,
        adjustments: _live.adjustments,
        preset: filterPresetById(_live.filterId),
        strength: _live.filterStrength,
      );
    }
    final bytes = _fallbackBytes ?? _geomBytes;
    return bytes == null
        ? const Center(child: CircularProgressIndicator())
        : Image.memory(bytes, gaplessPlayback: true);
  }

  Widget _buildPanel() {
    switch (_mode) {
      case _EditorMode.tools:
        return _GeometryToolbar(
          enabled: _geomBytes != null && !_busy,
          onCrop: _openCrop,
          onRotateLeft: () =>
              _commit(_history.current.addGeometry(const RotateOp(3))),
          onRotateRight: () =>
              _commit(_history.current.addGeometry(const RotateOp(1))),
          onFlipHorizontal: () => _commit(
              _history.current.addGeometry(const FlipOp(horizontal: true))),
          onFlipVertical: () => _commit(
              _history.current.addGeometry(const FlipOp(horizontal: false))),
        );
      case _EditorMode.filter:
        return FilterPanel(
          thumbnails: _thumbnails,
          selectedId: _live.filterId,
          strength: _live.filterStrength,
          onSelect: (id) => _commit(_history.current.copyWith(
            filterId: id,
            clearFilter: id == null,
            filterStrength: 1.0,
          )),
          onStrengthChanged: (v) => setState(
              () => _live = _live.copyWith(filterStrength: v)),
          onStrengthCommitted: (v) =>
              _commit(_history.current.copyWith(filterStrength: v)),
        );
      case _EditorMode.adjust:
        return AdjustPanel(
          adjustments: _live.adjustments,
          onChanged: (a) =>
              setState(() => _live = _live.copyWith(adjustments: a)),
          onCommitted: (a) =>
              _commit(_history.current.copyWith(adjustments: a)),
          onReset: () => _commit(_history.current
              .copyWith(adjustments: ColorAdjustments.neutral)),
        );
    }
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final canPop = _history.current.isPristine && !_history.canUndo;
    return PopScope(
      canPop: canPop,
      onPopInvokedWithResult: (didPop, _) async {
        if (didPop) return;
        final navigator = Navigator.of(context);
        if (await _confirmDiscard()) navigator.pop();
      },
      child: Scaffold(
        appBar: AppBar(
          leading: const BackButton(),
          actions: [
            IconButton(
              tooltip: '실행취소',
              onPressed: _history.canUndo && !_busy ? _undo : null,
              icon: const Icon(Icons.undo),
            ),
            IconButton(
              tooltip: '다시실행',
              onPressed: _history.canRedo && !_busy ? _redo : null,
              icon: const Icon(Icons.redo),
            ),
            IconButton(
              tooltip: '공유',
              onPressed: _geomBytes != null && !_saving ? _share : null,
              icon: const Icon(Icons.ios_share),
            ),
            Padding(
              padding: const EdgeInsets.only(right: 8),
              child: FilledButton(
                onPressed: _geomBytes != null && !_saving ? _save : null,
                child: _saving
                    ? const SizedBox(
                        width: 16,
                        height: 16,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      )
                    : const Text('저장'),
              ),
            ),
          ],
        ),
        body: Column(
          children: [
            Expanded(
              child: GestureDetector(
                onLongPressStart: (_) => setState(() => _comparing = true),
                onLongPressEnd: (_) => setState(() => _comparing = false),
                child: Stack(
                  fit: StackFit.expand,
                  children: [
                    _buildPreview(),
                    if (_busy)
                      const Align(
                        alignment: Alignment.topCenter,
                        child: LinearProgressIndicator(minHeight: 2),
                      ),
                    if (_comparing)
                      Positioned(
                        top: 12,
                        left: 0,
                        right: 0,
                        child: Center(
                          child: Container(
                            padding: const EdgeInsets.symmetric(
                                horizontal: 12, vertical: 6),
                            decoration: BoxDecoration(
                              color: Colors.black54,
                              borderRadius: BorderRadius.circular(20),
                            ),
                            child: const Text('원본'),
                          ),
                        ),
                      ),
                  ],
                ),
              ),
            ),
            Container(
              color: const Color(0xFF17171C),
              child: SafeArea(
                top: false,
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    _buildPanel(),
                    const Divider(height: 1),
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                      children: [
                        for (final (mode, icon, label) in const [
                          (_EditorMode.tools, Icons.crop_rotate, '도구'),
                          (_EditorMode.filter, Icons.auto_awesome, '필터'),
                          (_EditorMode.adjust, Icons.tune, '보정'),
                        ])
                          Expanded(
                            child: InkWell(
                              onTap: () => setState(() => _mode = mode),
                              child: Padding(
                                padding:
                                    const EdgeInsets.symmetric(vertical: 8),
                                child: Column(
                                  children: [
                                    Icon(
                                      icon,
                                      size: 22,
                                      color: _mode == mode
                                          ? scheme.primary
                                          : scheme.onSurfaceVariant,
                                    ),
                                    const SizedBox(height: 2),
                                    Text(
                                      label,
                                      style: TextStyle(
                                        fontSize: 11,
                                        color: _mode == mode
                                            ? scheme.primary
                                            : scheme.onSurfaceVariant,
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                            ),
                          ),
                      ],
                    ),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _GeometryToolbar extends StatelessWidget {
  const _GeometryToolbar({
    required this.enabled,
    required this.onCrop,
    required this.onRotateLeft,
    required this.onRotateRight,
    required this.onFlipHorizontal,
    required this.onFlipVertical,
  });

  final bool enabled;
  final VoidCallback onCrop;
  final VoidCallback onRotateLeft;
  final VoidCallback onRotateRight;
  final VoidCallback onFlipHorizontal;
  final VoidCallback onFlipVertical;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      height: 84,
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceEvenly,
        children: [
          _ToolButton(
            icon: Icons.crop,
            label: '자르기',
            onPressed: enabled ? onCrop : null,
          ),
          _ToolButton(
            icon: Icons.rotate_left,
            label: '왼쪽 회전',
            onPressed: enabled ? onRotateLeft : null,
          ),
          _ToolButton(
            icon: Icons.rotate_right,
            label: '오른쪽 회전',
            onPressed: enabled ? onRotateRight : null,
          ),
          _ToolButton(
            icon: Icons.swap_horiz,
            label: '좌우 반전',
            onPressed: enabled ? onFlipHorizontal : null,
          ),
          _ToolButton(
            icon: Icons.swap_vert,
            label: '상하 반전',
            onPressed: enabled ? onFlipVertical : null,
          ),
        ],
      ),
    );
  }
}

class _ToolButton extends StatelessWidget {
  const _ToolButton({
    required this.icon,
    required this.label,
    required this.onPressed,
  });

  final IconData icon;
  final String label;
  final VoidCallback? onPressed;

  @override
  Widget build(BuildContext context) {
    final color = onPressed == null
        ? Theme.of(context).disabledColor
        : Theme.of(context).colorScheme.onSurface;
    return InkWell(
      onTap: onPressed,
      borderRadius: BorderRadius.circular(12),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(icon, color: color),
            const SizedBox(height: 6),
            Text(label, style: TextStyle(fontSize: 11, color: color)),
          ],
        ),
      ),
    );
  }
}
