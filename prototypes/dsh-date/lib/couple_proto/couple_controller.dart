import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:math';

import 'package:flutter/foundation.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:http/http.dart' as http;

typedef Json = Map<String, dynamic>;

class CoupleVault {
  const CoupleVault();
  static const _storage = FlutterSecureStorage();
  static const _key = 'couple.prototype.account.v1';
  Future<String?> read() => _storage.read(key: _key);
  Future<void> write(String value) => _storage.write(key: _key, value: value);
  Future<void> clear() => _storage.delete(key: _key);
}

class _ServiceError implements Exception {
  const _ServiceError(this.message, [this.status = 0, this.code = '']);
  final String message, code;
  final int status;
  @override
  String toString() => message;
}

List<Json> _rows(dynamic data) =>
    (data as List? ?? []).whereType<Json>().toList();
String _str(dynamic s) => s is String ? s : '';
String _id() {
  final random = Random.secure();
  return List.generate(
    16,
    (_) => random.nextInt(256).toRadixString(16).padLeft(2, '0'),
  ).join();
}

class Meeting {
  const Meeting({
    required this.id,
    required this.title,
    required this.version,
    required this.day,
    required this.clock,
    required this.place,
    required this.address,
  });
  factory Meeting.fromJson(Json row) => Meeting(
    id: row['id'] as String,
    title: _str(row['title']),
    version: row['version'] as int,
    day: _str(row['day']),
    clock: _str(row['clock']),
    place: _str(row['place']),
    address: _str(row['address']),
  );
  final String id, title, day, clock, place, address;
  final int version;
  Json toJson() => {
    'id': id,
    'title': title,
    'version': version,
    'day': day,
    'clock': clock,
    'place': place,
    'address': address,
  };
}

class DelayProposal {
  DelayProposal(this.meeting, this.day, this.clock);
  final Meeting meeting;
  final String day, clock;
  String get title => meeting.title;
  String get before => '${meeting.day} ${meeting.clock}';
  String get after => '$day $clock';

  static final _command = RegExp(
    r'^(?:@?dp[,，、 ]*)?(?:(?:请|帮我|帮我们|麻烦你|请你)\s*)*(?:(?:把|将)?(?:这(?:次|个|条|场))?(?:我们的|今天的|原来的)?(?:约会|日程|计划|见面|集合)(?:的?(?:时间|安排))?)?(?:推迟|延迟|延后|顺延|往后推|晚)(?:个|了)?(?:半个?小时|三十分钟|30分钟)(?:吧|就好)?[。！!\s]*$',
    caseSensitive: false,
  );
  static bool matches(String text) =>
      _command.hasMatch(text.trim().replaceAll(RegExp(r'\s+'), ''));
  // R2 copywriting turns cannot create edits, even if the model proposes one.
  // Only a confirmed native calendar operation owns the shared schedule write.
  String explanationRequest(String original) =>
      '$original\n请写一句改期确认说明：原定 $before，拟改为 $after。待我确认，地点照旧。';
  static final _explanation = RegExp(
    r'^请写一句改期确认说明：原定 \d{4}-\d{2}-\d{2} \d{2}:\d{2}，拟改为 \d{4}-\d{2}-\d{2} \d{2}:\d{2}。待我确认，地点照旧。$',
  );
  static Json displayMessage(Json row) {
    if (row['role'] != 'user' || row['text'] is! String) return row;
    final lines = (row['text'] as String).split('\n');
    if (lines.length == 2 &&
        matches(lines.first) &&
        _explanation.hasMatch(lines.last)) {
      return {...row, 'text': lines.first};
    }
    return row;
  }

  static DelayProposal forMeeting(Meeting m) {
    final stamp = '${m.day}T${m.clock}:00Z';
    final at = DateTime.tryParse(stamp);
    if (at == null ||
        at.toIso8601String().substring(0, 16) != stamp.substring(0, 16)) {
      throw const _ServiceError('这条约会尚未填写完整的日期和时间，请先在现版日程中补齐。');
    }
    final next = at.add(const Duration(minutes: 30));
    if (next.year > 9999) throw const _ServiceError('目标日期超出可修改范围。');
    final iso = next.toIso8601String();
    return DelayProposal(m, iso.substring(0, 10), iso.substring(11, 16));
  }
}

