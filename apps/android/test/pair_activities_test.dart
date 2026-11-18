import 'dart:convert';

import 'package:couple_app/src/data/catalog.dart';
import 'package:couple_app/src/data/pair_activity.dart';
import 'package:couple_app/src/services/cloud_session.dart';
import 'package:couple_app/src/ui/cloud_records.dart';
import 'package:couple_app/src/ui/dp_module_chat.dart';
import 'package:couple_app/src/ui/pair_activities.dart';
import 'package:couple_app/src/ui/white_purple_tabs.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';

class _Pair {
  final records = <Json>[], activities = <Json>[];
  final requests = <String>[];

  Json snapshot(String user) => jsonDecode(
    jsonEncode({
      'user': {'id': user},
      'modules': records,
      'activities': activities,
    }),
  ) as Json;
}

class _LocalSession extends CloudSession {
  _LocalSession(this.pair, this.actor) {
    state = pair.snapshot(actor);
  }

  final _Pair pair;
  final String actor;

  @override
  Future<dynamic> mutate(String method, String path, [Json? body]) async {
    pair.requests.add('$method $path');
    if (path == '/v1/modules') {
      expect(body!['confirmed'], isTrue);
      expect(body['request_id'], isNotEmpty);
      final id = 'record-${pair.records.length}';
      pair.records.insert(0, {
        'id': id,
        'owner': actor,
        'module': body['module'],
        'title': body['title'],
        'body': body['body'],
        'version': 1,
      });
      pair.activities.add({
        'module_id': id,
        'proposal_version': 1,
        'agreed': false,
        'votes': [
          for (final id in ['alice', 'bob'])
            {'owner': id, 'name': id, 'choice': null, 'note': '', 'version': 0},
        ],
      });
    } else {
      expect(method, 'PUT');
      expect(path.endsWith('/vote'), isTrue);
      final target = pair.activities.singleWhere(
        (v) => v['module_id'] == path.split('/')[3],
      );
      final votes = (target['votes'] as List).cast<Json>();
      final myVote = votes.singleWhere((v) => v['owner'] == actor);
      expect(body!['version'], myVote['version']);
      expect(body['proposal_version'], target['proposal_version']);
      myVote.addAll({
        'choice': body['choice'],
        'note': body['note'],
        'version': (myVote['version'] as int) + 1,
      });
      target['agreed'] = votes.every((v) => v['choice'] == 'accept');
    }
    state = pair.snapshot(actor);
    notifyListeners();
    return {'ok': true};
  }
}

class _EditSession extends CloudSession {
  _EditSession(this.record) {
    state = {
      'modules': [record],
    };
  }
  final Json record;

  @override
  Future<dynamic> mutate(String method, String path, [Json? body]) async {
    if (method == 'PUT') {
      expect(path, '/v1/modules/m1');
      record['body'] = body!['body'];
    } else {
      expect(path, '/v1/drafts/d1/confirm');
      record['body'] = (body!['items'] as List).single['body'];
    }
    return {'ok': true};
  }
}

