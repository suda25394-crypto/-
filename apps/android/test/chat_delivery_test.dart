import 'dart:async';
import 'dart:convert';

import 'package:couple_app/src/client.dart';
import 'package:couple_app/src/services/cloud_session.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:material_ui/material_ui.dart';

import 'cloud_session_test.dart' show MemoryVault;

class _Fixture {
  final shared = List<Json>.generate(
    50,
    (i) => {'id': 'old-$i', 'owner': 'B', 'role': 'user', 'text': '历史 $i'},
  );
  final paths = <String>[];
  final posts = <Json>[];
  Completer<void>? postGate, readGate;
  int postStatus = 200, readStatus = 200;
  int concurrentReads = 0, maxReads = 0;
  late final session = CloudSession(
    vault: MemoryVault()
      ..entry = jsonEncode({
        'endpoint': 'https://test.invalid',
        'token': 'fixture',
      }),
    client: MockClient((request) async {
      final path = request.url.path;
      paths.add(path);
      http.Response json(dynamic value, [int code = 200]) =>
          http.Response.bytes(utf8.encode(jsonEncode(value)), code);
      if (path == '/v1/health') return json({'ok': true, 'schema': 3});
      if (path == '/v1/state') {
        concurrentReads++;
        if (maxReads < concurrentReads) maxReads = concurrentReads;
        final snapshot = json({
          'paired': true,
          'user': {'id': 'A', 'name': 'A'},
          'messages': {'shared': shared, 'private': <Json>[]},
          'mode': 'fixture',
        });
        final gate = readGate;
        readGate = null;
        try {
          if (gate != null) await gate.future;
          if (readStatus != 200) {
            return json({
              'error': {'message': '离线'},
            }, readStatus);
          }
          return snapshot;
        } finally {
          concurrentReads--;
        }
      }
      if (path == '/v1/messages') {
        final body = jsonDecode(request.body) as Json;
        posts.add(body);
        if (postGate case final gate?) await gate.future;
        if (postStatus != 200) {
          return json({
            'error': {'code': 'in_progress', 'message': '处理中'},
          }, postStatus);
        }
        shared.add({
          'id': 'remote-${posts.length}',
          'owner': 'A',
          'role': 'user',
          'text': body['text'],
        });
        return json({'ok': true});
      }
      throw StateError(path);
    }),
  );

  Future<void> show(WidgetTester t) async {
    t.view.devicePixelRatio = 1;
    t.view.physicalSize = const Size(390, 844);
    addTearDown(t.view.resetPhysicalSize);
    addTearDown(t.view.resetDevicePixelRatio);
    await t.pumpWidget(CoupleClient(session: session));
    await t.pumpAndSettle();
    session.setPolling(false);
    paths.clear();
  }

  Future<void> finish(WidgetTester t) async {
    await t.pumpWidget(const SizedBox.shrink());
    session.dispose();
  }
}