class CoupleController extends ChangeNotifier {
  CoupleController({http.Client? client, CoupleVault? vault})
    : _http = client ?? http.Client(),
      _vault = vault ?? const CoupleVault();
  final http.Client _http;
  final CoupleVault _vault;
  final Map<String, Json> _actions = {};
  Future<void> _vaultQueue = Future.value();
  bool loading = true, busy = false;
  bool _closed = false, _active = true, _polling = false;
  Timer? _timer;
  int _epoch = 0,
      _view = 0,
      _snapshotTicket = 0,
      _threadTicket = 0,
      _lastEvent = 0;
  DateTime _lastFull = DateTime.fromMillisecondsSinceEpoch(0);
  DateTime _lastThread = DateTime.fromMillisecondsSinceEpoch(0);
  String endpoint = const String.fromEnvironment('COUPLE_SERVICE_URL');
  String _token = '', userName = '', userId = '', scope = 'private';
  String? error, _selectedId;
  List<Meeting> meetings = [];
  List<Json> messages = [];
  bool get signedIn => _token.isNotEmpty;
  Meeting? get selected =>
      meetings.where((m) => m.id == _selectedId).firstOrNull;
  String get _key => '$scope:$_selectedId';
  DelayProposal? get proposal {
    final action = _actions[_key];
    if (action == null || action['ready'] != true || action['delay'] != true)
      return null;
    return DelayProposal.forMeeting(
      Meeting.fromJson(action['meeting'] as Json),
    );
  }

  void _emit() {
    if (!_closed) notifyListeners();
  }

  Future<void> _persist() {
    final captured = signedIn
        ? jsonEncode({
            'endpoint': endpoint,
            'token': _token,
            'actions': _actions,
          })
        : null;
    final save = _vaultQueue
        .catchError((Object _) {})
        .then(
          (_) => captured == null ? _vault.clear() : _vault.write(captured),
        );
    _vaultQueue = save;
    return save;
  }

  static String _address(String input) {
    final uri = Uri.tryParse(input.trim());
    if (uri == null ||
        uri.scheme != 'https' ||
        uri.host.isEmpty ||
        uri.userInfo.isNotEmpty ||
        uri.hasFragment ||
        uri.hasQuery) {
      throw const _ServiceError('请输入现版使用的 HTTPS 产品服务地址。');
    }
    return uri
        .replace(path: uri.path.replaceFirst(RegExp(r'/+$'), ''))
        .toString();
  }

  void _reset() {
    _epoch++;
    _view++;
    _snapshotTicket++;
    _threadTicket++;
    _timer?.cancel();
    _timer = null;
    _token = '';
    userId = '';
    userName = '';
    scope = 'private';
    _selectedId = null;
    meetings = [];
    messages = [];
    _actions.clear();
    _lastEvent = 0;
    _lastFull = DateTime.fromMillisecondsSinceEpoch(0);
  }

  Future<Json> _request(String method, String path, [Json? data]) async {
    final epoch = _epoch;
    final r = http.Request(method, Uri.parse('$endpoint/v1/$path'))
      ..followRedirects = false;
    if (signedIn) r.headers['Authorization'] = 'Bearer $_token';
    r.headers['Accept'] = 'application/json';
    if (data != null) {
      r.headers['Content-Type'] = 'application/json; charset=utf-8';
      r.bodyBytes = utf8.encode(jsonEncode(data));
    }
    late http.Response answer;
    try {
      answer = await _http
          .send(r)
          .then(http.Response.fromStream)
          .timeout(
            Duration(
              seconds: method == 'POST' && path.endsWith('/conversation')
                  ? 125
                  : 14,
            ),
          );
    } on TimeoutException {
      throw const _ServiceError('连接超时。重试同一句会核对原请求，不会额外改期。');
    } on http.ClientException {
      throw const _ServiceError('连接失败，请检查网络和 HTTPS 地址。');
    } on IOException {
      throw const _ServiceError('无法连接产品服务，请检查网络。');
    }
    if (_closed || epoch != _epoch) throw const _ServiceError('当前会话已切换。');
    final decoded = await _decode(answer);
    if (answer.statusCode < 200 || answer.statusCode >= 300) {
      final e = decoded['error'];
      final message = e is Json ? _str(e['message']) : '';
      final code = e is Json ? _str(e['code']) : '';
      if (signedIn &&
          (answer.statusCode == 401 ||
              (answer.statusCode == 403 &&
                  (path == 'state' ||
                      path == 'life/changes' ||
                      {
                        'channel_forbidden',
                        'not_paired',
                        'not_member',
                      }.contains(code))))) {
        _reset();
        await _persist();
        _emit();
      }
      throw _ServiceError(
        message.isEmpty ? '产品服务拒绝了请求（${answer.statusCode}）。' : message,
        answer.statusCode,
        code,
      );
    }
    return decoded;
  }

  Future<Json> _decode(http.Response response) async {
    if (response.bodyBytes.isEmpty) return {};
    try {
      final data = jsonDecode(utf8.decode(response.bodyBytes));
      if (data is Json) return data;
    } on FormatException {
      if (response.statusCode >= 300) return {};
    }
    throw const _ServiceError('产品服务返回格式异常，请核对服务地址。');
  }

