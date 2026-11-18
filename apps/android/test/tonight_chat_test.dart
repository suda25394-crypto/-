import 'package:couple_app/src/services/cloud_session.dart';
import 'package:couple_app/src/ui/cloud_chat.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';

class _ChatFixture extends CloudSession {
  _ChatFixture() {
    resetUser('a');
  }

  void resetUser(String id) {
    state = <String, dynamic>{
      'user': {'id': id},
      'mode': 'fixture',
      'messages': <String, dynamic>{'shared': <Json>[], 'private': <Json>[]},
    };
    notifyListeners();
  }

  final sent = <Json>[];
  bool uncertain = false;
  int reads = 0;
  @override
  Future<void> refresh() async {
    reads++;
  }

  @override
  Future<dynamic> mutate(String method, String path, [Json? body]) async {
    expect(path, '/v1/messages');
    sent.add({...body!});
    if (uncertain) {
      // Production mutate reconciles a conflict before returning the error.
      await refresh();
      throw const CloudError('结果待核对。', 409, 'outcome_unknown');
    }
    final scope = body['scope'] as String;
    final text = body['text'] as String;
    final callsModel = scope == 'private' || text.contains('@DP');
    final rows = state['messages'][scope] as List<Json>;
    rows.add({
      'id': 'user-${sent.length}',
      'role': 'user',
      'text': text,
      'owner': user['id'],
    });
    if (callsModel) {
      rows.add({
        'id': 'dp-${sent.length}',
        'role': 'assistant',
        'text': '合成回复',
        'owner': user['id'],
      });
    }
    notifyListeners();
    return <String, dynamic>{
      'receipt': <String, dynamic>{
        'called': callsModel,
        'mode': 'fixture',
        'outcome': 'ok',
        'requested_model': 'synthetic',
        'reported_model': 'synthetic',
        'in_tokens': 5,
        'out_tokens': 2,
        'at': 1700000000,
      },
    };
  }
}

void main() {
  for (final width in [320.0, 390.0]) {
    testWidgets(
      'white-purple group composer, keyboard and scoped history at $width',
      (t) async {
        final s = _ChatFixture();
        addTearDown(s.dispose);
        t.view.physicalSize = Size(width, 800);
        t.view.devicePixelRatio = 1;
        addTearDown(t.view.resetPhysicalSize);
        addTearDown(t.view.resetDevicePixelRatio);
        addTearDown(t.view.resetViewInsets);
        String? selected;
        Future<void> show(String scope) => t.pumpWidget(
          MaterialApp(
            builder: (context, child) => MediaQuery(
              data: MediaQuery.of(context)
                  .copyWith(textScaler: TextScaler.linear(1.6)),
              child: child!,
            ),
            home: Scaffold(
              body: CloudChat(
                session: s,
                scope: scope,
                openRecords: () {},
                openPlan: (id) => selected = id,
              ),
            ),
          ),
        );
        Future<void> tap(Finder finder) async {
          await t.pump();
          await t.ensureVisible(finder);
          await t.tap(finder);
          await t.pumpAndSettle();
        }

        final group = find.byKey(const Key('cloud-shared-input'));
        final private = find.byKey(const Key('cloud-private-input'));
        final send = find.byKey(const Key('chat-send'));
        final more = find.byKey(const Key('chat-more'));
        final plan = find.byKey(const Key('chat-plan'));
        await show('shared');
        expect(find.text('给共同空间写下第一条消息。'), findsOneWidget);
        expect(plan, findsNothing);
        expect(t.widget<IconButton>(send).onPressed, isNull);
        t.view.viewInsets = const FakeViewPadding(bottom: 292);
        await t.pump();
        await t.enterText(group, '联调准备好了');
        await tap(send);
        expect(s.sent.single['text'], '联调准备好了');
        expect(find.text('合成回复'), findsNothing);
        await tap(more);
        await tap(find.text('调用回执'));
        expect(find.text('服务端未发起模型调用。'), findsOneWidget);
        await tap(find.text('关闭'));

        await t.enterText(group, '@AI 旧称');
        await tap(send);
        expect(s.sent.length, 1);
        expect(find.textContaining('要邀请 DP 请用 @DP'), findsOneWidget);
        await t.enterText(group, '一天有几个小时？');
        await tap(more);
        await tap(find.text('@DP'));
        expect(t.widget<TextField>(group).controller!.text, '@DP 一天有几个小时？');
        expect(s.sent.length, 1);
        await tap(send);
        expect(s.sent.length, 2);
        expect(find.text('合成回复'), findsOneWidget);
        expect(t.takeException(), isNull);
        t.view.resetViewInsets();
        await t.pump();
        await tap(more);
        await tap(find.text('调用回执'));
        expect(find.textContaining('输入 5 · 输出 2'), findsOneWidget);
        await tap(find.text('关闭'));
        final modules = <Json>[
          {'id': 'p1', 'module': 'calendar', 'title': '一起散步', 'version': 2},
        ];
        s.state['modules'] = modules;
        await show('shared');
        await tap(plan);
        expect(selected, 'p1');
        await show('private');
        expect(plan, findsNothing);
        expect(find.text('合成回复'), findsNothing);
        await t.enterText(private, '私人的输入草稿');
        s.resetUser('b');
        await t.pump();
        expect(t.widget<TextField>(private).controller!.text, isEmpty);
        await show('shared');
        expect(find.text('私人的输入草稿'), findsNothing);
        expect(plan, findsNothing);
        expect(t.takeException(), isNull);
      },
    );
  }

  testWidgets('when a model outcome is unknown only recheck status', (t) async {
    final s = _ChatFixture()..uncertain = true;
    addTearDown(s.dispose);
    await t.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: CloudChat(session: s, scope: 'private', openRecords: () {}),
        ),
      ),
    );
    await t.enterText(find.byKey(const Key('cloud-private-input')), '测试句');
    final send = find.byKey(const Key('chat-send'));
    await t.pump();
    await t.tap(send);
    await t.pumpAndSettle();
    expect(s.sent.length, 1);
    expect(find.byTooltip('核对结果'), findsOneWidget);
    await t.tap(send);
    await t.pumpAndSettle();
    expect(s.sent.length, 1);
    expect(s.reads, 2);
    expect(find.textContaining('未再次请求模型'), findsOneWidget);
  });
}
