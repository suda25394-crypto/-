import 'package:couple_app/src/services/cloud_session.dart';
import 'package:couple_app/src/ui/dp_activity.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';

class _Session extends CloudSession {
  final calls = <String>[];
  late final Json item = {
    'module_id': 'date-01',
    'proposal_version': 1,
    'agreed': false,
    'votes': [
      {
        'owner': 'alice',
        'name': 'Alice',
        'version': 0,
        'choice': null,
        'note': '',
      },
      {'owner': 'bob', 'name': 'Bob', 'version': 0, 'choice': null, 'note': ''},
    ],
    'steps': <String, dynamic>{},
    'my_review_version': 0,
    'reviews': [],
  };
  _Session() {
    state = {
      'user': {'id': 'alice'},
      'activities': [item],
    };
  }
  @override
  Future<dynamic> mutate(String method, String path, [Json? body]) async {
    expect(body!['proposal_version'], 1);
    calls.add(path);
    if (path.endsWith('/vote')) {
      final vote = item['votes'][0];
      vote['choice'] = body['choice'];
      vote['note'] = body['note'];
      vote['version']++;
    } else if (path.contains('/steps/')) {
      item['steps'][path.split('/').last] = {'at': 50, 'version': 1};
    } else if (path.endsWith('/review')) {
      item['my_review_version']++;
      item['reviews'] = [
        <String, dynamic>{...body, 'owner': 'alice', 'name': 'Alice'},
      ];
    } else if (path.endsWith('/withdraw')) {
      item['my_review_version']++;
      item['reviews'] = [];
    } else {
      fail('Unexpected route $path');
    }
    notifyListeners();
    return {'ok': true};
  }
}

void main() {
  testWidgets(
    'each person votes, marks actual participation, saves or withdraws own feedback',
    (t) async {
      t.view.devicePixelRatio = 1;
      t.view.physicalSize = const Size(360, 800);
      addTearDown(t.view.resetPhysicalSize);
      addTearDown(t.view.resetDevicePixelRatio);
      final s = _Session();
      addTearDown(s.dispose);
      await t.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: ListView(
              padding: const EdgeInsets.all(16),
              children: [
                ActivityActions(
                  session: s,
                  record: const {'id': 'date-01', 'version': 1},
                ),
              ],
            ),
          ),
        ),
      );
      Future<void> tap(String text) async {
        final finder = find.text(text);
        await t.ensureVisible(finder);
        await t.tap(finder);
        await t.pumpAndSettle();
      }

      await tap('愿意');
      expect(find.text('我 · 愿意'), findsOneWidget);
      expect(find.text('Bob · 尚未表态'), findsOneWidget);
      expect(find.text('两人已定'), findsNothing);
      await tap('我的参与记录');
      await tap('已收藏');
      expect(find.text('记录我的实际体验'), findsNothing);
      await tap('实际参加过');
      await tap('记录我的实际体验');
      await t.enterText(find.byType(TextField), '咖啡一般，喜欢书摊');
      await t.pumpAndSettle();
      await tap('仅为我保存');
      expect(find.text('我的体验 · 仅我和我的 DP 可用'), findsOneWidget);
      await tap('纠正或撤回我的体验');
      await tap('分享给伴侣和共同 DP');
      await tap('确认共享体验');
      expect(find.text('我的体验 · 双方和共同 DP 可用'), findsOneWidget);
      await tap('纠正或撤回我的体验');
      await tap('撤回体验');
      await tap('确认撤回');
      expect(find.text('咖啡一般，喜欢书摊'), findsNothing);
      expect(s.calls.length, 6);
      expect(t.takeException(), isNull);
    },
  );
}
