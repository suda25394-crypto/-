import 'dart:convert';

import 'package:couple_app/src/client.dart';
import 'package:couple_app/src/services/cloud_session.dart';
import 'package:flutter/rendering.dart' show RenderParagraph;
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:material_ui/material_ui.dart';

import 'cloud_session_test.dart' show MemoryVault;

const _address = 'https://fixture.invalid/couple';
Finder _key(String key) => find.byKey(Key(key));

Future<void> _tap(WidgetTester t, String key) async {
  final button = _key(key);
  expect(button.hitTestable(), findsOneWidget);
  await t.tap(button);
  await t.pumpAndSettle();
}

Future<CloudSession> _restore(WidgetTester t, {double scale = 1}) async {
  t.view.devicePixelRatio = 1;
  t.view.physicalSize = const Size(320, 720);
  t.platformDispatcher.textScaleFactorTestValue = scale;
  addTearDown(t.view.resetDevicePixelRatio);
  addTearDown(t.view.resetPhysicalSize);
  addTearDown(t.view.resetViewInsets);
  addTearDown(t.platformDispatcher.clearTextScaleFactorTestValue);
  final vault = MemoryVault()
    ..entry = jsonEncode({'endpoint': _address, 'token': 'fixture-A'});
  final session = CloudSession(
    vault: vault,
    client: MockClient((req) async {
      final path = req.url.path;
      final id = req.headers['authorization'] == 'Bearer fixture-B' ? 'B' : 'A';
      dynamic result;
      switch (path) {
        case '/couple/v1/health':
          result = {'ok': true, 'schema': 3};
        case '/couple/v1/login':
          expect((jsonDecode(req.body) as Json)['email'], 'b@example.invalid');
          result = {'token': 'fixture-B'};
        case '/couple/v1/logout':
          result = {'ok': true};
        case '/couple/v1/state':
          expect(
            req.headers['authorization'],
            isIn(['Bearer fixture-A', 'Bearer fixture-B']),
          );
          result = {
            'mode': 'fixture',
            'paired': true,
            'user': {'id': id, 'name': id},
            'messages': {
              'private': [
                {'owner': id, 'role': 'user', 'text': '账号 $id 的私信'},
              ],
              'shared': [
                {'owner': 'A', 'role': 'user', 'text': '双方共享的记录'},
              ],
            },
          };
        default:
          fail('Unexpected request: $path');
      }
      return http.Response.bytes(utf8.encode(jsonEncode(result)), 200);
    }),
  );
  addTearDown(session.dispose);
  await t.pumpWidget(CoupleClient(session: session));
  await t.pumpAndSettle();
  session.setPolling(false);
  expect(find.text('我们仨'), findsOneWidget);
  expect(find.text('双方共享的记录'), findsOneWidget);
  expect(find.text('账号 A 的私信'), findsNothing);
  return session;
}