void main() {
  testWidgets(
    'unchanged polls stay quiet and stale reads serialize behind writes',
    (t) async {
      final f = _Fixture();
      await f.show(t);
      var notifications = 0;
      f.session.addListener(() => notifications++);
      f.session.setPolling(true);
      for (var i = 0; i < 3; i++) {
        await t.pump(const Duration(seconds: 4));
        await t.pump();
      }
      f.session.setPolling(false);
      expect(f.paths, List.filled(3, '/v1/state'));
      expect(notifications, 0);
      f.paths.clear();

      final gate = Completer<void>();
      f.readGate = gate;
      final old = f.session.refresh();
      final alsoOld = f.session.refresh();
      final write = f.session.mutate('POST', '/v1/messages', {
        'text': '写后读取',
        'request_id': 'synthetic',
        'scope': 'shared',
      });
      await t.pump();
      expect(f.paths, ['/v1/state', '/v1/messages']);
      gate.complete();
      await Future.wait([old, alsoOld, write]);
      expect(f.paths, ['/v1/state', '/v1/messages', '/v1/state']);
      expect(f.maxReads, 1);
      expect(notifications, 1);
      expect(f.session.messages('shared').last['text'], '写后读取');
      f.readStatus = 503;
      await expectLater(f.session.refresh(), throwsA(isA<CloudError>()));
      await expectLater(f.session.refresh(), throwsA(isA<CloudError>()));
      expect(notifications, 2);
      f.readStatus = 200;
      await f.session.refresh();
      expect(notifications, 3);
      await f.finish(t);
    },
  );

  testWidgets('overlapping writes both wait for the authoritative snapshot', (
    t,
  ) async {
    final f = _Fixture();
    await f.show(t);
    final firstGate = Completer<void>(), latestGate = Completer<void>();
    final completed = <String>[];
    Future<void> send(String key) async {
      await f.session.mutate('POST', '/v1/messages', {
        'text': key,
        'request_id': key,
        'scope': 'shared',
      });
      completed.add(key);
    }

    f.readGate = firstGate;
    final first = send('first');
    await t.pump();
    f.readGate = latestGate;
    final second = send('second');
    await t.pump();
    firstGate.complete();
    await t.pump();
    expect(completed, isEmpty);
    latestGate.complete();
    await Future.wait([first, second]);
    expect(f.maxReads, 1);
    expect(f.paths, ['/v1/messages', '/v1/state', '/v1/messages', '/v1/state']);
    expect(f.session.messages('shared').last['text'], 'second');
    await f.finish(t);
  });

  testWidgets(
    'local bubble precedes ACK; same text and conflict retry keep request identities',
    (t) async {
      final f = _Fixture();
      await f.show(t);
      final composer = find.byKey(const Key('cloud-shared-input'));
      final send = find.byKey(const Key('chat-send'));
      Future<void> sendSame() async {
        await t.enterText(composer, '同样的话');
        await t.pump();
        await t.tap(send);
        await t.pump();
      }

      f.postGate = Completer<void>();
      final oldBubble = find.byKey(const ValueKey<dynamic>('old-49'));
      final originalElement = t.element(oldBubble);
      await sendSame();
      expect(identical(t.element(oldBubble), originalElement), isTrue);
      expect(find.text('同样的话'), findsOneWidget);
      expect(find.text('我 · 发送中'), findsOneWidget);
      expect(f.paths, ['/v1/messages']);
      f.postGate!.complete();
      await t.pumpAndSettle();
      expect(find.text('同样的话'), findsOneWidget);
      f.postStatus = 409;
      f.paths.clear();
      await sendSame();
      await t.pumpAndSettle();
      expect(f.paths, ['/v1/messages', '/v1/state']);
      expect(t.widget<TextField>(composer).controller!.text, '同样的话');
      expect(f.posts[0]['request_id'], isNot(f.posts[1]['request_id']));
      f.postStatus = 200;
      await t.tap(send);
      await t.pumpAndSettle();
      expect(f.posts[2]['request_id'], f.posts[1]['request_id']);
      expect(find.text('同样的话'), findsNWidgets(2));
      await f.finish(t);
    },
  );

  testWidgets(
    'another device on the same account cannot consume a local send',
    (t) async {
      final f = _Fixture();
      await f.show(t);
      f.postGate = Completer<void>();
      await t.enterText(find.byKey(const Key('cloud-shared-input')), '同文并发');
      await t.pump();
      await t.tap(find.byKey(const Key('chat-send')));
      await t.pump();
      for (final entry in [('other-1', '另一设备不同内容'), ('other-2', '同文并发')]) {
        f.shared.add({
          'id': entry.$1,
          'owner': 'A',
          'role': 'user',
          'text': entry.$2,
        });
        await f.session.refresh();
        await t.pump();
        expect(find.text('我 · 发送中'), findsOneWidget);
        expect(find.text('同文并发'), findsNWidgets(entry.$1 == 'other-1' ? 1 : 2));
      }
      f.postGate!.complete();
      await t.pumpAndSettle();
      expect(find.text('我 · 发送中'), findsNothing);
      expect(find.text('同文并发'), findsNWidgets(2));
      expect(f.posts.length, 1);
      await f.finish(t);
    },
  );

  testWidgets(
    'incoming preserves the reading anchor; a local send returns to newest',
    (t) async {
      final f = _Fixture();
      await f.show(t);
      final list = find.byWidgetPredicate((w) => w is ListView && w.reverse);
      for (var i = 0; i < 3; i++) {
        await t.drag(list, const Offset(0, 520));
        await t.pumpAndSettle();
      }
      final texts = t.widgetList<SelectableText>(find.byType(SelectableText));
      final reading = texts.map((w) => w.data!).firstWhere((s) {
        final label = find.text(s).hitTestable();
        if (!s.startsWith('历史') || label.evaluate().isEmpty) return false;
        final y = t.getCenter(label).dy;
        return y > 250 && y < 500;
      });
      final y = t.getCenter(find.text(reading)).dy;
      f.shared.add({
        'id': 'incoming',
        'owner': 'B',
        'role': 'user',
        'text': '新来信',
      });
      await f.session.refresh();
      await t.pumpAndSettle();
      expect(t.getCenter(find.text(reading)).dy, y);
      expect(find.byKey(const Key('chat-new-messages')), findsOneWidget);

      f.postGate = Completer<void>();
      await t.enterText(find.byKey(const Key('cloud-shared-input')), '从历史发送');
      await t.pump();
      await t.tap(find.byKey(const Key('chat-send')));
      await t.pump();
      expect(find.text('从历史发送').hitTestable(), findsOneWidget);
      f.postGate!.complete();
      await t.pumpAndSettle();
      expect(find.text('从历史发送').hitTestable(), findsOneWidget);
      expect(find.byKey(const Key('chat-new-messages')), findsNothing);
      await f.finish(t);
    },
  );
}
