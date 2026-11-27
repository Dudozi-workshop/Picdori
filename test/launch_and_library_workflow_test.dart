import 'dart:io';
import 'dart:typed_data';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:image/image.dart' as img;
import 'package:image_picker_platform_interface/image_picker_platform_interface.dart';
import 'package:path_provider_platform_interface/path_provider_platform_interface.dart';
import 'package:picdori/core/image_processor.dart';
import 'package:picdori/main.dart';
import 'package:picdori/ui/management_pages.dart';
import 'package:picdori/services/picdori_archive.dart';

class _Picker extends ImagePickerPlatform {
  _Picker(this.photo);

  final XFile photo;
  bool hasLostPhoto = false;
  bool cancelPick = false;
  int pickCount = 0;

  @override
  Future<XFile?> getImageFromSource({
    required ImageSource source,
    ImagePickerOptions options = const ImagePickerOptions(),
  }) async {
    pickCount++;
    return cancelPick ? null : photo;
  }

  @override
  Future<LostDataResponse> getLostData() async => hasLostPhoto
      ? LostDataResponse(files: [photo])
      : LostDataResponse.empty();
}

class _Paths extends PathProviderPlatform {
  _Paths(this.directory);

  final Directory directory;

  @override
  Future<String?> getApplicationSupportPath() async => directory.path;
}

Future<void> _waitFor(WidgetTester tester, Finder finder) async {
  for (var attempt = 0; attempt < 100 && finder.evaluate().isEmpty; attempt++) {
    await tester.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 20)));
    await tester.pump();
  }
  expect(finder, findsOneWidget);
}

