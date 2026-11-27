import 'dart:io';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:image/image.dart' as img;
import 'package:picdori/core/image_processor.dart';
import 'package:picdori/services/picdori_archive.dart';

void main() {
  late Directory root;
  late PicdoriArchive archive;
  late DateTime now;

  setUp(() async {
    root = await Directory.systemTemp.createTemp('picdori_archive_');
    now = DateTime.utc(2026, 11, 21);
    archive = PicdoriArchive(root: root, now: () => now);
    await archive.initialize();
  });

  tearDown(() async {
    if (await root.exists()) await root.delete(recursive: true);
  });

  ImageResult example({int width = 3}) {
    final image = img.Image(width: width, height: 2);
    final bytes = Uint8List.fromList(img.encodePng(image));
    return ImageResult(bytes: bytes, width: width, height: 2,
      format: OutputFormat.png);
  }

  test('successful result is durable and duplicate conversion is recorded', () async {
    final result = example();
    final first = await archive.save(result, settings: {
      'width': 3, 'height': 2, 'format': 'PNG',
    });
    final again = await archive.save(result, settings: {
      'width': 3, 'height': 2, 'format': 'PNG',
    });
    expect(first.reused, isFalse);
    expect(again.reused, isTrue);
    expect(archive.active, hasLength(1));
    expect(archive.recent, hasLength(2));
    expect(await File(first.file.path).exists(), isTrue);

    final reopened = PicdoriArchive(root: root);
    await reopened.initialize();
    expect(reopened.active, hasLength(1));
    expect(reopened.recent, hasLength(2));
  });

  test('trash can restore and permanently remove files', () async {
    final file = (await archive.save(example())).file;
    await archive.moveToTrash([file.id]);
    expect(archive.active, isEmpty);
    expect(archive.trash, hasLength(1));
    expect(archive.trashBytes, greaterThan(0));
    await archive.restore([file.id]);
    expect(archive.active, hasLength(1));
    await archive.moveToTrash([file.id]);
    await archive.permanentlyDelete([file.id]);
    expect(archive.trash, isEmpty);
    expect(await File(file.path).exists(), isFalse);
  });

  test('reediting keeps the archived source bytes and adds a new output', () async {
    final original = example();
    final source = (await archive.save(original)).file;
    final edited = runImageProcessing(ImageJob(
      source: await archive.loadBytes(source),
      width: 2,
      height: 2,
      mode: GeometryMode.fit,
      format: OutputFormat.png,
    ));
    final output = await archive.save(edited, sourceId: source.id);

    final reopened = PicdoriArchive(root: root, now: () => now);
    await reopened.initialize();
    expect(reopened.active, hasLength(2));
    expect(reopened.find(output.file.id)?.sourceId, source.id);
    expect(await reopened.loadBytes(reopened.find(source.id)!), original.bytes);
    expect(await reopened.loadBytes(reopened.find(output.file.id)!), edited.bytes);
  });

  test('trash restores before seven days and expires at seven days', () async {
    final file = (await archive.save(example())).file;
    await archive.moveToTrash([file.id]);

    now = now.add(const Duration(days: 7, seconds: -1));
    final reopened = PicdoriArchive(root: root, now: () => now);
    await reopened.initialize();
    expect(reopened.trash.single.id, file.id);
    await reopened.restore([file.id]);
    expect(reopened.active.single.id, file.id);
    expect(await reopened.loadBytes(file), example().bytes);

    await reopened.moveToTrash([file.id]);
    now = now.add(const Duration(days: 7));
    await expectLater(reopened.restore([file.id]), throwsStateError);
    expect(reopened.trash, isEmpty);
    expect(reopened.active, isEmpty);
    expect(await File(file.path).exists(), isFalse);

    final afterExpiry = PicdoriArchive(root: root, now: () => now);
    await afterExpiry.initialize();
    expect(afterExpiry.find(file.id), isNull);
  });

  test('overlapping saves reuse content and keep both work records', () async {
    final results = await Future.wait([
      archive.save(example()),
      archive.save(example()),
    ]);
    expect(results.first.reused, isFalse);
    expect(results.last.reused, isTrue);
    expect(results.last.file.id, results.first.file.id);
    expect(archive.active, hasLength(1));
    expect(archive.recent, hasLength(2));
  });

  test('history deletion never deletes the archived output', () async {
    final file = (await archive.save(example())).file;
    final history = archive.recent.single;
    await archive.deleteHistory(history.id);
    expect(archive.recent, isEmpty);
    expect(archive.active.single.id, file.id);
    expect(await File(file.path).exists(), isTrue);
  });

  test('same content in trash is not silently restored', () async {
    final first = (await archive.save(example())).file;
    await archive.moveToTrash([first.id]);
    final second = await archive.save(example());
    expect(second.reused, isFalse);
    expect(archive.active, hasLength(1));
    expect(archive.trash, hasLength(1));
    await expectLater(archive.restore([first.id]), throwsStateError);
  });
}
