import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:gal/gal.dart';
import 'package:path_provider/path_provider.dart';
import 'package:share_plus/share_plus.dart';

import '../../core/edit_history.dart';
import '../../core/edit_ops.dart';
import '../../core/image_pipeline.dart';
import 'crop_screen.dart';

/// 사진 편집 화면 (M1 셸).
///
/// 프리뷰는 다운스케일된 이미지에 연산을 적용해 빠르게 갱신하고,
/// 저장 시에만 원본 해상도로 전체 파이프라인을 돌린다.
class EditorScreen extends StatefulWidget {
  const EditorScreen({super.key, required this.originalBytes});

  final Uint8List originalBytes;

  @override
  State<EditorScreen> createState() => _EditorScreenState();
}

class _EditorScreenState extends State<EditorScreen> {
  static const int _previewMaxDimension = 1280;

  final EditHistory _history = EditHistory();

  /// 방향 보정 + 다운스케일만 적용된 프리뷰 원본 (비교 보기에도 사용).
  Uint8List? _basePreviewBytes;

  /// 현재 연산이 모두 적용된 프리뷰.
  Uint8List? _previewBytes;

  bool _busy = false;
  bool _saving = false;
  bool _comparing = false;
  int _generation = 0;

  @override
  void initState() {
    super.initState();
    _preparePreview();
  }

  Future<void> _preparePreview() async {
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
      setState(() {
        _basePreviewBytes = base;
        _previewBytes = base;
      });
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('이미지를 열 수 없습니다: $e')),
      );
      Navigator.of(context).pop();
    }
  }

  Future<void> _recomputePreview() async {
    final base = _basePreviewBytes;
    if (base == null) return;
    final generation = ++_generation;
    setState(() => _busy = true);
    try {
      final result = await compute(
        runPipeline,
        PipelineRequest(sourceBytes: base, ops: _history.ops),
      );
      if (!mounted || generation != _generation) return;
      setState(() => _previewBytes = result);
    } finally {
      if (mounted && generation == _generation) {
        setState(() => _busy = false);
      }
    }
  }

  void _apply(EditOp op) {
    _history.push(op);
    _recomputePreview();
  }

  void _undo() {
    if (_history.undo() != null) _recomputePreview();
  }

  void _redo() {
    if (_history.redo() != null) _recomputePreview();
  }

  Future<void> _openCrop() async {
    final preview = _previewBytes;
    if (preview == null || _busy) return;
    final rect = await Navigator.of(context).push<Rect>(
      MaterialPageRoute<Rect>(
        builder: (_) => CropScreen(imageBytes: preview),
      ),
    );
    if (rect != null) _apply(CropOp(rect));
  }

  Future<Uint8List> _renderFullResolution() {
    return compute(
      runPipeline,
      PipelineRequest(
        sourceBytes: widget.originalBytes,
        ops: _history.ops,
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
    if (_history.isEmpty) return true;
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

  @override
  Widget build(BuildContext context) {
    final showing = _comparing ? _basePreviewBytes : _previewBytes;
    return PopScope(
      canPop: _history.isEmpty,
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
              onPressed: _previewBytes != null && !_saving ? _share : null,
              icon: const Icon(Icons.ios_share),
            ),
            Padding(
              padding: const EdgeInsets.only(right: 8),
              child: FilledButton(
                onPressed: _previewBytes != null && !_saving ? _save : null,
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
              child: showing == null
                  ? const Center(child: CircularProgressIndicator())
                  : GestureDetector(
                      onLongPressStart: (_) =>
                          setState(() => _comparing = true),
                      onLongPressEnd: (_) =>
                          setState(() => _comparing = false),
                      child: Stack(
                        fit: StackFit.expand,
                        children: [
                          Image.memory(showing, gaplessPlayback: true),
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
            _Toolbar(
              enabled: _previewBytes != null && !_busy,
              onCrop: _openCrop,
              onRotateLeft: () => _apply(const RotateOp(3)),
              onRotateRight: () => _apply(const RotateOp(1)),
              onFlipHorizontal: () => _apply(const FlipOp(horizontal: true)),
              onFlipVertical: () => _apply(const FlipOp(horizontal: false)),
            ),
          ],
        ),
      ),
    );
  }
}

class _Toolbar extends StatelessWidget {
  const _Toolbar({
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
    return SafeArea(
      top: false,
      child: Container(
        height: 84,
        color: const Color(0xFF17171C),
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
