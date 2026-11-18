import 'dart:convert';

import 'package:couple_app/src/services/cloud_session.dart';
import 'package:couple_app/src/ui/cloud_chat.dart';
import 'package:couple_app/src/ui/cloud_records.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:material_ui/material_ui.dart';

import 'cloud_session_test.dart' show MemoryVault;

void main() {
  testWidgets(
    'reopened composer retrieves original request id, then draft and memory require explicit publication',
    (t) async {
      t.view.devicePixelRatio = 1;
      t.view.physicalSize = const Size(360, 800);
      addTearDown(t.view.resetPhysicalSize);
      addTearDown(t.view.resetDevicePixelRatio);
      final state = <String, dynamic>{
        'mode': 'fixture',
        'user': {'id': 'a', 'name': 'A'},
        'paired': true,
        'messages': {'private': [], 'shared': []},
        'pending_messages': [
          {
            'request_id': 'retry-original-id',
            'scope': 'private',
            'text': '我不喜欢人多',
            'busy': false,
            'uncertain': false,
          },
        ],
        'drafts': [
          {
            'id': 'd',
            'version': 1,
            'owner': 'a',
            'scope': 'private',
            'status': 'pending',
            'items': [
              {'module': 'date', 'title': '周六约会', 'body': '15:00 公园'},
            ],
          },
        ],
        'memories': [
          {
            'id': 'm',
            'version': 1,
            'owner': 'a',
            'scope': 'candidate',
            'text': '偏好清静',
          },
        ],
        'modules': [],
        'profiles': [],
      };
      final mutations = <String>[];
      final vault = MemoryVault();
      vault.entry = jsonEncode({
        'token': 'fixture',
        'endpoint': 'https://fixture.test',
      });
      final session = CloudSession(
        vault: vault,
        client: MockClient((r) async {
          if (r.method == 'GET') {
            return http.Response.bytes(utf8.encode(jsonEncode(state)), 200);
          }
          final b = jsonDecode(r.body) as Json;
          mutations.add(r.url.path);
          if (r.url.path == '/v1/messages') {
            expect(b['request_id'], 'retry-original-id');
            expect(b['scope'], 'private');
            state['pending_messages'] = [];
          } else if (r.url.path == '/v1/drafts/d/confirm') {
            expect(b['version'], 1);
            expect(b['items'][0]['body'], '更改到 16:00');
            state['drafts'][0]['status'] = 'confirmed';
          } else if (r.url.path == '/v1/memories/m') {
            expect(b['scope'], 'shared');
            expect(b['text'], '偏好清静');
            state['memories'][0]['scope'] = 'shared';
          } else {
            fail('Unexpected POST/PUT $r');
          }
          return http.Response('{"ok":true}', 200);
        }),
      );
      await session.restore();
      Future<void> tap(Finder f) async {
        await t.ensureVisible(f);
        await t.tap(f);
        await t.pumpAndSettle();
      }

      await t.pumpWidget(
        MaterialApp(
          home: Builder(
            builder: (ctx) => Scaffold(
              body: CloudChat(
                session: session,
                scope: 'private',
                openRecords: () => Navigator.push(
                  ctx,
                  MaterialPageRoute(
                    builder: (_) =>
                        CloudRecords(session: session, shared: false),
                  ),
                ),
              ),
            ),
          ),
        ),
      );
      await t.pumpAndSettle();
      await tap(find.textContaining('我的待处理消息'));
      await tap(find.text('我不喜欢人多'));
      expect(mutations, isEmpty);
      await tap(find.text('重试'));
      expect(mutations, ['/v1/messages']);
      await tap(find.text('草稿 1 / 记忆'));
      await tap(find.text('周六约会'));
      await t.enterText(find.byType(TextField).last, '更改到 16:00');
      await tap(find.text('确认写入共同模块'));
      await tap(find.text('返回'));
      expect(mutations, ['/v1/messages']);
      await tap(find.text('确认写入共同模块'));
      await tap(find.text('确认发布'));
      await tap(find.text('偏好清静'));
      await tap(find.text('确认并发布给伴侣'));
      await tap(find.text('确认发布'));
      expect(mutations, [
        '/v1/messages',
        '/v1/drafts/d/confirm',
        '/v1/memories/m',
      ]);
      expect(t.takeException(), isNull);
      await t.pumpWidget(const SizedBox.shrink());
      session.dispose();
    },
  );
}
