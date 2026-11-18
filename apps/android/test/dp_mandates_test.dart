import 'package:couple_app/src/services/cloud_session.dart';
import 'package:couple_app/src/ui/dp_mandates.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';

const _message = <String, dynamic>{
  'id': 'source',
  'role': 'user',
  'owner': 'a',
  'text': '下次一起挑电影，接着看上次那部',
};

class _Fixture extends CloudSession {
  final writes = <Json>[];
  bool reject = false;
  _Fixture() {
    state = {
      'user': {'id': 'b'},
      'mandates': <Json>[],
    };
  }
  @override
  Future<dynamic> mutate(String method, String path, [Json? body]) async {
    if (reject) throw const CloudError('服务暂不可用，请重试。');
    final data = body!;
    writes.add(data);
    if (method == 'POST' && path == '/v1/mandates') {
      state['mandates'] = <Json>[
        {
          ...data,
          'id': 'mandate',
          'source_owner': 'a',
          'source_at': 1800000000,
          'owner': 'b',
          'status': 'active',
          'version': 1,
        },
      ];
    } else {
      expect(method, 'PUT');
      expect(path, '/v1/mandates/mandate');
      final row = rows('mandates').single;
      expect(data['version'], row['version']);
      row['status'] = data['status'];
      row['version']++;
    }
    notifyListeners();
    return {'ok': true};
  }
}

void main() {
  testWidgets(
    'shared message reviewed before save, partner attribution, status and retry',
    (t) async {
      t.view.devicePixelRatio = 1;
      t.view.physicalSize = const Size(360, 800);
      addTearDown(t.view.resetPhysicalSize);
      addTearDown(t.view.resetDevicePixelRatio);
      final session = _Fixture();
      await t.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: ListenableBuilder(
              listenable: session,
              builder: (context, _) => Column(
                children: [
                  MandateInboxButton(session: session),
                  MandateFromMessage(session: session, message: _message),
                  MandateFromMessage(
                    session: session,
                    message: {..._message, 'role': 'assistant'},
                  ),
                ],
              ),
            ),
          ),
        ),
      );
      Future<void> tap(String label) async {
        final f = find.text(label);
        await t.ensureVisible(f);
        await t.tap(f);
        await t.pumpAndSettle();
      }

      expect(find.text('设为委托'), findsOneWidget);
      await tap('设为委托');
      expect(find.text('一起挑电影'), findsOneWidget);
      expect(find.text('接着看上次那部'), findsOneWidget);
      expect(find.text('来自共同群 · 伴侣'), findsOneWidget);
      await t.pageBack();
      await t.pumpAndSettle();
      expect(session.writes, isEmpty);
      await tap('设为委托');
      await t.enterText(find.byType(TextFormField).last, '续看第二集');
      session.reject = true;
      await tap('确认保存共同委托');
      expect(find.text('服务暂不可用，请重试。'), findsOneWidget);
      expect(session.writes, isEmpty);
      session.reject = false;
      await tap('确认保存共同委托');
      expect(session.writes.single, {
        'source_id': 'source',
        'source_text': _message['text'],
        'task': '续看第二集',
        'cue': '一起挑电影',
      });
      await tap('查看共同委托');
      await tap('续看第二集');
      expect(find.text('由我保存 · 来自共同群'), findsOneWidget);
      expect(find.textContaining('伴侣 · '), findsOneWidget);
      await tap('暂缓');
      expect(find.textContaining('已暂缓'), findsOneWidget);
      await tap('恢复提醒');
      await tap('取消委托');
      await tap('返回');
      expect(session.writes.length, 3);
      await tap('完成');
      await tap('确认');
      expect(session.writes.last['status'], 'completed');
      expect(find.text('取消委托'), findsNothing);
      await t.pageBack();
      await t.pumpAndSettle();
      await tap('共同委托');
      expect(find.textContaining('已完成'), findsOneWidget);
      expect(t.takeException(), isNull);
      await t.pumpWidget(const SizedBox.shrink());
      session.dispose();
    },
  );
}
