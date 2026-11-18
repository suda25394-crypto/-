import 'package:couple_app/src/services/cloud_session.dart';
import 'package:couple_app/src/ui/dp_game.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';

class GameSession extends CloudSession {
  GameSession(this.role) {
    state = {
      'modules': [
        {'id': 'm', 'module': 'memory', 'title': '河边选书'},
      ],
      'games': <Json>[],
    };
  }
  final String role;
  final paths = <String>[];

  @override
  Future<dynamic> mutate(String method, String path, [Json? body]) async {
    paths.add(path);
    if (path == '/v1/games') {
      expect(body!['source_ids'], ['m']);
      expect(body['request_id'], isNotEmpty);
      final game = <String, dynamic>{
        'id': 'g',
        'role': role,
        'my_choices': <int?>[null, null, null],
        'version': 0,
        'my_locked': false,
        'other_locked': true,
        'my_consent': false,
        'other_consent': true,
        'questions': List.generate(
          3,
          (i) => {
            'prompt': '问题$i',
            'options': ['选项$i-A', '选项$i-B', '选项$i-C'],
            'anchor': '河边选书',
          },
        ),
      };
      (state['games'] as List).add(game);
    } else {
      final game = rows('games').single;
      if (path.endsWith('/choices') || path.endsWith('/lock')) {
        expect(body!['version'], game['version']);
        game['my_choices'] = body['choices'];
        game['version']++;
        game['my_locked'] = path.endsWith('/lock');
      } else if (path.endsWith('/reveal')) {
        game['result'] = {
          'answers': [0, 1, 2],
          'guesses': [0, 0, 2],
          'score': 2,
        };
      } else {
        fail('Unexpected route $path');
      }
    }
    notifyListeners();
    return rows('games').single;
  }
}

void main() {
  for (final (role, width, height) in [
    ('answer', 360.0, 800.0),
    ('guess', 390.0, 844.0),
  ]) {
    testWidgets(
      'game $role taps three questions, resumes and reveals on $width',
      (t) async {
        t.view.devicePixelRatio = 1;
        t.view.physicalSize = Size(width, height);
        addTearDown(t.view.resetDevicePixelRatio);
        addTearDown(t.view.resetPhysicalSize);
        final session = GameSession(role);
        addTearDown(session.dispose);
        await t.pumpWidget(MaterialApp(home: DpGameScreen(session: session)));
        Future<void> tap(String text) async {
          final f = find.text(text);
          await t.ensureVisible(f);
          await t.tap(f);
          await t.pumpAndSettle();
        }

        if (role == 'answer') {
          await tap('河边选书');
          await tap('生成三道题');
        } else {
          await session.mutate('POST', '/v1/games', {
            'source_ids': ['m'],
            'request_id': 'other-player-generated',
          });
          await t.pumpAndSettle();
          await tap('我来猜 · 继续');
        }
        expect(
          find.text(role == 'answer' ? '你来作答' : '猜猜对方会怎么选'),
          findsOneWidget,
        );
        await tap('选项0-A');
        await t.pageBack();
        await t.pumpAndSettle();
        await tap(role == 'answer' ? '我作答 · 继续' : '我来猜 · 继续');
        expect(
          t
              .widget<ChoiceChip>(
                find.ancestor(
                  of: find.text('选项0-A'),
                  matching: find.byType(ChoiceChip),
                ),
              )
              .selected,
          isTrue,
        );
        await tap('选项1-B');
        await tap('选项2-C');
        await tap('确认提交三个选择');
        expect(find.textContaining('本人选择 ·'), findsNothing);
        await tap('同意一起揭晓');
        expect(find.text('猜中了 2 / 3 题'), findsOneWidget);
        expect(session.paths.where((p) => p.endsWith('/choices')).length, 3);
        expect(t.takeException(), isNull);
      },
    );
  }
}
