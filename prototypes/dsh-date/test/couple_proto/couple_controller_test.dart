import 'dart:convert';

import 'package:dsh_app/couple_proto/couple_controller.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;

/// The service and both identities are loopback-only; the app still validates
/// its public TLS origin, while this test transport talks to the local fixture.
class FixtureHttp extends http.BaseClient {
  FixtureHttp(this.port);
  final int port;
  final inner = http.Client();
  bool loseMeetingReply = false, rejectWrite = false;
  final operations = <String>[];
  int deltaReads = 0;
  @override
  Future<http.StreamedResponse> send(http.BaseRequest source) async {
    if (source.url.host != 'pair-fixture.invalid')
      throw StateError('unexpected test origin');
    final request =
        http.Request(
            source.method,
            source.url.replace(scheme: 'http', host: '127.0.0.1', port: port),
          )
          ..followRedirects = false
          ..headers.addAll(source.headers)
          ..bodyBytes = await source.finalize().toBytes();
    final persist = request.url.path.endsWith('/life/meeting');
    if (request.url.path.endsWith('/life/changes')) deltaReads++;
    if (persist)
      operations.add((jsonDecode(request.body) as Map)['request_id'] as String);
    if (persist && rejectWrite) {
      return http.StreamedResponse(
        Stream.value(
          utf8.encode('{"error":{"code":"forbidden","message":"当前账号无权修改"}}'),
        ),
        403,
      );
    }
    final response = await inner.send(request);
    if (persist && loseMeetingReply) {
      loseMeetingReply = false;
      await response.stream.drain<void>();
      throw http.ClientException(
        'fixture: server committed; response was lost',
      );
    }
    return response;
  }

  @override
  void close() => inner.close();
}

class MemoryVault extends CoupleVault {
  String? value;
  @override
  Future<String?> read() async => value;
  @override
  Future<void> write(String data) async {
    value = data;
  }

  @override
  Future<void> clear() async {
    value = null;
  }
}

