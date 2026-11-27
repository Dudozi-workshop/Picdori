import 'dart:io';
import 'package:flutter/material.dart';
import '../services/picdori_archive.dart';
import 'picdori_bento.dart';

String formatSize(int n) => n < 1000 ? '$n B'
    : n < 1000000 ? '${(n / 1000).round()} KB'
    : '${(n / 1000000).toStringAsFixed(2)} MB';

class PicdoriLibraryView extends StatefulWidget {
  const PicdoriLibraryView({super.key, required this.archive,
    required this.onOpen, required this.onTrash});
  final PicdoriArchive archive;
  final ValueChanged<PicdoriFile> onOpen;
  final Future<bool> Function(List<String>, {required int hiddenCount}) onTrash;
  @override
  State<PicdoriLibraryView> createState() => _PicdoriLibraryViewState();
}

class _PicdoriLibraryViewState extends State<PicdoriLibraryView> {
  String query = '', format = '전체', order = '최신순';
  final searchController = TextEditingController();
  bool selection = false;
  final chosen = <String>{};

  @override
  void dispose() {
    searchController.dispose();
    super.dispose();
  }

  void _resetFilters() {
    searchController.clear();
    setState(() {
      query = '';
      format = '전체';
    });
  }

  @override
  Widget build(BuildContext context) {
    final files = widget.archive.active.where((f) =>
      (format == '전체' || f.format == format) &&
      f.name.toLowerCase().contains(query.toLowerCase())).toList();
    if (order == '오래된순') {
      files.sort((a,b) => a.createdAt.compareTo(b.createdAt));
    } else if (order == '용량순') {
      files.sort((a,b) => b.size.compareTo(a.size));
    } else if (order == '이름순') {
      files.sort((a,b) => a.name.compareTo(b.name));
    }
    return ListView(padding: const EdgeInsets.all(16), children: [
      Row(children: [
        const Expanded(child: Text('내 파일', style: TextStyle(
          fontSize: 24, fontWeight: FontWeight.w800))),
        TextButton(onPressed: () => setState(() {
          selection = !selection; chosen.clear();
        }), child: Text(selection ? '취소' : '선택')),
      ]),
      Text('${widget.archive.active.length}개 · ${formatSize(widget.archive.activeBytes)}',
        style: const TextStyle(fontSize: 12, color: PicdoriColors.muted)),
      const SizedBox(height: 14),
      TextField(key: const ValueKey('picdori-file-search'),
        controller: searchController,
        onChanged: (v) => setState(() => query = v),
        decoration: const InputDecoration(
          prefixIcon: Icon(Icons.search), hintText: '파일명 검색')),
      Row(children: [
        Expanded(child: SingleChildScrollView(
          scrollDirection: Axis.horizontal,
          child: Row(children: [
            for (final item in ['전체', 'JPG', 'PNG'])
              Padding(padding: const EdgeInsets.only(right: 5),
                child: ChoiceChip(label: Text(item), selected: format == item,
                  showCheckmark: false,
                  onSelected: (_) => setState(() => format = item))),
          ]))),
        DropdownButton<String>(value: order,
          underline: const SizedBox.shrink(),
          items: ['최신순','오래된순','이름순','용량순']
              .map((e) => DropdownMenuItem(value: e,
                child: Text(e, style: const TextStyle(fontSize: 12)))).toList(),
          onChanged: (v) => setState(() => order = v ?? '최신순')),
      ]),
      const SizedBox(height: 10),
      if (widget.archive.active.isEmpty)
        const Center(child: Padding(padding: EdgeInsets.all(40),
          child: Text('아직 보관된 결과물이 없어요.')))
      else if (files.isEmpty)
        Padding(padding: const EdgeInsets.symmetric(vertical: 24),
          child: Column(children: [
            const Text('조건에 맞는 사진이 없어요.'),
            TextButton(onPressed: _resetFilters, child: const Text('검색·필터 초기화')),
          ])),
      GridView.builder(shrinkWrap: true,
        physics: const NeverScrollableScrollPhysics(),
        itemCount: files.length,
        gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
          crossAxisCount: MediaQuery.sizeOf(context).width < 360 ? 2 : 3,
          crossAxisSpacing: 9, mainAxisSpacing: 9, childAspectRatio: .76),
        itemBuilder: (context, i) {
          final f = files[i];
          return InkWell(
            onLongPress: () => setState(() {
              selection = true; chosen.add(f.id);
            }),
            onTap: selection ? () => setState(() {
              if (!chosen.add(f.id)) chosen.remove(f.id);
            }) : () => widget.onOpen(f),
            child: Column(children: [
              Expanded(child: Stack(fit: StackFit.expand, children: [
                ClipRRect(borderRadius: BorderRadius.circular(13),
                  child: Image.file(File(f.path), fit: BoxFit.cover,
                    cacheWidth: 350,
                    errorBuilder: (context, error, stack) =>
                      const Icon(Icons.broken_image_outlined))),
                if (selection) Align(alignment: Alignment.topRight,
                  child: Icon(chosen.contains(f.id)
                    ? Icons.check_circle : Icons.radio_button_unchecked,
                    color: PicdoriColors.accent)),
              ])),
              const SizedBox(height: 4),
              Text(f.name, maxLines: 1, overflow: TextOverflow.ellipsis,
                style: const TextStyle(fontSize: 11)),
              Text(formatSize(f.size), style: const TextStyle(
                fontSize: 10, color: PicdoriColors.muted)),
            ]),
          );
        }),
      if (selection) ...[
        TextButton(onPressed: () => setState(() {
          final current = files.map((e) => e.id).toSet();
          if (chosen.containsAll(current)) { chosen.removeAll(current); }
          else { chosen.addAll(current); }
        }), child: const Text('현재 결과 전체 선택')),
        FilledButton.icon(
          onPressed: chosen.isEmpty ? null : () async {
            final visibleIds = files.map((file) => file.id).toSet();
            final hiddenCount = chosen.where((id) => !visibleIds.contains(id)).length;
            final moved = await widget.onTrash(chosen.toList(), hiddenCount: hiddenCount);
            if (moved && mounted) {
              setState(() {
                chosen.clear();
                selection = false;
              });
            }
          },
          icon: const Icon(Icons.delete_outline),
          label: Text('${chosen.length}개 최근 삭제로 이동')),
      ],
    ]);
  }
}

