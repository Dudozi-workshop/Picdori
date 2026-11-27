import 'package:flutter/material.dart';
import 'package:picdori/main.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  testWidgets('first screen is a selectable tool home', (tester) async {
    await tester.pumpWidget(const PicdoriApp());
    expect(find.bySemanticsLabel('픽도리'), findsOneWidget);
    final navigation = tester.widget<NavigationBar>(find.byType(NavigationBar));
    expect(navigation.destinations, hasLength(4));
    expect(navigation.selectedIndex, 0);
    expect(find.byKey(const ValueKey('picdori-header-settings')), findsOneWidget);
    expect(find.text('사진 선택하기'), findsNothing);
  });

  testWidgets('film artwork leaves room for tool names at large text on a narrow phone', (tester) async {
    tester.view.physicalSize = const Size(320, 568);
    tester.view.devicePixelRatio = 1;
    tester.platformDispatcher.textScaleFactorTestValue = 1.6;
    addTearDown(() {
      tester.view.resetPhysicalSize();
      tester.view.resetDevicePixelRatio();
      tester.platformDispatcher.clearTextScaleFactorTestValue();
    });
    await tester.pumpWidget(const PicdoriApp());
    for (final tool in const {
      'size': '사진 크기 조정',
      'compress': '용량 줄이기',
      'format': '형식 바꾸기',
      'all': '한 번에 맞추기',
    }.entries) {
      final card = find.byKey(ValueKey('picdori-home-${tool.key}'));
      await tester.ensureVisible(card);
      final label = find.descendant(of: card, matching: find.text(tool.value));
      final art = find.descendant(of: card, matching: find.byType(Image));
      final titleBounds = tester.getRect(label);
      final artBounds = tester.getRect(art);
      expect(titleBounds.right, lessThanOrEqualTo(artBounds.left));
      expect(artBounds.right, lessThanOrEqualTo(tester.getRect(card).right));
    }
    expect(tester.takeException(), isNull);
  });

  testWidgets('both settings entry points open settings at 320px', (tester) async {
    tester.view.physicalSize = const Size(320, 568);
    tester.view.devicePixelRatio = 1;
    addTearDown(() {
      tester.view.resetPhysicalSize();
      tester.view.resetDevicePixelRatio();
    });

    await tester.pumpWidget(const PicdoriApp());
    final gear = find.byKey(const ValueKey('picdori-header-settings'));
    final gearIcon = find.descendant(of: gear, matching: find.byType(Icon));
    expect(tester.widget<Icon>(gearIcon).size, 19);
    await tester.tap(gear);
    await tester.pumpAndSettle();
    expect(find.text('자동 보관'), findsOneWidget);

    await tester.tap(find.text('홈'));
    await tester.pumpAndSettle();
    expect(gear, findsOneWidget);
    await tester.tap(find.descendant(
      of: find.byType(NavigationBar),
      matching: find.byIcon(Icons.settings_outlined),
    ));
    await tester.pumpAndSettle();
    expect(find.text('자동 보관'), findsOneWidget);
    final navigation = tester.widget<NavigationBar>(find.byType(NavigationBar));
    expect(navigation.selectedIndex, 3);
    expect(tester.takeException(), isNull);
  });
}
