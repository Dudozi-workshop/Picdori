import 'dart:convert';
import 'dart:io';
import 'dart:math';
import 'dart:typed_data';

import 'package:crypto/crypto.dart';
import 'package:path_provider/path_provider.dart';

import '../core/image_processor.dart';

/// Durable app-private outputs. Gallery/Files exports are separate copies.
class PicdoriFile {
  PicdoriFile({
    required this.id,
    required this.path,
    required this.name,
    required this.hash,
    required this.size,
    required this.width,
    required this.height,
    required this.format,
    required this.createdAt,
    this.sourceId,
    this.deletedAt,
  });

  final String id;
  final String path;
  final String name;
  final String hash;
  final int size;
  final int width;
  final int height;
  final String format;
  final DateTime createdAt;
  final String? sourceId;
  DateTime? deletedAt;

  bool get inTrash => deletedAt != null;
  DateTime? get expiresAt => deletedAt?.add(const Duration(days: 7));

  Map<String, dynamic> toJson() => {
    'id': id,
    'path': path,
    'name': name,
    'hash': hash,
    'size': size,
    'width': width,
    'height': height,
    'format': format,
    'createdAt': createdAt.toUtc().toIso8601String(),
    'sourceId': sourceId,
    'deletedAt': deletedAt?.toUtc().toIso8601String(),
  };

  factory PicdoriFile.fromJson(Map<String, dynamic> m) => PicdoriFile(
    id: m['id'] as String,
    path: m['path'] as String,
    name: m['name'] as String,
    hash: m['hash'] as String,
    size: m['size'] as int,
    width: m['width'] as int,
    height: m['height'] as int,
    format: m['format'] as String,
    createdAt: DateTime.parse(m['createdAt'] as String),
    sourceId: m['sourceId'] as String?,
    deletedAt: m['deletedAt'] == null
        ? null : DateTime.parse(m['deletedAt'] as String),
  );
}

class PicdoriHistory {
  PicdoriHistory({
    required this.id,
    required this.fileId,
    required this.createdAt,
    required this.settings,
  });

  final String id;
  final String fileId;
  final DateTime createdAt;
  final Map<String, dynamic> settings;

  Map<String, dynamic> toJson() => {
    'id': id,
    'fileId': fileId,
    'createdAt': createdAt.toUtc().toIso8601String(),
    'settings': settings,
  };

  factory PicdoriHistory.fromJson(Map<String, dynamic> m) => PicdoriHistory(
    id: m['id'] as String,
    fileId: m['fileId'] as String,
    createdAt: DateTime.parse(m['createdAt'] as String),
    settings: Map<String, dynamic>.from(m['settings'] as Map),
  );
}

class PicdoriSave {
  const PicdoriSave(this.file, this.reused);
  final PicdoriFile file;
  final bool reused;
}

/// One small JSON metadata index plus actual image files. Writes of the index
/// are staged and renamed; a failed index write must not report archive success.
class PicdoriArchive {
  PicdoriArchive({Directory? root, DateTime Function()? now})
      : _providedRoot = root,
        _now = now ?? DateTime.now;

  final Directory? _providedRoot;
  final DateTime Function() _now;
  Future<void> _pendingWrite = Future<void>.value();
  final List<PicdoriFile> _files = [];
  final List<PicdoriHistory> _history = [];
  late Directory _root;
  bool _ready = false;

  List<PicdoriFile> get active => List.unmodifiable(
    _files.where((f) => !f.inTrash).toList()
      ..sort((a, b) => b.createdAt.compareTo(a.createdAt)),
  );
  List<PicdoriFile> get trash => List.unmodifiable(
    _files.where((f) => f.inTrash).toList()
      ..sort((a, b) => b.deletedAt!.compareTo(a.deletedAt!)),
  );
  List<PicdoriHistory> get recent => List.unmodifiable(
    List<PicdoriHistory>.from(_history)
      ..sort((a, b) => b.createdAt.compareTo(a.createdAt)),
  );
  int get activeBytes => active.fold(0, (sum, f) => sum + f.size);
  int get trashBytes => trash.fold(0, (sum, f) => sum + f.size);
  PicdoriFile? find(String id) {
    for (final f in _files) {
      if (f.id == id) return f;
    }
    return null;
  }

  Future<void> initialize() => _serialize(() async {
    final base = _providedRoot ?? await getApplicationSupportDirectory();
    _root = Directory(base.path + '/picdori_library');
    await _root.create(recursive: true);
    await Directory(_root.path + '/images').create(recursive: true);
    final index = File(_root.path + '/index.json');
    if (await index.exists()) {
      final data = jsonDecode(await index.readAsString()) as Map<String, dynamic>;
      _files
        ..clear()
        ..addAll((data['files'] as List? ?? []).map((e) =>
            PicdoriFile.fromJson(Map<String, dynamic>.from(e as Map))));
      _history
        ..clear()
        ..addAll((data['history'] as List? ?? []).map((e) =>
            PicdoriHistory.fromJson(Map<String, dynamic>.from(e as Map))));
    }
    _ready = true;
    await _purgeExpired();
  });

  Future<T> _serialize<T>(Future<T> Function() operation) {
    // A failed write reaches its caller without blocking the next operation.
    final next = _pendingWrite.then((_) => operation());
    _pendingWrite = next.then<void>(
      (_) {},
      onError: (Object error, StackTrace stackTrace) {},
    );
    return next;
  }