void main() {
  test('half-hour tools only accept explicit affirmative requests and compute a local calendar rollover', () {
    final m = Meeting(
      id: '1',
      title: '散步',
      version: 1,
      day: '2026-12-31',
      clock: '23:45',
      place: '东门',
      address: '',
    );
    expect(DelayProposal.forMeeting(m).after, '2027-01-01 00:15');
    for (final x in ['把约会推迟半小时', '请把这次约会推迟半个小时', '@DP 帮我把约会推迟30分钟']) {
      expect(DelayProposal.matches(x), isTrue, reason: x);
    }
    for (final x in ['别把约会推迟半小时', '推迟半小时吗？', '推迟半小时再改地点', '推迟两小时']) {
      expect(DelayProposal.matches(x), isFalse, reason: x);
    }
    expect(
      () => DelayProposal.forMeeting(
        Meeting(
          id: '2',
          title: '?',
          version: 2,
          day: '',
          clock: '',
          place: '',
          address: '',
        ),
      ),
      throwsA(anything),
    );
  });
  const port = int.fromEnvironment('COUPLE_PROTO_TEST_PORT');
  test(
    'R2 two accounts keep the private DP turn private, commit the same meeting once across midnight and notify the peer',
    () async {
      final ct = FixtureHttp(port), peer = FixtureHttp(port);
      final vault = MemoryVault(), otherVault = MemoryVault();
      var a = CoupleController(client: ct, vault: vault);
      var b = CoupleController(client: peer, vault: otherVault);
      final ids = <CoupleController>[a, b];
      addTearDown(() {
        for (final c in ids) c.dispose();
      });
      const origin = 'https://pair-fixture.invalid';
      await a.login(origin, 'a@example.test', 'fixture-only');
      await b.login(origin, 'b@example.test', 'fixture-only');
      expect(a.error, isNull);
      expect(b.error, isNull);
      final token = (jsonDecode(vault.value!) as Map)['token'] as String;
      final direct = http.Client();
      addTearDown(direct.close);
      Future<Map<String, dynamic>> api(
        String path, [
        Map<String, dynamic>? body,
      ]) async {
        final uri = Uri.parse('http://127.0.0.1:$port/v1/$path');
        final headers = {
          'Authorization': 'Bearer $token',
          'Content-Type': 'application/json',
        };
        final res = body == null
            ? await direct.get(uri, headers: headers)
            : await direct.post(uri, headers: headers, body: jsonEncode(body));
        expect(res.statusCode, 200, reason: res.body);
        return jsonDecode(utf8.decode(res.bodyBytes)) as Map<String, dynamic>;
      }

      final stamp = DateTime.now().microsecondsSinceEpoch.toString();
      final title = '跨年约会-$stamp';
      await api('modules', {
        'request_id': 'seed_$stamp',
        'module': 'calendar',
        'title': title,
        'body': '保留原文',
        'confirmed': true,
      });
      final module = ((await api('state'))['modules'] as List).firstWhere(
        (r) => r['title'] == title,
      );
      final key = module['id'] as String;
      await api('modules/$key/life/meeting', {
        'request_id': 'plan_$stamp',
        'version': module['version'],
        'day': '2026-12-31',
        'clock': '23:45',
        'place': '东门',
        'address': '海州市湖滨路18号',
      });
      await a.refresh();
      await b.refresh();
      await a.selectMeeting(key);
      await b.selectMeeting(key);
      expect(a.selected?.id, key);
      expect(b.selected?.clock, '23:45');
      await a.send('只在我私下讨论的内容-$stamp');
      expect(a.messages.where((m) => m['role'] == 'assistant'), isNotEmpty);
      await b.refresh();
      expect(b.messages, isEmpty);
      await b.setScope('shared');
      expect(b.messages, isEmpty);
      Future<List<dynamic>> currentDraftIds() async =>
          ((await api('modules/$key/conversation?scope=private'))['drafts']
                  as List)
              .where((d) => d['status'] == 'pending')
              .map((d) => d['id'])
              .toList();
      await a.send('调整集合地点到书店');
      final otherEditable = await currentDraftIds();
      expect(otherEditable, isNotEmpty);
      await a.send('把约会推迟半小时');
      expect(await currentDraftIds(), otherEditable);
      expect(
        a.messages.where((m) => m['role'] == 'user').last['text'],
        '把约会推迟半小时',
      );
      expect(a.error, isNull);
      expect(a.proposal?.after, '2027-01-01 00:15');
      await b.refresh();
      expect(b.selected?.clock, '23:45');
      expect(b.proposal, isNull);

      // Re-open the sender's saved proposal before the first write.
      a.setForeground(false);
      final resumedHttp = FixtureHttp(port);
      a = CoupleController(client: resumedHttp, vault: vault);
      ids.add(a);
      await a.restore();
      await a.selectMeeting(key);
      expect(a.proposal?.before, '2026-12-31 23:45');
      resumedHttp.loseMeetingReply = true;
      await a.confirm();
      expect(a.proposal, isNotNull);
      expect(a.error, isNotNull);
      final cutoff = DateTime.now().add(const Duration(seconds: 5));
      while (b.selected?.clock != '00:15' && DateTime.now().isBefore(cutoff)) {
        await Future<void>.delayed(const Duration(milliseconds: 60));
      }
      expect(b.selected?.day, '2027-01-01');
      expect(b.selected?.clock, '00:15');
      expect(b.selected?.place, '东门');
      expect(b.selected?.address, '海州市湖滨路18号');
      expect(peer.deltaReads, greaterThan(0));
      await a.confirm();
      expect(a.error, isNull);
      expect(a.proposal, isNull);
      expect(resumedHttp.operations.length, 2);
      expect(resumedHttp.operations.toSet().length, 1);
      expect(await currentDraftIds(), otherEditable);
      expect(a.selected?.version, (module['version'] as int) + 2);
      final records = ((await api('state'))['modules'] as List).where(
        (m) => m['title'] == title,
      );
      expect(records.length, 1);
      expect(records.single['body'], '保留原文');

      await a.send('把约会推迟半小时');
      expect(a.proposal?.after, '2027-01-01 00:45');
      await api('modules/$key/life/meeting', {
        'request_id': 'edit_$stamp',
        'version': a.selected!.version,
        'day': '2027-01-01',
        'clock': '02:30',
        'place': '北门',
        'address': '',
      });
      await a.confirm();
      expect(a.error, contains('已发生变化'));
      expect(a.selected?.clock, '02:30');
      expect(a.proposal, isNull);
      await a.send('把约会推迟半小时');
      resumedHttp.rejectWrite = true;
      await a.confirm();
      expect(a.error, contains('无权修改'));
      await b.refresh();
      expect(b.selected?.clock, '02:30');
      await a.cancel();
      expect(a.proposal, isNull);
      expect(await currentDraftIds(), otherEditable);

      b.setForeground(false);
      b = CoupleController(client: FixtureHttp(port), vault: otherVault);
      ids.add(b);
      await b.restore();
      await b.selectMeeting(key);
      expect(b.selected?.clock, '02:30');
      expect(b.scope, 'private');
      expect(b.messages, isEmpty);
      await b.setScope('shared');
      expect(b.messages, isEmpty);
      await b.send('一起确认集合地点-$stamp');
      expect(b.error, isNull);
      await a.setScope('shared');
      expect(a.messages.any((m) => m['text'] == '一起确认集合地点-$stamp'), isTrue);
      expect(
        a.messages.any((m) => (m['text'] as String).contains('只在我私下')),
        isFalse,
      );
      await a.setScope('private');
      expect(
        a.messages.any((m) => (m['text'] as String).contains('只在我私下')),
        isTrue,
      );
      await api('logout', {});
      await a.refresh();
      expect(a.signedIn, isFalse);
      expect(a.messages, isEmpty);
      expect(a.proposal, isNull);
      expect(a.meetings, isEmpty);
      expect(vault.value, isNull);
      await a.login('http://example.invalid', 'b@example.test', 'fixture-only');
      expect(a.signedIn, isFalse);
      expect(a.messages, isEmpty);
    },
    skip: port == 0
        ? 'Set COUPLE_PROTO_TEST_PORT to the local synthetic R2 fixture.'
        : false,
  );
}
