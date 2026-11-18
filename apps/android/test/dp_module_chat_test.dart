import 'package:couple_app/src/data/catalog.dart';
import 'package:couple_app/src/services/cloud_session.dart';
import 'package:couple_app/src/ui/cloud_records.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';

class _ThreadSession extends CloudSession {
  final record = <String, dynamic>{
    'id': 'm01',
    'module': 'date',
    'version': 1,
    'title': '河边晚饭',
    'body': '周六晚六点会合',
  };
  final threads = <String, List<Json>>{'private': [], 'shared': []};
  Json? draft;
  final posts = <Json>[];
  _ThreadSession() {
    state = {
      'user': {'id': 'alice'},
      'modules': [record],
      'mode': 'fixture',
    };
  }
  @override
  Future<dynamic> request(String method, String path, [Json? body]) async {
    final uri = Uri.parse(path);
    expect(method, 'GET');
    expect(uri.path, '/v1/modules/m01/conversation');
    final scope = uri.queryParameters['scope']!;
    return <String, dynamic>{
      'record': {...record},
      'messages': [...threads[scope]!],
      'drafts': [if (draft != null && draft!['scope'] == scope) draft!],
    };
  }

  @override
  Future<dynamic> mutate(String method, String path, [Json? body]) async {
    if (path == '/v1/modules/m01/conversation') {
      posts.add(body!);
      expect(body['request_id'], isNotEmpty);
      expect(body['version'], record['version']);
      final scope = body['scope'] as String;
      threads[scope]!.addAll([
        {'id': 'u', 'role': 'user', 'owner': 'alice', 'text': body['text']},
        {
          'id': 'r',
          'role': 'assistant',
          'owner': 'alice',
          'text': '已收到这条记录的请求',
        },
      ]);
      if (scope == 'private') {
        draft = {
          'id': 'd01',
          'version': 1,
          'scope': scope,
          'status': 'pending',
          'target_id': 'm01',
          'target_version': 1,
          'items': [
            <String, dynamic>{'module': 'date', 'title': '晚些见', 'body': '周六七点'},
          ],
        };
      }
    } else if (path == '/v1/drafts/d01/confirm') {
      final edit = (body!['items'] as List).single as Json;
      record.addAll({
        'version': 2,
        'title': edit['title'],
        'body': edit['body'],
      });
      draft!['status'] = 'confirmed';
    } else {
      fail('Unexpected request $method $path');
    }
    notifyListeners();
    return {'ok': true};
  }
}

void main() {
  for (final size in [const Size(360, 800), const Size(390, 844)]) {
    testWidgets(
      'module private/shared continuity and explicit targeted edit at ${size.width}',
      (t) async {
        t.view.devicePixelRatio = 1;
        t.view.physicalSize = size;
        addTearDown(t.view.resetPhysicalSize);
        addTearDown(t.view.resetDevicePixelRatio);
        final s = _ThreadSession();
        addTearDown(s.dispose);
        await t.pumpWidget(
          MaterialApp(
            home: CloudModuleScreen(session: s, id: ModuleId.date),
          ),
        );
        Future<void> tap(String text) async {
          final f = find.text(text);
          await t.ensureVisible(f);
          await t.tap(f);
          await t.pumpAndSettle();
        }

        await tap('河边晚饭');
        await tap('私下问 DP');
        await t.enterText(
          find.byKey(const Key('cloud-private-input')),
          '想把六点改到七点',
        );
        await tap('发送');
        expect(find.text('已收到这条记录的请求'), findsOneWidget);
        expect(s.record['body'], '周六晚六点会合');
        await tap('本条草稿（1）');
        await tap('晚些见');
        await t.enterText(find.byType(TextField).last, '周六七点半');
        await tap('确认写入共同模块');
        await tap('返回');
        expect(s.record['version'], 1);
        await tap('确认写入共同模块');
        await tap('确认发布');
        expect(s.record['body'], '周六七点半');
        expect(find.textContaining('第 2 版'), findsOneWidget);
        await t.pageBack();
        await t.pumpAndSettle();
        await tap('两人共同续聊');
        expect(find.text('想把六点改到七点'), findsNothing);
        expect(find.text('双方可见 · DP 围绕本条记录回复'), findsOneWidget);
        await t.enterText(find.byType(TextField), '@DP 现在几点？');
        await tap('发送');
        expect(s.posts.map((p) => p['scope']), ['private', 'shared']);
        expect(t.takeException(), isNull);
      },
    );
  }
}