  Future<void> _explicit(Future<void> Function() run) async {
    if (busy || _closed) return;
    busy = true;
    error = null;
    _emit();
    try {
      await run();
    } catch (e) {
      if (!_closed) error = e.toString();
    } finally {
      busy = false;
      _emit();
    }
  }

  Future<void> _check() async {
    final health = await _request('GET', 'health');
    if (health['ok'] != true || health['schema'] != 3)
      throw const _ServiceError('该地址不是兼容的双生宇宙 R2 产品服务。');
  }

  Future<void> restore() async {
    try {
      final raw = await _vault.read();
      if (raw == null || _closed) return;
      final saved = jsonDecode(raw) as Json;
      endpoint = _address(saved['endpoint'] as String);
      _token = saved['token'] as String;
      final stored = saved['actions'];
      if (stored is Json) {
        for (final entry in stored.entries) {
          if (entry.value is Json) _actions[entry.key] = entry.value as Json;
        }
      }
      await _check();
      await _snapshot();
      _arm();
    } catch (e) {
      error = e.toString();
    } finally {
      loading = false;
      _emit();
    }
  }

  Future<void> login(String address, String email, String password) =>
      _explicit(() async {
        _reset();
        endpoint = _address(address);
        await _check();
        final result = await _request('POST', 'login', {
          'email': email.trim(),
          'password': password,
        });
        _token = _str(result['token']);
        if (_token.isEmpty || result['paired'] != true) {
          _reset();
          throw const _ServiceError('此账号未登录或尚未配对。');
        }
        try {
          await _persist();
        } catch (_) {
          _reset();
          throw const _ServiceError('设备无法安全保存登录会话。');
        }
        await _snapshot();
        _arm();
      });

  Future<void> logout() => _explicit(() async {
    try {
      if (signedIn) await _request('POST', 'logout');
    } finally {
      _reset();
      await _persist();
    }
  });

  Future<void> _snapshot() async {
    if (!signedIn) return;
    final ticket = ++_snapshotTicket;
    final data = await _request('GET', 'state');
    if (ticket != _snapshotTicket) return;
    final who = data['user'];
    if (data['paired'] != true || who is! Json || _str(who['id']).isEmpty) {
      _reset();
      await _persist();
      throw const _ServiceError('该账号无法访问情侣空间。');
    }
    final journeys = {for (final j in _rows(data['journeys'])) j['plan']: j};
    final next = <Meeting>[];
    for (final row in _rows(data['modules'])) {
      if (!{'calendar', 'date'}.contains(row['module'])) continue;
      final j = journeys[row['id']];
      if (j != null && j['stage'] != 'planned') continue;
      next.add(
        Meeting.fromJson({
          ...row,
          if (j != null) ...{
            'day': j['day'],
            'clock': j['clock'],
            'place': j['place'],
            'address': j['address'],
          },
        }),
      );
    }
    final changed =
        jsonEncode(next.map((m) => m.toJson()).toList()) !=
            jsonEncode(meetings.map((m) => m.toJson()).toList()) ||
        userId != who['id'] ||
        userName != who['name'];
    meetings = next;
    userId = _str(who['id']);
    userName = _str(who['name']);
    if (_selectedId != null && selected == null) {
      _view++;
      _selectedId = null;
      messages = [];
    }
    _lastEvent = _newest(data['joint_changes']);
    _lastFull = DateTime.now();
    if (changed) _emit();
  }

  int _newest(dynamic list) => _rows(list).fold(0, (int largest, row) {
    final id = row['id'];
    return id is int && id > largest ? id : largest;
  });

  Future<void> selectMeeting(String id) async {
    if (busy || !meetings.any((m) => m.id == id)) return;
    if (_selectedId != id) {
      _selectedId = id;
      scope = 'private';
      messages = [];
      _view++;
      error = null;
      _emit();
    }
    await _readView();
  }

  Future<void> setScope(String value) async {
    if (busy ||
        !{'private', 'shared'}.contains(value) ||
        selected == null ||
        scope == value)
      return;
    scope = value;
    messages = [];
    _view++;
    error = null;
    _emit();
    await _readView();
  }

  Future<void> _readView() async {
    final view = _view;
    try {
      await _thread();
    } catch (e) {
      if (view == _view && !_closed) {
        error = e.toString();
        _emit();
      }
    }
  }