  void _assertReady() {
    if (!_ready) throw StateError('보관함이 준비되지 않았어요.');
  }

  String _newId() => DateTime.now().microsecondsSinceEpoch.toRadixString(36)
      + '_' + Random.secure().nextInt(0x7fffffff).toRadixString(36);

  Future<void> _persist() async {
    final target = File(_root.path + '/index.json');
    final staging = File(_root.path + '/index.tmp');
    await staging.writeAsString(jsonEncode({
      'version': 1,
      'files': _files.map((f) => f.toJson()).toList(),
      'history': _history.map((h) => h.toJson()).toList(),
    }), flush: true);
    await staging.rename(target.path);
  }

  Future<PicdoriSave> save(ImageResult output, {
    String? sourceId,
    Map<String, dynamic> settings = const {},
  }) => _serialize(() async {
    _assertReady();
    final hash = sha256.convert(output.bytes).toString();
    PicdoriFile? existing;
    for (final entry in _files) {
      if (!entry.inTrash && entry.hash == hash &&
          entry.size == output.size &&
          await File(entry.path).exists()) {
        existing = entry;
        break;
      }
    }

    final now = _now().toUtc();
    PicdoriFile? created;
    if (existing == null) {
      final id = _newId();
      final name = 'picdori_' + now.toIso8601String()
          .replaceAll(RegExp(r'[-:.TZ]'), '').substring(0, 14)
          + '_' + id.substring(0, 5) + '.' + output.extension;
      final path = _root.path + '/images/' + id + '.' + output.extension;
      final staging = File(path + '.tmp');
      await staging.writeAsBytes(output.bytes, flush: true);
      if (await staging.length() != output.size) {
        await staging.delete();
        throw const FileSystemException('출력 파일 크기 검증 실패');
      }
      await staging.rename(path);
      created = PicdoriFile(
        id: id,
        path: path,
        name: name,
        hash: hash,
        size: output.size,
        width: output.width,
        height: output.height,
        format: output.extension.toUpperCase(),
        createdAt: now,
        sourceId: sourceId,
      );
      _files.add(created);
    }

    final saved = existing ?? created!;
    final job = PicdoriHistory(
      id: _newId(), fileId: saved.id, createdAt: now,
      settings: Map<String, dynamic>.from(settings),
    );
    _history.add(job);
    try {
      await _persist();
    } catch (_) {
      _history.remove(job);
      if (created != null) {
        _files.remove(created);
        final file = File(created.path);
        if (await file.exists()) await file.delete();
      }
      rethrow;
    }
    return PicdoriSave(saved, existing != null);
  });

  Future<void> moveToTrash(Iterable<String> ids) => _serialize(() async {
    _assertReady();
    final now = _now().toUtc();
    final affected = _files.where((f) =>
        ids.contains(f.id) && !f.inTrash).toList();
    for (final f in affected) {
      f.deletedAt = now;
    }
    try {
      await _persist();
    } catch (_) {
      for (final f in affected) {
        f.deletedAt = null;
      }
      rethrow;
    }
  });

  Future<void> restore(Iterable<String> ids) => _serialize(() async {
    _assertReady();
    final affected = _files.where((f) => ids.contains(f.id) && f.inTrash).toList();
    if (affected.isEmpty ||
        affected.any((f) => !f.expiresAt!.isAfter(_now().toUtc()))) {
      await _purgeExpired();
      throw StateError('복구 가능한 사진이 없거나 복구 기간이 지났어요.');
    }
    final content = {
      for (final f in _files)
        if (!f.inTrash) (f.hash, f.size),
    };
    for (final f in affected) {
      if (!content.add((f.hash, f.size))) {
        throw StateError('같은 결과물이 이미 내 파일에 있어요.');
      }
      if (!await File(f.path).exists()) {
        throw const FileSystemException('복구할 파일이 없어요.');
      }
    }
    final before = {for (final f in affected) f.id: f.deletedAt};
    for (final f in affected) {
      f.deletedAt = null;
    }
    try {
      await _persist();
    } catch (_) {
      for (final f in affected) {
        f.deletedAt = before[f.id];
      }
      rethrow;
    }
  });

  Future<void> permanentlyDelete(Iterable<String> ids) =>
      _serialize(() => _permanentlyDelete(ids));

  Future<void> _permanentlyDelete(Iterable<String> ids) async {
    _assertReady();
    for (final id in ids.toList()) {
      final entry = find(id);
      if (entry == null || !entry.inTrash) continue;
      final file = File(entry.path);
      if (await file.exists()) await file.delete();
      _files.remove(entry);
      await _persist();
    }
  }

  Future<void> _purgeExpired() async {
    _assertReady();
    final now = _now().toUtc();
    await _permanentlyDelete(_files
        .where((f) => f.expiresAt?.isAfter(now) == false)
        .map((f) => f.id).toList());
  }

  Future<void> deleteHistory(String id) => _serialize(() async {
    _assertReady();
    final before = List<PicdoriHistory>.from(_history);
    _history.removeWhere((h) => h.id == id);
    try {
      await _persist();
    } catch (_) {
      _history..clear()..addAll(before);
      rethrow;
    }
  });

  Future<Uint8List> loadBytes(PicdoriFile file) =>
      File(file.path).readAsBytes();
}
