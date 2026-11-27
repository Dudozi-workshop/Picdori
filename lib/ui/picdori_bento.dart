import 'package:flutter/material.dart';

/// Shared Picdori palette. Cream is the canvas; peach, sage and lavender
/// identify tools without requiring users to learn color-only semantics.
abstract final class PicdoriColors {
  static const background = Color(0xFFFFF9F3);
  static const paper = Color(0xFFFFFFFF);
  static const peach = Color(0xFFFBE0D9);
  static const sage = Color(0xFFE4EAD9);
  static const lavender = Color(0xFFEEE4F2);
  static const oatmeal = Color(0xFFF2ECE3);
  static const ink = Color(0xFF3E3A34);
  static const muted = Color(0xFF756A5F);
  static const accent = Color(0xFFA64C37);
  static const coral = Color(0xFFF57450);
  static const outline = Color(0xFFEADFD3);
}

class PicdoriBentoHome extends StatelessWidget {
  const PicdoriBentoHome({super.key, required this.onSelect, this.onSettings});

  final ValueChanged<String> onSelect;
  final VoidCallback? onSettings;

  @override
  Widget build(BuildContext context) {
    final compact = MediaQuery.sizeOf(context).width < 350 ||
        MediaQuery.textScalerOf(context).scale(16) >= 21;
    final compress = _ToolCard(
      key: const ValueKey('picdori-home-compress'),
      title: '용량 줄이기',
      description: '목표 용량 설정',
      sticker: 'compress',
      color: PicdoriColors.sage,
      vertical: !compact,
      onTap: () => onSelect('compress'),
    );
    final format = _ToolCard(
      key: const ValueKey('picdori-home-format'),
      title: '형식 바꾸기',
      description: 'JPG ↔ PNG',
      sticker: 'format',
      color: PicdoriColors.lavender,
      vertical: !compact,
      onTap: () => onSelect('format'),
    );

    return Center(
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 580),
        child: Padding(
          padding: EdgeInsets.fromLTRB(compact ? 14 : 18, 8,
              compact ? 14 : 18, 20),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              SizedBox(
                height: 64,
                child: Row(children: [
                  ClipRRect(
                    borderRadius: BorderRadius.circular(7),
                    child: Image.asset('assets/icons/picdori_launcher.png',
                        key: const ValueKey('picdori-brand-mark'),
                        width: 28, height: 28, cacheWidth: 112,
                        excludeFromSemantics: true),
                  ),
                  const SizedBox(width: 6),
                  Image.asset('assets/home/wordmark.webp',
                      semanticLabel: '픽도리', width: 60),
                  const Spacer(),
                  Align(
                    alignment: Alignment.bottomCenter,
                    child: Image.asset('assets/home/poco.webp',
                        width: 49, excludeFromSemantics: true),
                  ),
                  IconButton(
                    key: const ValueKey('picdori-header-settings'),
                    tooltip: '설정',
                    onPressed: onSettings,
                    icon: const Icon(Icons.settings_outlined,
                        size: 19, color: PicdoriColors.ink),
                  ),
                ]),
              ),
              _ToolCard(
                key: const ValueKey('picdori-home-size'),
                title: '사진 크기 조정',
                description: '픽셀 · 비율 · 자르기',
                sticker: 'resize',
                color: PicdoriColors.peach,
                onTap: () => onSelect('size'),
              ),
              const SizedBox(height: 10),
              if (compact) ...[
                compress,
                const SizedBox(height: 10),
                format,
              ] else
                IntrinsicHeight(
                  child: Row(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      Expanded(child: compress),
                      const SizedBox(width: 10),
                      Expanded(child: format),
                    ],
                  ),
                ),
              const SizedBox(height: 10),
              _ToolCard(
                key: const ValueKey('picdori-home-all'),
                title: '한 번에 맞추기',
                description: '크기 · 용량 · 형식 함께 설정',
                sticker: 'all',
                color: const Color(0xFFFDEDD4),
                onTap: () => onSelect('all'),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _ToolCard extends StatelessWidget {
  const _ToolCard({
    super.key,
    required this.title,
    required this.description,
    required this.sticker,
    required this.color,
    required this.onTap,
    this.vertical = false,
  });

  final String title;
  final String description;
  final String sticker;
  final Color color;
  final VoidCallback onTap;
  final bool vertical;

  @override
  Widget build(BuildContext context) {
    final copy = Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: [
        Text(
          title,
          style: TextStyle(
            color: PicdoriColors.ink,
            fontWeight: FontWeight.w600,
            fontSize: vertical ? 17 : 19,
            height: 1.25,
          ),
        ),
        const SizedBox(height: 5),
        Text(
          description,
          style: const TextStyle(
            color: PicdoriColors.muted,
            fontSize: 13,
            height: 1.4,
          ),
        ),
      ],
    );
    final art = Image.asset('assets/home/$sticker.webp',
        width: vertical ? 120 : 168, height: vertical ? 76 : 104,
        fit: BoxFit.contain, excludeFromSemantics: true);

    return Semantics(
      button: true,
      child: Material(
        color: color,
        borderRadius: BorderRadius.circular(17),
        clipBehavior: Clip.antiAlias,
        child: InkWell(
          onTap: onTap,
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: vertical
                ? Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Align(alignment: Alignment.topCenter, child: art),
                      const SizedBox(height: 12),
                      copy,
                    ],
                  )
                : Row(children: [
                    Expanded(flex: 6, child: copy),
                    const SizedBox(width: 8),
                    Flexible(flex: 5, child: art),
                  ]),
          ),
        ),
      ),
    );
  }
}
