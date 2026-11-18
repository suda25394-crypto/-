import 'dart:convert';

import 'package:couple_app/src/client.dart';
import 'package:couple_app/src/services/cloud_session.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:material_ui/material_ui.dart';

import 'cloud_session_test.dart' show MemoryVault;

void main() {
  for (final viewport in [const Size(360, 800), const Size(390, 844)]) {
    testWidgets('paired app uses live state across four tabs at $viewport', (
      tester,
    ) async {
      tester.view.devicePixelRatio = 1;
      tester.view.physicalSize = viewport;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      final shared = <Json>[], priv = <Json>[], modules = <Json>[];
      final vault = MemoryVault();
      final session = CloudSession(
        vault: vault,
        client: MockClient((req) async {
          dynamic result;
          final path = req.url.path;
          if (path == '/v1/health') {
            result = {'ok': true, 'schema': 3};
          } else if (path == '/v1/login') {
            result = {'token': 'session-fixture'};
          } else if (path == '/v1/state') {
            result = {
              'mode': 'fixture',
              'user': {'id': 'a', 'name': 'A'},
              'paired': true,
              'messages': {'private': priv, 'shared': shared},
              'modules': modules,
              'drafts': [],
              'memories': [],
              'profiles': [],
            };
          } else if (path == '/v1/messages') {
            final p = jsonDecode(req.body) as Json;
            (p['scope'] == 'private' ? priv : shared).add({
              'owner': 'a',
              'role': 'user',
              'id': p['request_id'],
              'text': p['text'],
            });
            result = {'ok': true};
          } else if (path == '/v1/modules') {
            final p = jsonDecode(req.body) as Json;
            expect(p['confirmed'], true);
            modules.add({...p, 'version': 1, 'owner': 'a', 'id': 'm1'});
            result = {'ok': true};
          } else if (path == '/v1/logout') {
            result = {'ok': true};
          } else {
            fail('Unexpected path $path');
          }
          return http.Response.bytes(utf8.encode(jsonEncode(result)), 200);
        }),
      );
      Future<void> tap(Finder f) async {
        await tester.ensureVisible(f);
        await tester.tap(f);
        await tester.pumpAndSettle();
      }

      await tester.pumpWidget(CoupleClient(session: session));
      await tester.pumpAndSettle();
      expect(find.text('登录私人空间'), findsOneWidget);
      expect(find.text('体验本机演示'), findsOneWidget);
      await tester.enterText(
        find.byKey(const Key('service-url')),
        'https://fixture.test',
      );
      await tester.enterText(
        find.byKey(const Key('account-email')),
        'a@example.test',
      );
      await tester.enterText(
        find.byKey(const Key('account-password')),
        'fixture-only',
      );
      await tap(find.text('登录'));
      expect(find.textContaining('合成联调'), findsOneWidget);
      expect(find.text('共同记忆'), findsNothing);
      await tap(find.byKey(const Key('open-director')));
      await tester.enterText(
        find.byKey(const Key('cloud-private-input')),
        '只写给我',
      );
      await tap(find.text('发送'));
      expect(find.text('只写给我'), findsOneWidget);
      await tester.pageBack();
      await tester.pumpAndSettle();
      await tap(find.text('共同'));
      expect(find.text('只写给我'), findsNothing);
      await tester.enterText(
        find.byKey(const Key('cloud-shared-input')),
        '共同消息样本',
      );
      await tap(find.text('发送'));
      expect(find.text('共同消息样本'), findsOneWidget);
      await tap(find.text('功能'));
      await tap(find.byKey(const Key('module-date')));
      await tap(find.text('添加共同记录'));
      await tester.enterText(find.byType(TextField).first, '周六散步');
      await tester.enterText(find.byType(TextField).last, '16:00 湖边');
      await tap(find.text('预览并保存'));
      await tap(find.text('确认保存'));
      expect(find.text('周六散步'), findsOneWidget);
      await tester.pageBack();
      await tester.pumpAndSettle();
      await tap(find.text('首页'));
      expect(find.text('周六散步'), findsOneWidget);
      await tap(find.text('档案'));
      expect(tester.takeException(), isNull);
      await tap(find.textContaining('合成联调'));
      await tap(find.text('退出登录'));
      expect(find.text('登录私人空间'), findsOneWidget);
      expect(vault.entry, isNull);
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox.shrink());
      session.dispose();
    });
  }
}
