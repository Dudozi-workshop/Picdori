import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:picdori/ui/library_pages.dart';

void main() {
  for (final outcome in ['opened', 'unavailable', 'platform error']) {
    testWidgets('settings feedback mail: $outcome', (tester) async {
      Uri? draft;
      String? copiedAddress;
      final messenger = TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
      messenger.setMockMethodCallHandler(SystemChannels.platform, (call) async {
        if (call.method == 'Clipboard.setData') {
          copiedAddress = (call.arguments as Map)['text'] as String;
        }
        return null;
      });
      addTearDown(() => messenger.setMockMethodCallHandler(SystemChannels.platform, null));
      await tester.pumpWidget(MaterialApp(home: Scaffold(
        body: PicdoriSettingsView(onStorage: () {}, onTrash: () {},
          openMail: (uri) async {
            draft = uri;
            if (outcome == 'platform error') throw PlatformException(code: 'launch');
            return outcome == 'opened';
          }),
      )));
      final feedback = find.text('의견 보내기');
      await tester.ensureVisible(feedback);
      await tester.tap(feedback);
      await tester.pumpAndSettle();
      expect(draft?.scheme, 'mailto');
      expect(draft?.path, 'dudoziworkshop@gmail.com');
      expect(draft?.queryParameters, {'subject': '[픽도리] 의견 보내기'});
      if (outcome == 'opened') {
        expect(find.byType(AlertDialog), findsNothing);
      } else {
        expect(find.text('dudoziworkshop@gmail.com'), findsOneWidget);
        await tester.tap(find.text('주소 복사'));
        await tester.pumpAndSettle();
        expect(copiedAddress, 'dudoziworkshop@gmail.com');
        expect(find.byType(AlertDialog), findsNothing);
        expect(find.text('문의 이메일 주소를 복사했어요.'), findsOneWidget);
      }
    });
  }
}