void main() {
  testWidgets(
    'draw follows its linked plan or memory and a returned wish can vote again',
    (t) async {
      for (final stage in ['planned', 'remembered', 'wish']) {
        final session = CloudSession();
        addTearDown(session.dispose);
        session.state = {
          'user': {'id': 'bob'},
          'modules': <Json>[
            {
              'id': 'w',
              'module': 'wish',
              'title': '一起散步',
              'body': '约会行动签\n在街角走走',
              'owner': 'alice',
              'version': 2,
            },
            {
              'id': 'p',
              'module': 'calendar',
              'title': '一起散步',
              'body': '在街角走走',
              'owner': 'alice',
              'version': 2,
            },
            {
              'id': 'm',
              'module': 'memory',
              'title': '散步之后',
              'body': '我们去了东门',
              'owner': 'bob',
              'version': 1,
            },
          ],
          'activities': <Json>[
            {
              'module_id': 'w',
              'proposal_version': 2,
              'agreed': false,
              'votes': <Json>[
                {'owner': 'alice', 'name': 'Alice', 'version': 0},
                {'owner': 'bob', 'name': 'Bob', 'version': 0},
              ],
            },
          ],
          'journeys': <Json>[
            {
              'wish': 'w',
              'plan': 'p',
              'stage': stage,
              'memory': stage == 'remembered' ? 'm' : null,
              'day': '2026-11-19',
              'clock': '14:30',
              'place': '东门',
            },
          ],
        };
        await t.pumpWidget(
          MaterialApp(
            key: UniqueKey(),
            home: PairActivitiesPage(session: session, kind: PairActivity.draw),
          ),
        );
        await t.pumpAndSettle();
        if (stage == 'wish') {
          expect(find.text('愿意'), findsOneWidget);
          expect(find.text('已排进共同日程'), findsNothing);
        } else {
          final planned = stage == 'planned';
          expect(find.text(planned ? '已排进共同日程' : '已留下共同回忆'), findsOneWidget);
          expect(find.text('愿意'), findsNothing);
          expect(find.text('两人都愿意'), findsNothing);
          if (planned) {
            expect(find.text('2026-11-19 · 14:30 · 东门'), findsOneWidget);
          }
          await t.tap(find.text(planned ? '查看共同日程' : '查看共同回忆'));
          await t.pumpAndSettle();
          expect(
            t
                .widget<CloudModuleDetail>(find.byType(CloudModuleDetail))
                .moduleId,
            planned ? 'p' : 'm',
          );
        }
        expect(t.takeException(), isNull);
      }
    },
  );

  testWidgets(
    'normal edit and targeted DP draft retain the activity type once',
    (t) async {
      Future<void> tap(String text) async {
        await t.ensureVisible(find.text(text));
        await t.tap(find.text(text));
        await t.pumpAndSettle();
      }

      for (final kind in [...PairActivity.values, null]) {
        final module = kind?.module ?? 'memory';
        final row = <String, dynamic>{
          'module': module,
          'title': '原题',
          'id': 'm1',
          'version': 1,
          'body': kind?.storedBody('原文') ?? '原文',
        };
        final session = _EditSession(row);
        addTearDown(session.dispose);
        await t.pumpWidget(
          MaterialApp(
            key: UniqueKey(),
            home: CloudModuleEditor(
              session: session,
              id: ModuleId.values.byName(module),
              row: row,
            ),
          ),
        );
        expect(
          t.widget<TextField>(find.byType(TextField).last).controller!.text,
          '原文',
        );
        await t.enterText(find.byType(TextField).last, '手改文本');
        await tap('预览并保存');
        await tap('确认保存');
        expect(row['body'], '${kind?.marker ?? ''}手改文本');
        final proposed = kind == PairActivity.draw
            ? '${kind!.marker}草稿文本'
            : '草稿文本';
        await t.pumpWidget(
          MaterialApp(
            key: UniqueKey(),
            home: DraftEditor(
              session: session,
              draft: {
                'target_id': 'm1',
                'target_version': 2,
                'id': 'd1',
                'version': 1,
                'status': 'pending',
                'items': [
                  {'module': module, 'body': proposed, 'title': '新题'},
                ],
              },
            ),
          ),
        );
        expect(
          t.widget<TextField>(find.byType(TextField).last).controller!.text,
          '草稿文本',
        );
        await tap('确认写入共同模块');
        await tap('确认发布');
        expect(row['body'], '${kind?.marker ?? ''}草稿文本');
        expect(PairActivity.forRecord(row), kind);
      }
    },
  );

  testWidgets(
    'two people leave a note, reply, draw an invitation and return to the same results',
    (t) async {
      final pair = _Pair();
      t.view.devicePixelRatio = 1;
      t.view.physicalSize = const Size(360, 800);
      addTearDown(t.view.resetPhysicalSize);
      addTearDown(t.view.resetDevicePixelRatio);

      Future<void> tap(Finder f) async {
        await t.ensureVisible(f);
        await t.tap(f);
        await t.pumpAndSettle();
      }

      Future<void> open(String who, PairActivity kind) async {
        await t.pumpWidget(const SizedBox.shrink());
        final session = _LocalSession(pair, who);
        addTearDown(session.dispose);
        await t.pumpWidget(
          MaterialApp(
            home: Scaffold(
              body: FeaturesTab(
                session: session,
                openModule: (_) {},
                openPrivateChat: () {},
              ),
            ),
          ),
        );
        await t.pumpAndSettle();
        await tap(find.text(kind.label));
        expect(find.byType(PairActivitiesPage), findsOneWidget);
      }

      Finder key(String value) => find.byKey(Key(value));

      await open('alice', PairActivity.notebook);
      await tap(key('pair-compose-notebook'));
      await t.enterText(key('pair-note-body'), '下雨了，我带了两把伞。');
      await t.pump();
      await tap(key('pair-publish'));
      expect(find.text('等伴侣收下'), findsOneWidget);

      await open('bob', PairActivity.notebook);
      await tap(find.text('收下并回信'));
      await t.enterText(key('pair-reply-body'), '下班见！');
      await t.pump();
      await tap(key('pair-reply-save'));
      expect(find.text('我已收下'), findsOneWidget);
      await open('alice', PairActivity.notebook);
      expect(find.text('回信 · 下班见！'), findsOneWidget);
      expect(find.text('收下并回信'), findsNothing);

      await open('alice', PairActivity.draw);
      await tap(key('pair-compose-draw'));
      await tap(find.text('异地也能玩'));
      await tap(key('pair-reveal'));
      final before = pair.requests.length;
      await tap(find.text('换一张'));
      expect(pair.requests.length, before);
      await tap(key('pair-publish'));
      await tap(find.text('愿意'));
      await open('bob', PairActivity.draw);
      expect(find.text('alice · 愿意'), findsOneWidget);
      await tap(find.text('愿意'));
      for (final who in ['alice', 'bob']) {
        await open(who, PairActivity.draw);
        expect(find.text('两人都愿意'), findsOneWidget);
        expect(find.text('打开共同心愿，安排日期'), findsOneWidget);
      }
      expect(pair.requests.where((r) => r == 'POST /v1/modules'), hasLength(2));
      expect(pair.requests.where((r) => r.endsWith('/vote')), hasLength(3));
      expect(t.takeException(), isNull);
    },
  );
}
