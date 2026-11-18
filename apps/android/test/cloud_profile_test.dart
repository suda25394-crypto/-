import 'package:couple_app/src/services/cloud_session.dart';
import 'package:couple_app/src/ui/cloud_profiles.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';

class _ProfileSession extends CloudSession {
  final writes = <Json>[];
  @override
  Future<dynamic> request(String method, String path, [Json? body]) async {
    writes.add({'method': method, 'path': path, 'body': body});
    return {'ok': true};
  }

  @override
  Future<void> refresh() async {}
}

void main() {
  testWidgets(
    'partner sees only published profile and new disclosures require preview',
    (tester) async {
      final session = _ProfileSession();
      addTearDown(session.dispose);
      session.state = {
        'user': {'id': 'a'},
        'profiles': [
          {
            'owner': 'b',
            'published': true,
            'data': {
              'life': {'interests': '骑车'},
            },
          },
        ],
      };
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(body: CloudProfilesScreen(session: session)),
        ),
      );
      await tester.tap(find.text('伴侣'));
      await tester.pumpAndSettle();
      expect(find.text('骑车'), findsOneWidget);
      expect(find.text('填写我的档案'), findsNothing);
      await tester.tap(find.text('我'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('填写我的档案'));
      await tester.pumpAndSettle();
      await tester.enterText(find.byKey(const Key('interests')), '看日出');
      await tester.testTextInput.receiveAction(TextInputAction.done);
      await tester.pumpAndSettle();
      final publish = find.widgetWithText(FilledButton, '预览并发布');
      await tester.scrollUntilVisible(
        publish,
        135,
        scrollable: find.byType(Scrollable).first,
      );
      await tester.pumpAndSettle();
      await tester.ensureVisible(publish);
      await tester.pumpAndSettle();
      await tester.tap(publish);
      await tester.pumpAndSettle();
      expect(find.text('发布给伴侣？'), findsOneWidget);
      expect(session.writes, isEmpty);
      await tester.tap(find.text('取消'));
      await tester.pumpAndSettle();
      await tester.ensureVisible(find.text('仅保存个人草稿'));
      await tester.tap(find.text('仅保存个人草稿'));
      await tester.pumpAndSettle();
      expect(session.writes.single['body']['published'], false);
      expect(session.writes.single['body']['data']['life']['interests'], '看日出');
    },
  );
}
