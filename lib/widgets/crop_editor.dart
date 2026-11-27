import 'dart:typed_data';

import 'package:crop_your_image/crop_your_image.dart';
import 'package:flutter/material.dart';

/// Full-screen editor for the only task that needs direct photo manipulation.
/// Keep the crop frame fixed at the requested output aspect; users pan and
/// pinch the photo underneath instead of resizing a wandering selection box.
class CropEditor extends StatefulWidget {
  const CropEditor({super.key, required this.image, required this.aspectRatio});

  final Uint8List image;
  final double aspectRatio;

  @override
  State<CropEditor> createState() => _CropEditorState();
}

class _CropEditorState extends State<CropEditor> {
  final _controller = CropController();
  bool _working = false;
  int _undoCount = 0;
  int _redoCount = 0;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('자르기 위치 조절'),
        actions: [
          IconButton(
            tooltip: '이전 위치로',
            icon: const Icon(Icons.undo),
            onPressed: _working || _undoCount == 0
                ? null : _controller.undo,
          ),
          IconButton(
            tooltip: '다시 실행',
            icon: const Icon(Icons.redo),
            onPressed: _working || _redoCount == 0
                ? null : _controller.redo,
          ),
        ],
      ),
      body: SafeArea(
        child: Column(
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(18, 6, 18, 0),
              child: Text(
                '사진을 움직여 남길 영역을 정하고, 두 손가락으로 확대할 수 있어요.',
                textAlign: TextAlign.center,
                style: Theme.of(context).textTheme.bodySmall,
              ),
            ),
            Expanded(
              child: Padding(
                padding: const EdgeInsets.all(16),
                child: Crop(
                  image: widget.image,
                  controller: _controller,
                  aspectRatio: widget.aspectRatio,
                  interactive: true,
                  fixCropRect: true,
                  maskColor: Colors.black.withValues(alpha: 0.56),
                  onHistoryChanged: (history) {
                    if (!mounted) return;
                    if (_undoCount != history.undoCount ||
                        _redoCount != history.redoCount) {
                      setState(() {
                        _undoCount = history.undoCount;
                        _redoCount = history.redoCount;
                      });
                    }
                  },
                  onCropped: (result) {
                    if (!mounted) return;
                    switch (result) {
                      case CropSuccess(:final croppedImage):
                        Navigator.pop(context, croppedImage);
                      case CropFailure(:final cause):
                        setState(() => _working = false);
                        ScaffoldMessenger.of(context).showSnackBar(
                          SnackBar(content: Text('자르기 실패: $cause')),
                        );
                    }
                  },
                ),
              ),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 8, 16, 16),
              child: SizedBox(
                width: double.infinity,
                child: FilledButton.icon(
                  onPressed: _working ? null : () {
                    setState(() => _working = true);
                    _controller.crop();
                  },
                  icon: const Icon(Icons.crop),
                  label: Text(_working ? '처리 중...' : '이 위치로 자르기'),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