void main() {
  testWidgets(
    'conversation list opens both scopes without showing private previews',
    (t) async {
      await _restore(t, scale: 1.8);
      final group = _key('cloud-shared-input');
      await t.enterText(group, '保留在群聊的草稿');

      await _tap(t, 'open-conversations');
      expect(find.text('双方共享的记录'), findsOneWidget);
      expect(find.text('私聊 · 仅自己可见'), findsOneWidget);
      expect(find.text('账号 A 的私信'), findsNothing);
      await _tap(t, 'conversation-shared');
      expect(t.widget<TextField>(group).controller!.text, '保留在群聊的草稿');

      await _tap(t, 'open-conversations');
      await _tap(t, 'conversation-private');
      expect(_key('cloud-private-input'), findsOneWidget);
      expect(find.text('账号 A 的私信'), findsOneWidget);
      expect(find.text('双方共享的记录'), findsNothing);
      await t.binding.handlePopRoute();
      await t.pumpAndSettle();
      expect(t.widget<TextField>(group).controller!.text, '保留在群聊的草稿');
      expect(t.takeException(), isNull);
      await t.pumpWidget(const SizedBox.shrink());
    },
  );

  testWidgets(
    'restored group, keyboard, private route and Android back retain the shared composer',
    (t) async {
      await _restore(t);
      final group = _key('cloud-shared-input');
      await t.enterText(group, '留在群里的草稿');
      t.view.viewInsets = const FakeViewPadding(bottom: 260);
      await t.pumpAndSettle();
      expect(_key('tab-0'), findsNothing);
      expect(t.getBottomLeft(group).dy, lessThanOrEqualTo(720 - 260));
      t.view.resetViewInsets();
      await t.pumpAndSettle();
      expect(_key('tab-0'), findsOneWidget);
      await _tap(t, 'open-private');
      expect(find.text('我和 DP'), findsOneWidget);
      expect(_key('tab-0'), findsNothing);
      expect(find.text('双方共享的记录'), findsNothing);
      expect(find.text('账号 A 的私信'), findsOneWidget);
      final privateInput = _key('cloud-private-input');
      expect(t.widget<TextField>(privateInput).controller!.text, isEmpty);
      await t.enterText(privateInput, '仅在私聊输入');
      await t.binding.handlePopRoute();
      await t.pumpAndSettle();
      expect(t.widget<TextField>(group).controller!.text, '留在群里的草稿');
      expect(find.text('仅在私聊输入'), findsNothing);
      await _tap(t, 'tab-1');
      await _tap(t, 'module-date');
      expect(_key('tab-1'), findsNothing);
      await t.binding.handlePopRoute();
      await t.pumpAndSettle();
      expect(find.text('全部功能'), findsOneWidget);
      expect(_key('tab-1'), findsOneWidget);
      await t.binding.handlePopRoute();
      await t.pumpAndSettle();
      expect(t.widget<TextField>(group).controller!.text, '留在群里的草稿');
      expect(t.takeException(), isNull);
      await t.pumpWidget(const SizedBox.shrink());
    },
  );

  testWidgets(
    'ending A session on private route clears both drafts and starts B in the shared group',
    (t) async {
      final session = await _restore(t);
      await t.enterText(_key('cloud-shared-input'), 'A 群输入草稿');
      await _tap(t, 'open-private');
      await t.enterText(_key('cloud-private-input'), 'A 私聊输入草稿');
      await session.logout();
      await t.pumpAndSettle();
      expect(find.text('登录私人空间'), findsOneWidget);
      expect(_key('cloud-private-input'), findsNothing);
      await t.enterText(_key('service-url'), _address);
      await t.enterText(_key('account-email'), 'b@example.invalid');
      await t.enterText(_key('account-password'), 'fixture');
      await t.ensureVisible(find.text('登录'));
      await t.tap(find.text('登录'));
      await t.pumpAndSettle();
      session.setPolling(false);
      expect(find.text('我们仨'), findsOneWidget);
      expect(
        t.widget<TextField>(_key('cloud-shared-input')).controller!.text,
        isEmpty,
      );
      expect(find.text('双方共享的记录'), findsOneWidget);
      await _tap(t, 'open-private');
      expect(
        t.widget<TextField>(_key('cloud-private-input')).controller!.text,
        isEmpty,
      );
      expect(find.text('账号 B 的私信'), findsOneWidget);
      expect(find.text('账号 A 的私信'), findsNothing);
      expect(find.text('A 私聊输入草稿'), findsNothing);
      expect(t.takeException(), isNull);
      await t.pumpWidget(const SizedBox.shrink());
    },
  );

  testWidgets(
    'full heading and private entry fit on 320dp at 180 percent text',
    (t) async {
      await _restore(t, scale: 1.8);
      final title = find.text('我们仨');
      final paragraph = t.renderObject<RenderParagraph>(title);
      final natural = TextPainter(
        text: paragraph.text,
        textDirection: paragraph.textDirection,
        textScaler: paragraph.textScaler,
        maxLines: 1,
      )..layout();
      expect(paragraph.size.width, greaterThanOrEqualTo(natural.width - .5));
      expect(paragraph.size.height, greaterThanOrEqualTo(natural.height - .5));
      natural.dispose();
      expect(
        t.getRect(title).right,
        lessThanOrEqualTo(t.getRect(_key('change-wallpaper')).left),
      );
      expect(_key('open-private').hitTestable(), findsOneWidget);
      await _tap(t, 'open-private');
      expect(find.text('我和 DP'), findsOneWidget);
      expect(t.takeException(), isNull);
      await t.pumpWidget(const SizedBox.shrink());
    },
  );
}
