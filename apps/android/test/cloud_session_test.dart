import 'dart:convert';

import 'package:couple_app/src/services/cloud_session.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';

class MemoryVault extends SessionVault {
  String? entry;
  @override
  Future<String?> read() async => entry;
  @override
  Future<void> save(String value) async => entry = value;
  @override
  Future<void> remove() async => entry = null;
}

void main() {
  test('rejects unprotected public origins, credentials and query tokens', () {
    for (final raw in [
      'http://my-server.test',
      'https://test:secret@my.test',
      'https://my.test?token=tok',
      'file://test/private',
    ]) {
      expect(() => serviceUri(raw), throwsA(isA<CloudError>()));
    }
    expect(
      serviceUri('https://private.test/couple/').toString(),
      'https://private.test/couple',
    );
    expect(serviceUri('http://127.0.0.1:18787').host, '127.0.0.1');
  });
  test(
    'membership revocation wipes the vault and state, model denial does not',
    () async {
      String? blocked;
      final vault = MemoryVault();
      final session = CloudSession(
        vault: vault,
        client: MockClient((req) async {
          if (req.url.path == '/v1/login') {
            return http.Response(
              jsonEncode({'token': 'test-only-session'}),
              200,
            );
          }
          if (blocked != null) {
            return http.Response(
              jsonEncode({
                'error': {'code': blocked, 'message': 'denied'},
              }),
              403,
            );
          }
          expect(req.headers['Authorization'], 'Bearer test-only-session');
          return http.Response(
            jsonEncode({
              'paired': true,
              'user': {'id': 'alice'},
              'messages': {'shared': [], 'private': []},
            }),
            200,
          );
        }),
      );
      addTearDown(session.dispose);
      await session.login(
        'https://fixture.test',
        'a@example.test',
        'private-password',
      );
      expect(vault.entry, isNot(contains('private-password')));
      blocked = 'model_access';
      await expectLater(
        session.request('POST', '/v1/messages', {}),
        throwsA(isA<CloudError>()),
      );
      expect(session.signedIn, isTrue);
      blocked = 'channel_forbidden';
      await expectLater(
        session.request('POST', '/v1/messages', {}),
        throwsA(isA<CloudError>()),
      );
      expect(session.signedIn, isFalse);
      expect(session.state, isEmpty);
      expect(vault.entry, isNull);
    },
  );

  const origin = String.fromEnvironment('COUPLE_FIXTURE_URL');
  test(
    'two real HTTP clients restore, share confirmed items and discard revoked memory',
    () async {
      final aVault = MemoryVault();
      final a = CloudSession(vault: aVault),
          b = CloudSession(vault: MemoryVault()),
          reopened = CloudSession(vault: aVault);
      addTearDown(() {
        a.dispose();
        b.dispose();
        reopened.dispose();
      });
      Future<void> message(CloudSession s, String scope, String value) =>
          s.mutate('POST', '/v1/messages', {
            'scope': scope,
            'text': value,
            'request_id': newRequestId(),
          });
      await a.login(origin, 'a@example.test', 'fixture-only');
      await b.login(origin, 'b@example.test', 'fixture-only');
      expect(a.state['mode'], 'fixture');
      expect(a.user['id'], isNot(b.user['id']));
      final originalDrafts = b.rows('drafts').map((d) => d['id']).toSet();
      await message(a, 'private', '我不喜欢人多');
      var mem = a.rows('memories').firstWhere((m) => m['scope'] == 'candidate');
      await b.refresh();
      expect(b.rows('memories').where((m) => m['id'] == mem['id']), isEmpty);
      expect(
        b.messages('private').where((m) => m['text'] == '我不喜欢人多'),
        isEmpty,
      );
      await a.mutate('PUT', '/v1/memories/${mem['id']}', {
        'version': mem['version'],
        'scope': 'shared',
        'text': '我不喜欢人多',
      });
      await message(b, 'shared', '@AI 周六想出去，预算 200 元');
      await a.refresh();
      expect(a.messages('shared'), b.messages('shared'));
      final d = a
          .rows('drafts')
          .firstWhere(
            (d) => !originalDrafts.contains(d['id']) && d['scope'] == 'shared',
          );
      final items = [
        for (final item in d['items']) Map<String, dynamic>.from(item as Map),
      ];
      items.first['body'] = '周六 16:00 在安静的公园见';
      final confirm = {'version': d['version'], 'items': items};
      await a.mutate('POST', '/v1/drafts/${d['id']}/confirm', confirm);
      final count = a.rows('modules').length;
      await b.mutate('POST', '/v1/drafts/${d['id']}/confirm', confirm);
      expect(b.rows('modules').length, count);
      expect(
        b.rows('modules').map((m) => m['body']),
        contains(items.first['body']),
      );
      await reopened.restore();
      expect(reopened.user['id'], a.user['id']);
      expect(reopened.rows('modules'), b.rows('modules'));
      mem = a.rows('memories').firstWhere((m) => m['id'] == mem['id']);
      await a.mutate('PUT', '/v1/memories/${mem['id']}', {
        'version': mem['version'],
        'scope': 'private',
        'text': '我喜欢上午去',
      });
      await b.refresh();
      expect(b.rows('memories').where((m) => m['id'] == mem['id']), isEmpty);
      await a.logout();
      await expectLater(reopened.refresh(), throwsA(isA<CloudError>()));
      expect(reopened.state, isEmpty);
      await b.logout();
    },
    skip: origin.isEmpty
        ? 'Set COUPLE_FIXTURE_URL to a fresh loopback fixture for HTTP acceptance.'
        : false,
  );
}
