import 'dart:async';
import 'dart:io';
import 'package:flutter/material.dart';
import '../services/picdori_archive.dart';
import 'picdori_bento.dart';
import 'library_pages.dart';

class PicdoriTrashView extends StatefulWidget {
  const PicdoriTrashView({super.key, required this.archive,
    required this.onRestore, required this.onPurge});
  final PicdoriArchive archive;
  final Future<void> Function(List<String>) onRestore;
  final Future<void> Function(List<String>) onPurge;

  @override
  State<PicdoriTrashView> createState() => _PicdoriTrashViewState();
}

String recoveryTimeLeft(Duration remaining) {
  if (remaining <= Duration.zero) return '복구 기한 만료';
  if (remaining.inDays > 0) return '${remaining.inDays}일 남음';
  if (remaining.inHours > 0) return '${remaining.inHours}시간 남음';
  return '1시간 미만';
}

class _PicdoriTrashViewState extends State<PicdoriTrashView> {
  late final Timer _clock;

  @override
  void initState() {
    super.initState();
    _clock = Timer.periodic(const Duration(minutes: 1), (_) => setState(() {}));
  }

  @override
  void dispose() {
    _clock.cancel();
    super.dispose();
  }

  void _showDeadline(PicdoriFile file) {
    final local = file.expiresAt!.toLocal();
    String pad(int value) => value.toString().padLeft(2, '0');
    final date = '${local.year}.${pad(local.month)}.${pad(local.day)}';
    final time = '${pad(local.hour)}:${pad(local.minute)}:${pad(local.second)}';
    showDialog<void>(context: context, builder: (context) => AlertDialog(
      title: const Text('복구 기한'),
      content: Text('${file.name}\n$date $time (기기 시간)'),
      actions: [TextButton(onPressed: () => Navigator.pop(context),
        child: const Text('닫기'))],
    ));
  }

  @override
  Widget build(BuildContext context) {
    final items = widget.archive.trash;
    final now = DateTime.now().toUtc();
    return ListView(padding: const EdgeInsets.all(16), children: [
      const Text('최근 삭제한 항목',
        style: TextStyle(fontSize: 23, fontWeight: FontWeight.w800)),
      const SizedBox(height: 7),
      Text('${items.length}개 · ${formatSize(widget.archive.trashBytes)}',
        style: const TextStyle(color: PicdoriColors.muted)),
      const Text('삭제 후 7일간 복구할 수 있어요. 복구 대기 중에는 공간을 차지해요.',
        style: TextStyle(fontSize: 12, color: PicdoriColors.muted)),
      if (items.isNotEmpty) Align(
        alignment: Alignment.centerRight,
        child: TextButton.icon(
          onPressed: () => widget.onPurge(items.map((f) => f.id).toList()),
          icon: const Icon(Icons.delete_forever),
          label: const Text('전체 비우기'))),
      if (items.isEmpty) const Padding(
        padding: EdgeInsets.all(44),
        child: Center(child: Text('최근 삭제한 사진이 없어요.'))),
      for (final f in items)
        Card(elevation: 0, color: PicdoriColors.paper,
          child: ListTile(
            leading: ClipRRect(
              borderRadius: BorderRadius.circular(8),
              child: Image.file(File(f.path),
                width: 48, height: 48, fit: BoxFit.cover,
                errorBuilder: (ctx, e, s) =>
                    const SizedBox(width: 48, child: Icon(Icons.broken_image_outlined)))),
            onTap: () => _showDeadline(f),
            title: Text(f.name, maxLines: 1,
              overflow: TextOverflow.ellipsis),
            subtitle: Text('${formatSize(f.size)} · ${recoveryTimeLeft(f.expiresAt!.difference(now))}',
              style: const TextStyle(fontSize: 11)),
            trailing: Row(mainAxisSize: MainAxisSize.min, children: [
              IconButton(tooltip: '복구',
                onPressed: f.expiresAt!.isAfter(now) ? () => widget.onRestore([f.id]) : null,
                icon: const Icon(Icons.restore)),
              IconButton(tooltip: '영구 삭제',
                onPressed: () => widget.onPurge([f.id]),
                icon: const Icon(Icons.delete_forever_outlined)),
            ]),
          )),
    ]);
  }
}

class PicdoriStorageView extends StatelessWidget {
  const PicdoriStorageView({super.key, required this.archive,
    required this.onTrash});
  final PicdoriArchive archive;
  final VoidCallback onTrash;

  @override
  Widget build(BuildContext context) => ListView(
    padding: const EdgeInsets.all(16), children: [
      const Text('저장 공간 관리',
        style: TextStyle(fontSize: 23, fontWeight: FontWeight.w800)),
      const SizedBox(height: 14),
      Card(elevation: 0, color: PicdoriColors.paper,
        child: Padding(padding: const EdgeInsets.all(18),
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            const Text('픽도리 이미지 보관 사용량',
              style: TextStyle(color: PicdoriColors.muted, fontSize: 12)),
            Text(formatSize(archive.activeBytes + archive.trashBytes),
              style: const TextStyle(fontSize: 28,
                fontWeight: FontWeight.w800)),
            const SizedBox(height: 18),
            Row(children: [
              const Expanded(child: Text('내 파일')),
              Text(formatSize(archive.activeBytes)),
            ]),
            const SizedBox(height: 9),
            Row(children: [
              const Expanded(child: Text('최근 삭제')),
              Text(formatSize(archive.trashBytes)),
            ]),
            const SizedBox(height: 14),
            const Text('캐시·임시 파일과 기기 전체 사용량은 제외한 값이에요.',
              style: TextStyle(fontSize: 11, color: PicdoriColors.muted)),
          ]))),
      const SizedBox(height: 14),
      OutlinedButton.icon(onPressed: onTrash,
        icon: const Icon(Icons.delete_outline),
        label: const Text('최근 삭제한 항목 관리')),
    ]);
}