class PicdoriHistoryView extends StatelessWidget {
  const PicdoriHistoryView({super.key, required this.archive,
    required this.onReuse, required this.onRemove});
  final PicdoriArchive archive;
  final ValueChanged<PicdoriHistory> onReuse;
  final ValueChanged<PicdoriHistory> onRemove;
  @override
  Widget build(BuildContext context) => ListView(
    padding: const EdgeInsets.all(16), children: [
      const Text('최근 작업', style: TextStyle(
        fontSize: 24, fontWeight: FontWeight.w800)),
      const Text('이전에 사용한 조건을 다시 활용해요.',
        style: TextStyle(fontSize: 12, color: PicdoriColors.muted)),
      const SizedBox(height: 14),
      if (archive.recent.isEmpty)
        const Padding(padding: EdgeInsets.all(40),
          child: Center(child: Text('아직 작업 기록이 없어요.'))),
      for (final h in archive.recent)
        Card(elevation: 0, color: PicdoriColors.paper,
          child: ListTile(
            leading: const Icon(Icons.tune, color: PicdoriColors.accent),
            title: Text('${h.settings['width']} × ${h.settings['height']}px · ${h.settings['format']}',
              style: const TextStyle(fontWeight: FontWeight.w700,
                fontSize: 13)),
            subtitle: Text('${h.settings['maxBytes'] == null ? '용량 제한 없음' : formatSize(h.settings['maxBytes'] as int)} · ${h.settings['mode'] == 'crop' ? '잘라서 채우기' : '전체 유지'}\n${h.createdAt.toLocal().toString().substring(0,16)}',
              style: const TextStyle(fontSize: 11)),
            isThreeLine: true,
            onTap: () => onReuse(h),
            trailing: IconButton(tooltip: '기록 삭제',
              onPressed: () => onRemove(h),
              icon: const Icon(Icons.close, size: 18)),
          )),
    ]);
}

class PicdoriSettingsView extends StatelessWidget {
  const PicdoriSettingsView({super.key, required this.onStorage,
    required this.onTrash});
  final VoidCallback onStorage, onTrash;
  @override
  Widget build(BuildContext context) => ListView(
    padding: const EdgeInsets.all(16), children: [
      const Text('설정', style: TextStyle(
        fontSize: 24, fontWeight: FontWeight.w800)),
      const SizedBox(height: 18),
      const Text('파일 및 저장', style: TextStyle(fontWeight: FontWeight.w700)),
      const ListTile(leading: Icon(Icons.folder_outlined),
        title: Text('자동 보관'), subtitle: Text('항상 사용 · 모든 성공 결과를 보관')),
      ListTile(leading: const Icon(Icons.storage_outlined),
        title: const Text('저장 공간 관리'), onTap: onStorage,
        trailing: const Icon(Icons.chevron_right)),
      ListTile(leading: const Icon(Icons.delete_outline),
        title: const Text('최근 삭제한 항목'),
        subtitle: const Text('7일 복구 · 즉시 영구 삭제'),
        onTap: onTrash, trailing: const Icon(Icons.chevron_right)),
      const SizedBox(height: 20),
      const Text('앱 정보', style: TextStyle(fontWeight: FontWeight.w700)),
      const ListTile(leading: Icon(Icons.info_outline),
        title: Text('픽도리'), subtitle: Text('원본 사진은 변경하지 않아요.')),
      const ListTile(leading: Icon(Icons.shield_outlined),
        title: Text('보관 데이터'),
        subtitle: Text('앱 삭제나 데이터 초기화 시 내부 보관본을 잃을 수 있어요.')),
    ]);
}