void main() {
  late Directory directory;
  late _Picker picker;
  late PicdoriArchive archive;

  ImageResult photo() {
    final bytes = Uint8List.fromList(img.encodePng(img.Image(width: 40, height: 30)));
    return ImageResult(bytes: bytes, width: 40, height: 30, format: OutputFormat.png);
  }

  setUp(() async {
    directory = await Directory.systemTemp.createTemp('picdori_workflow_test_');
    final oldPicker = ImagePickerPlatform.instance;
    final oldPaths = PathProviderPlatform.instance;
    picker = _Picker(XFile.fromData(photo().bytes, name: 'sample.png'));
    ImagePickerPlatform.instance = picker;
    PathProviderPlatform.instance = _Paths(directory);
    addTearDown(() async {
      ImagePickerPlatform.instance = oldPicker;
      PathProviderPlatform.instance = oldPaths;
      await directory.delete(recursive: true);
    });
    archive = PicdoriArchive(root: directory);
    await archive.initialize();
  });

  testWidgets('one tap starts photo selection and cancel returns to the tools',
      (tester) async {
    picker.cancelPick = true;
    await tester.runAsync(() => tester.pumpWidget(const PicdoriApp()));
    final card = find.byKey(const ValueKey('picdori-home-compress'));
    await tester.ensureVisible(card);
    await tester.tap(card);
    await tester.pumpAndSettle();
    expect(picker.pickCount, 1);
    expect(card, findsOneWidget);

    picker.cancelPick = false;
    await tester.runAsync(() => tester.tap(card));
    await _waitFor(tester, find.text('500 KB 이하로 만들기'));
    expect(tester.widget<Text>(
      find.byKey(const ValueKey('picdori-output-summary')),
    ).data, '40 × 30px · PNG · 500 KB 이하');
    expect(picker.pickCount, 2);
    await tester.ensureVisible(find.text('200KB'));
    await tester.tap(find.text('200KB'));
    await tester.pump();
    expect(find.text('200 KB 이하로 만들기'), findsOneWidget);

    await tester.binding.handlePopRoute();
    await tester.pumpAndSettle();
    final format = find.byKey(const ValueKey('picdori-home-format'));
    await tester.ensureVisible(format);
    await tester.tap(format);
    await tester.pumpAndSettle();
    expect(picker.pickCount, 2);
    expect(find.text('JPG로 변환하기'), findsOneWidget);
    await tester.ensureVisible(find.byKey(const ValueKey('picdori-format-png')));
    await tester.tap(find.byKey(const ValueKey('picdori-format-png')));
    await tester.pump();
    expect(find.text('PNG로 변환하기'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('Android startup reopens the photo lost by the picker', (tester) async {
    debugDefaultTargetPlatformOverride = TargetPlatform.android;
    addTearDown(() => debugDefaultTargetPlatformOverride = null);
    picker.hasLostPhoto = true;
    await tester.runAsync(() => tester.pumpWidget(const PicdoriApp()));

    final photoPreview = find.byKey(const ValueKey('picdori-preview-canvas'));
    await _waitFor(tester, photoPreview);
    expect(find.text('한 번에 맞추기'), findsOneWidget);
    expect(find.textContaining('원본 40 × 30px'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('reusing history displays a custom maximum size', (tester) async {
    await tester.runAsync(() => archive.save(photo(), settings: {
      'width': 40,
      'height': 30,
      'format': 'PNG',
      'mode': 'fit',
      'maxBytes': 350000,
    }));
    await tester.runAsync(() => tester.pumpWidget(const PicdoriApp()));
    await tester.tap(find.byIcon(Icons.history_outlined));
    await tester.pump();

    final recent = find.text('40 × 30px · PNG');
    await _waitFor(tester, recent);
    await tester.runAsync(() => tester.tap(recent));
    await _waitFor(tester, find.byKey(const ValueKey('picdori-all-tabs')));

    final limitTab = find.descendant(
      of: find.byKey(const ValueKey('picdori-all-tabs')),
      matching: find.text('용량'),
    );
    await tester.tap(limitTab);
    await tester.pumpAndSettle();
    final field = tester.widget<TextField>(
      find.byKey(const ValueKey('picdori-custom-kb')),
    );
    expect(field.controller?.text, '350');
    expect(tester.takeException(), isNull);
  });

  test('trash labels cover the last hour and exact recovery deadline', () {
    expect(recoveryTimeLeft(const Duration(days: 3)), '3일 남음');
    expect(recoveryTimeLeft(const Duration(hours: 5)), '5시간 남음');
    expect(recoveryTimeLeft(const Duration(seconds: 1)), '1시간 미만');
    expect(recoveryTimeLeft(Duration.zero), '복구 기한 만료');
  });

  testWidgets('resetting a search and format filter opens the stored export',
      (tester) async {
    tester.view.physicalSize = const Size(430, 900);
    tester.view.devicePixelRatio = 1;
    addTearDown(() {
      tester.view.resetPhysicalSize();
      tester.view.resetDevicePixelRatio();
    });
    final saved = await tester.runAsync(() => archive.save(photo()));
    final name = saved!.file.name;
    await tester.runAsync(() => tester.pumpWidget(const PicdoriApp()));
    await tester.tap(find.byIcon(Icons.folder_outlined));
    await tester.pump();
    await _waitFor(tester, find.text(name));
    final search = find.byKey(const ValueKey('picdori-file-search'));
    await tester.tap(find.widgetWithText(ChoiceChip, 'JPG'));
    await tester.enterText(search, 'no-match');
    await tester.testTextInput.receiveAction(TextInputAction.done);
    await tester.pumpAndSettle();
    expect(find.text('조건에 맞는 사진이 없어요.'), findsOneWidget);
    await tester.tap(find.text('검색·필터 초기화'));
    await tester.pumpAndSettle();
    expect(tester.widget<TextField>(search).controller!.text, isEmpty);
    await tester.tap(find.text(name));
    await tester.pumpAndSettle();
    expect(find.text('기존 파일은 그대로 보관돼요.'), findsOneWidget);
    await tester.runAsync(() => tester.tap(find.text('저장·공유하기')));
    await _waitFor(tester, find.byKey(const ValueKey('picdori-save-gallery')));
    expect(find.text(name), findsOneWidget);
    expect(find.text('사진이 완성됐어요'), findsNothing);
    expect(find.text('설정 다시 하기'), findsNothing);
    await tester.binding.handlePopRoute();
    await tester.pumpAndSettle();
    expect(find.text('파일 상세'), findsOneWidget);
  });

  testWidgets('filtered out selections are disclosed and cancel keeps them',
      (tester) async {
    tester.view.physicalSize = const Size(430, 900);
    tester.view.devicePixelRatio = 1;
    addTearDown(() {
      tester.view.resetPhysicalSize();
      tester.view.resetDevicePixelRatio();
    });
    await tester.runAsync(() => archive.save(photo()));
    await tester.runAsync(() => tester.pumpWidget(const PicdoriApp()));
    await tester.tap(find.byIcon(Icons.folder_outlined));
    await tester.pump();
    final select = find.text('선택');
    await _waitFor(tester, select);
    await tester.tap(select);
    await tester.pumpAndSettle();
    final selectAll = find.text('현재 결과 전체 선택');
    await tester.ensureVisible(selectAll);
    await tester.tap(selectAll);
    await tester.pump();

    final search = find.byKey(const ValueKey('picdori-file-search'));
    await tester.ensureVisible(search);
    await tester.enterText(search, 'no match');
    await tester.testTextInput.receiveAction(TextInputAction.done);
    await tester.pumpAndSettle();
    final delete = find.text('1개 최근 삭제로 이동');
    await tester.ensureVisible(delete);
    await tester.tap(delete);
    await tester.pumpAndSettle();
    expect(find.textContaining('보이지 않는 파일 1개'), findsOneWidget);
    await tester.tap(find.descendant(
      of: find.byType(AlertDialog),
      matching: find.text('취소'),
    ));
    await tester.pumpAndSettle();
    expect(delete, findsOneWidget);
    expect(tester.takeException(), isNull);
  });
}
