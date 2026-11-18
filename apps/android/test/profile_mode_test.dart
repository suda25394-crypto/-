import 'package:couple_app/src/services/cloud_session.dart';
import 'package:couple_app/src/ui/cloud_chat.dart';
import 'package:couple_app/src/ui/cloud_profiles.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';

class _GuidedSession extends CloudSession {
  final calls = <String>[];
  final questions = [
    {
      'id': 'respond',
      'text': '上一次感觉对方听懂你是什么时候？',
      'source': 'Arican-Dinc & Gable (2023)',
      'theme': '伴侣回应性',
      'doi': '10.1016/j.copsyc.2023.101652',
    },
    {
      'id': 'celebrate',
      'text': '你希望怎样分享好消息？',
      'source': 'Gable et al. (2004)',
      'theme': '分享积极事件',
      'doi': '10.1037/0022-3514.87.2.228',
    },
  ];
  _GuidedSession() {
    state = {
      'profile_mode': {'active': false, 'version': 0, 'question': null},
      'user': {'id': 'a'},
      'messages': {'private': <Json>[], 'shared': <Json>[]},
      'daily_portrait': {
        'as_of': '2026-11-18',
        'observations': [
          {'id': 'm1', 'text': '散步时喜欢听对方讲完再回应。'},
        ],
      },
    };
  }
  @override
  Future<dynamic> mutate(String method, String path, [Json? body]) async {
    calls.add(path);
    if (path == '/v1/messages') {
      expect(body!['scope'], 'private');
      (state['messages']['private'] as List<Json>).add({
        'role': 'user',
        'owner': 'a',
        'text': body['text'],
      });
    } else {
      final mode = state['profile_mode'] as Json;
      expect(body!['version'], mode['version']);
      final action = path.split('/').last;
      final active = action != 'end';
      state['profile_mode'] = {
        'active': active,
        'version': (mode['version'] as int) + 1,
        'question': active ? questions[action == 'skip' ? 1 : 0] : null,
      };
    }
    notifyListeners();
    return state['profile_mode'];
  }
}

void main() {
  testWidgets(
    'private chat starts, explains, skips, and ends guided conversation',
    (t) async {
      final s = _GuidedSession();
      addTearDown(s.dispose);
      Future<void> showChat(String scope) => t.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: CloudChat(session: s, scope: scope, openRecords: () {}),
          ),
        ),
      );
      await showChat('private');
      await t.tap(find.text('让 DP 了解我'));
      await t.pumpAndSettle();
      expect(find.text(s.questions.first['text']!), findsOneWidget);
      await t.tap(find.text('提问依据'));
      await t.pumpAndSettle();
      expect(
        find.textContaining('10.1016/j.copsyc.2023.101652'),
        findsOneWidget,
      );
      await t.tap(find.text('关闭'));
      await t.pumpAndSettle();
      await t.enterText(
        find.byKey(const Key('cloud-private-input')),
        '昨天她听我讲完了。',
      );
      await t.pump();
      await t.tap(find.byTooltip('发送'));
      await t.pumpAndSettle();
      expect(find.text('昨天她听我讲完了。'), findsOneWidget);
      await t.tap(find.text('换个话题'));
      await t.pumpAndSettle();
      expect(find.text(s.questions.last['text']!), findsOneWidget);
      await showChat('shared');
      expect(find.text(s.questions.last['text']!), findsNothing);
      expect(find.text('让 DP 了解我'), findsNothing);
      await showChat('private');
      await t.tap(find.text('结束了解'));
      await t.pumpAndSettle();
      await t.enterText(find.byKey(const Key('cloud-private-input')), '今晚吃什么？');
      await t.pump();
      await t.tap(find.byTooltip('发送'));
      await t.pumpAndSettle();
      expect(s.calls, [
        '/v1/profile-mode/start',
        '/v1/messages',
        '/v1/profile-mode/skip',
        '/v1/profile-mode/end',
        '/v1/messages',
      ]);
      expect(find.text('让 DP 了解我'), findsOneWidget);
    },
  );

  testWidgets('daily profile belongs to its owner and can open private chat', (
    t,
  ) async {
    final s = _GuidedSession();
    addTearDown(s.dispose);
    bool opened = false;
    await t.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: CloudProfilesScreen(
            session: s,
            openPrivateChat: () {
              opened = true;
            },
          ),
        ),
      ),
    );
    expect(find.text('我的每日档案'), findsOneWidget);
    expect(find.textContaining('2026-11-18'), findsOneWidget);
    expect(find.text('散步时喜欢听对方讲完再回应。'), findsOneWidget);
    expect(find.text('填写我的档案'), findsNothing);
    await t.tap(find.text('和 DP 聊聊我的档案'));
    expect(opened, isTrue);
    await t.tap(find.text('伴侣'));
    await t.pumpAndSettle();
    expect(find.text('我的每日档案'), findsNothing);
    expect(find.text('散步时喜欢听对方讲完再回应。'), findsNothing);
    expect(find.text('和 DP 聊聊我的档案'), findsNothing);
  });

  testWidgets('a day with only a new clue opens its private review controls', (
    t,
  ) async {
    final s = _GuidedSession();
    addTearDown(s.dispose);
    final candidate = {
      'id': 'm2',
      'owner': 'a',
      'scope': 'candidate',
      'text': '散心时更喜欢走走。',
      'version': 1,
    };
    s.state['daily_portrait'] = {
      'as_of': '2026-11-19',
      'observations': [],
      'pending': [candidate],
    };
    s.state['memories'] = [candidate];
    await t.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: CloudProfilesScreen(session: s, openPrivateChat: () {}),
        ),
      ),
    );
    expect(find.text('待我核对'), findsOneWidget);
    await t.tap(find.text('散心时更喜欢走走。'));
    await t.pumpAndSettle();
    expect(find.text('核对记忆'), findsOneWidget);
    expect(find.text('拒绝记住'), findsOneWidget);
    await t.pageBack();
    await t.pumpAndSettle();
    await t.tap(find.text('伴侣'));
    await t.pumpAndSettle();
    expect(find.text('待我核对'), findsNothing);
    expect(find.text('散心时更喜欢走走。'), findsNothing);
  });
}