  Future<void> _thread() async {
    final meeting = selected;
    if (meeting == null) return;
    final key = _key, view = _view, ticket = ++_threadTicket;
    final data = await _request(
      'GET',
      'modules/${Uri.encodeComponent(meeting.id)}/conversation?scope=$scope',
    );
    if (view != _view || ticket != _threadTicket || key != _key) return;
    final next = _rows(data['messages'])
        .map(DelayProposal.displayMessage)
        .toList();
    final changed = jsonEncode(next) != jsonEncode(messages);
    messages = next;
    _lastThread = DateTime.now();
    final action = _actions[key];
    var ready = false;
    if (action != null &&
        action['ready'] != true &&
        next.any(
          (m) =>
              m['role'] == 'assistant' && m['request_id'] == action['request'],
        )) {
      if (action['delay'] == true) {
        action['ready'] = true;
      } else {
        _actions.remove(key);
      }
      ready = true;
      await _persist();
    }
    if (changed || ready) _emit();
  }

  Future<void> send(String text) => _explicit(() async {
    final meeting = selected;
    final words = text.trim();
    if (meeting == null || words.isEmpty) return;
    if (words.length > 2000) throw const _ServiceError('每次最多可发送 2000 个字。');
    final key = _key;
    final previous = _actions[key];
    if (previous?['ready'] == true) throw const _ServiceError('请先确认或取消当前改期。');
    final delay = DelayProposal.matches(words);
    if (delay) DelayProposal.forMeeting(meeting);
    if (previous != null && previous['text'] != words) {
      await _thread();
      if (_actions[key] != null)
        throw const _ServiceError('上次请求尚未核对，请先重试原句或取消当前操作。');
    }
    final action =
        _actions[key] ??
        {
          'request': _id(),
          'operation': _id(),
          'meeting': meeting.toJson(),
          'text': words,
          'delay': delay,
          'ready': false,
        };
    _actions[key] = action;
    await _persist();
    try {
      await _request(
        'POST',
        'modules/${Uri.encodeComponent(meeting.id)}/conversation',
        {
          'scope': scope,
          'text': action['delay'] == true
              ? DelayProposal.forMeeting(
                  Meeting.fromJson(action['meeting'] as Json),
                ).explanationRequest(words)
              : words,
          'request_id': action['request'],
          'version': (action['meeting'] as Json)['version'],
        },
      );
      await _thread();
    } on _ServiceError catch (e) {
      if (e.status >= 400 &&
          e.status < 500 &&
          e.status != 408 &&
          e.code != 'in_progress') {
        _actions.remove(key);
        await _persist();
      }
      rethrow;
    }
  });

  Future<void> confirm() => _explicit(() async {
    final card = proposal;
    if (card == null) return;
    final key = _key, action = _actions[key]!, m = card.meeting;
    try {
      final result = await _request(
        'POST',
        'modules/${Uri.encodeComponent(m.id)}/life/meeting',
        {
          'request_id': action['operation'],
          'version': m.version,
          'day': card.day,
          'clock': card.clock,
          'place': m.place,
          'address': m.address,
        },
      );
      if (result['module_id'] != m.id)
        throw const _ServiceError('服务返回了不同的日程，请刷新核对。');
    } on _ServiceError catch (e) {
      if (e.status == 409) {
        _actions.remove(key);
        await _persist();
        await _snapshot();
        throw const _ServiceError('这条日程已发生变化，请核对最新时间后重新提议。');
      }
      rethrow;
    }
    _actions.remove(key);
    await _persist();
    await _snapshot();
  });

  Future<void> cancel() => _explicit(() async {
    _actions.remove(_key);
    await _persist();
  });
  Future<void> refresh() async {
    if (!signedIn || _closed) return;
    try {
      await _snapshot();
      await _thread();
      error = null;
      _arm();
    } catch (e) {
      error = e.toString();
    }
    _emit();
  }

  void setForeground(bool value) {
    if (_active == value) return;
    _active = value;
    _timer?.cancel();
    _timer = null;
    if (value && signedIn) unawaited(refresh());
  }

  void _arm() {
    if (!_active || !signedIn || _closed || _timer != null) return;
    _timer = Timer.periodic(
      const Duration(milliseconds: 800),
      (_) => unawaited(_tick()),
    );
  }

  Future<void> _tick() async {
    if (_polling || busy || _closed || !_active || !signedIn) return;
    _polling = true;
    try {
      final delta = await _request('GET', 'life/changes');
      if (_newest(delta['changes']) != _lastEvent ||
          DateTime.now().difference(_lastFull).inSeconds >= 30)
        await _snapshot();
      if (selected != null &&
          DateTime.now().difference(_lastThread).inSeconds >= 4)
        await _thread();
    } on _ServiceError catch (e) {
      if (!signedIn && !_closed) {
        error = e.toString();
        _emit();
      }
    } finally {
      _polling = false;
    }
  }

  @override
  void dispose() {
    _closed = true;
    _epoch++;
    _timer?.cancel();
    _http.close();
    super.dispose();
  }
}
