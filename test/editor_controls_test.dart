import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:image/image.dart' as img;
import 'package:picdori/main.dart';
import 'package:picdori/core/image_processor.dart';
import 'package:picdori/ui/picdori_bento.dart';

Uint8List photo([int w = 120, int h = 90]) {
  final image = img.Image(width: w, height: h);
  img.fill(image, color: img.ColorRgb8(40, 140, 200));
  return Uint8List.fromList(img.encodePng(image));
}

Widget fixture({int width = 120, int height = 90}) => MaterialApp(
  home: EditorPage(
    initialSource: photo(width, height),
    initialWidth: width,
    initialHeight: height,
  ),
);

void main() {
  testWidgets('home is a warm-cream bento tool picker', (tester) async {
    await tester.pumpWidget(fixture());
    await tester.binding.handlePopRoute();
    await tester.pumpAndSettle();
    for (final key in [
      'picdori-home-size',
      'picdori-home-compress',
      'picdori-home-format',
      'picdori-home-all',
    ]) {
      expect(find.byKey(ValueKey(key)), findsOneWidget);
    }
    expect(find.byKey(const ValueKey('picdori-brand-mark')),
        findsOneWidget);
    expect(find.text('사진 선택하기'), findsNothing);
    await tester.tap(find.byKey(const ValueKey('picdori-home-size')));
    await tester.pumpAndSettle();
    expect(find.text('사진 크기 맞추기'), findsOneWidget);
    expect(find.byKey(const ValueKey('picdori-preview-canvas')), findsOneWidget);
    expect(find.text('목표 파일 용량'), findsNothing);
    expect(tester.takeException(), isNull);
  });

  testWidgets('compact 320px home cards remain usable', (tester) async {
    tester.view.physicalSize = const Size(320, 568);
    tester.view.devicePixelRatio = 1;
    addTearDown(() {
      tester.view.resetPhysicalSize();
      tester.view.resetDevicePixelRatio();
    });
    await tester.pumpWidget(fixture());
    await tester.binding.handlePopRoute();
    await tester.pumpAndSettle();
    await tester.ensureVisible(find.byKey(const ValueKey('picdori-home-all')));
    await tester.tap(find.byKey(const ValueKey('picdori-home-all')));
    await tester.pumpAndSettle();
    expect(find.text('한 번에 맞추기'), findsOneWidget);
    expect(find.byKey(const ValueKey('picdori-preview-canvas')), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('Android back returns from editor to tool home', (tester) async {
    await tester.pumpWidget(fixture());
    await tester.binding.handlePopRoute();
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey('picdori-home-format')));
    await tester.pumpAndSettle();
    expect(find.text('파일 형식 바꾸기'), findsOneWidget);

    // Root-level editor is a logical screen, not a new Navigator route.
    await tester.binding.handlePopRoute();
    await tester.pumpAndSettle();
    expect(find.byKey(const ValueKey('picdori-home-size')),
        findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('result recovery has inline retry without losing finished photo',
      (tester) async {
    final original = photo(120, 90);
    await tester.pumpWidget(MaterialApp(
      home: EditorPage(
        initialSource: original,
        initialWidth: 120,
        initialHeight: 90,
        initialResult: ImageResult(
          bytes: original,
          width: 120,
          height: 90,
          format: OutputFormat.png,
        ),
        initialSaveFailure: '사진첩 접근 권한을 확인해 주세요.',
      ),
    ));
    expect(find.text('사진이 완성됐어요'), findsOneWidget);
    expect(find.byKey(const ValueKey('picdori-save-failure')),
        findsOneWidget);
    expect(find.byKey(const ValueKey('picdori-retry-save')),
        findsOneWidget);
    final action = tester.widget<OutlinedButton>(
        find.byKey(const ValueKey('picdori-retry-save')));
    expect(action.onPressed, isNotNull);
    expect(find.byKey(const ValueKey('picdori-new-photo')),
        findsOneWidget);
    expect(find.text('120 × 90px'), findsWidgets);
    expect(find.text('규격 검증 완료 · 용량 변화 없음'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('compact result screen keeps both save options reachable',
      (tester) async {
    tester.view.physicalSize = const Size(320, 568);
    tester.view.devicePixelRatio = 1;
    addTearDown(() {
      tester.view.resetPhysicalSize();
      tester.view.resetDevicePixelRatio();
    });
    final original = photo(120, 90);
    await tester.pumpWidget(MaterialApp(
      home: EditorPage(
        initialSource: original,
        initialWidth: 120,
        initialHeight: 90,
        initialResult: ImageResult(
          bytes: original,
          width: 120,
          height: 90,
          format: OutputFormat.png,
        ),
        initialSaveFailure: '저장 경로를 확인한 후 다시 시도해 주세요.',
      ),
    ));
    expect(find.byKey(const ValueKey('picdori-save-gallery')),
        findsOneWidget);
    expect(find.byKey(const ValueKey('picdori-save-file')),
        findsOneWidget);
    expect(find.byKey(const ValueKey('picdori-retry-save')),
        findsOneWidget);
    await tester.ensureVisible(find.byKey(const ValueKey('picdori-new-photo')));
    await tester.pump();
    expect(tester.takeException(), isNull);
  });

  testWidgets('editor restores its four tabs after the keyboard closes',
      (tester) async {
    addTearDown(tester.view.resetViewInsets);
    await tester.pumpWidget(fixture());
    expect(find.byType(NavigationBar), findsOneWidget);

    tester.view.viewInsets = const FakeViewPadding(bottom: 240);
    await tester.pump();
    expect(find.byType(NavigationBar), findsNothing);
    expect(tester.takeException(), isNull);

    tester.view.resetViewInsets();
    await tester.pumpAndSettle();
    final navigation = tester.widget<NavigationBar>(find.byType(NavigationBar));
    expect(navigation.destinations, hasLength(4));
    expect(tester.takeException(), isNull);
  });

  testWidgets('large accessibility text keeps bento home usable',
      (tester) async {
    tester.view.physicalSize = const Size(320, 640);
    tester.view.devicePixelRatio = 1;
    addTearDown(() {
      tester.view.resetPhysicalSize();
      tester.view.resetDevicePixelRatio();
    });
    await tester.pumpWidget(MaterialApp(
      home: MediaQuery(
        data: const MediaQueryData(
          size: Size(320, 640),
          textScaler: TextScaler.linear(1.4),
        ),
        child: Scaffold(
          body: SingleChildScrollView(
            child: PicdoriBentoHome(onSelect: (_) {}),
          ),
        ),
      ),
    ));
    await tester.ensureVisible(find.byKey(const ValueKey('picdori-home-all')));
    await tester.pump();
    expect(tester.takeException(), isNull);
  });

  testWidgets('all-in-one editor shows one setting category at a time',
      (tester) async {
    await tester.pumpWidget(fixture());
    expect(find.text('한 번에 맞추기'), findsOneWidget);
    expect(find.byKey(const ValueKey('picdori-all-tabs')), findsOneWidget);
    expect(find.text('사진 크기 설정'), findsOneWidget);
    expect(find.text('목표 파일 용량'), findsNothing);
    await tester.tap(find.text('용량'));
    await tester.pumpAndSettle();
    expect(find.text('목표 파일 용량'), findsOneWidget);
    expect(find.text('사진 크기 설정'), findsNothing);
    await tester.tap(find.text('형식'));
    await tester.pumpAndSettle();
    expect(find.text('저장할 파일 형식'), findsOneWidget);
    expect(find.text('목표 파일 용량'), findsNothing);
    expect(tester.takeException(), isNull);
  });

  testWidgets('ratio selection changes canvas, crop keeps full editor',
      (tester) async {
    await tester.pumpWidget(fixture());
    await tester.ensureVisible(find.text('1:1'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('1:1'));
    await tester.pumpAndSettle();
    expect(tester.widget<AspectRatio>(
      find.byKey(const ValueKey('picdori-preview-canvas')),
    ).aspectRatio, 1);
    await tester.ensureVisible(find.text('잘라서 채우기'));
    await tester.tap(find.text('잘라서 채우기'));
    await tester.pumpAndSettle();
    final cropButton = find.widgetWithText(
        OutlinedButton, '자르기 위치 조절');
    await tester.ensureVisible(cropButton);
    await tester.tap(cropButton);
    await tester.pumpAndSettle();
    expect(find.text('이 위치로 자르기'), findsOneWidget);
    expect(find.text('사진을 움직여 남길 영역을 정하고, 두 손가락으로 확대할 수 있어요.'),
        findsOneWidget);
    await tester.pageBack();
    await tester.pumpAndSettle();
    expect(find.text('사진 만들기'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('pixel input is separated into its own tab',
      (tester) async {
    await tester.pumpWidget(fixture());
    expect(find.text('가로 px'), findsNothing);
    await tester.ensureVisible(find.text('픽셀 직접 입력'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('픽셀 직접 입력'));
    await tester.pumpAndSettle();
    final width = find.byKey(const ValueKey('picdori-width'));
    await tester.enterText(width, '60');
    await tester.pump();
    expect(tester.widget<TextField>(
      find.byKey(const ValueKey('picdori-height')),
    ).controller!.text, '45');
    await tester.enterText(width, '0');
    await tester.pump();
    expect(find.text('가로·세로 픽셀은 1 이상의 숫자로 입력해 주세요.'),
        findsOneWidget);
    final action = tester.widget<FilledButton>(
      find.byKey(const ValueKey('picdori-make')),
    );
    expect(action.onPressed, isNull);
  });

  testWidgets('from photo mode, other settings are available on request',
      (tester) async {
    await tester.pumpWidget(fixture());
    await tester.tap(find.text('용량'));
    await tester.pumpAndSettle();
    await tester.ensureVisible(find.text('500KB'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('500KB'));
    await tester.pump();
    final summary = find.byKey(const ValueKey('picdori-output-summary'));
    expect(tester.widget<Text>(summary).data, '120 × 90px · JPG · 500 KB 이하');
    expect(find.text('목표 파일 용량'), findsOneWidget);
    expect(find.text('사진 크기 설정'), findsNothing);
    expect(tester.takeException(), isNull);
  });

  testWidgets('file format editor offers interactive JPG/PNG tiles',
      (tester) async {
    await tester.pumpWidget(fixture());
    await tester.tap(find.text('형식'));
    await tester.pumpAndSettle();
    expect(find.byKey(const ValueKey('picdori-format-jpg')), findsOneWidget);
    expect(find.byKey(const ValueKey('picdori-format-png')), findsOneWidget);
    await tester.ensureVisible(find.byKey(const ValueKey('picdori-format-png')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey('picdori-format-png')));
    await tester.pump();
    final summary = find.byKey(const ValueKey('picdori-output-summary'));
    expect(tester.widget<Text>(summary).data, '120 × 90px · PNG · 용량 제한 없음');
    expect(tester.takeException(), isNull);
  });
}
