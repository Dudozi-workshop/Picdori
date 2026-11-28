import 'dart:typed_data';
import 'package:flutter/material.dart';

class PhotoComparePage extends StatefulWidget {
  const PhotoComparePage({
    super.key,
    required this.source,
    required this.output,
    required this.sourceDetails,
    required this.outputDetails,
  });

  final Uint8List source;
  final Uint8List output;
  final String sourceDetails;
  final String outputDetails;

  @override
  State<PhotoComparePage> createState() => _PhotoComparePageState();
}

class _PhotoComparePageState extends State<PhotoComparePage> {
  bool _showSource = false;

  @override
  Widget build(BuildContext context) {
    final label = _showSource ? '원본' : '완성본';
    final details = _showSource ? widget.sourceDetails : widget.outputDetails;
    return Scaffold(
      appBar: AppBar(title: const Text('사진 비교')),
      body: SafeArea(
        top: false,
        child: Column(children: [
          Expanded(
            child: ColoredBox(
              color: const Color(0xFF242320),
              child: ClipRect(
                child: InteractiveViewer(
                  maxScale: 4,
                  child: SizedBox.expand(
                    child: Image(
                      image: ResizeImage(
                        MemoryImage(_showSource ? widget.source : widget.output),
                        width: 3072, height: 3072, policy: ResizeImagePolicy.fit,
                      ),
                      fit: BoxFit.contain,
                      semanticLabel: '$label 사진',
                    ),
                  ),
                ),
              ),
            ),
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 12, 16, 16),
            child: Column(mainAxisSize: MainAxisSize.min, children: [
              Semantics(liveRegion: true, child: Text(details, textAlign: TextAlign.center)),
              const SizedBox(height: 8),
              SegmentedButton<bool>(
                segments: const [
                  ButtonSegment(value: true, label: Text('원본')),
                  ButtonSegment(value: false, label: Text('완성본')),
                ],
                selected: {_showSource},
                onSelectionChanged: (value) => setState(() => _showSource = value.single),
              ),
            ]),
          ),
        ]),
      ),
    );
  }
}
