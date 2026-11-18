import 'dart:async';
import 'dart:convert';
import 'dart:math';

import 'package:flutter/foundation.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:http/http.dart' as http;

typedef Json = Map<String, dynamic>;

class CloudError implements Exception {
  const CloudError(this.message, [this.status = 0, this.code = 'network']);
  final String message;
  final int status;
  final String code;
  @override
  String toString() => message;
}

String newRequestId() {
  final rng = Random.secure();
  final bytes = List.generate(16, (_) => rng.nextInt(256));
  bytes[6] = (bytes[6] & 15) | 64;
  bytes[8] = (bytes[8] & 63) | 128;
  final hex = bytes.map((n) => n.toRadixString(16).padLeft(2, '0')).join();
  return '${hex.substring(0, 8)}-${hex.substring(8, 12)}-${hex.substring(12, 16)}-${hex.substring(16, 20)}-${hex.substring(20)}';
}

Uri serviceUri(String raw) {
  final uri = Uri.tryParse(raw.trim());
  if (uri == null ||
      !uri.hasAuthority ||
      uri.host.isEmpty ||
      uri.userInfo.isNotEmpty ||
      uri.hasQuery ||
      uri.hasFragment ||
      !(uri.scheme == 'https' ||
          (kDebugMode &&
              uri.scheme == 'http' &&
              ['localhost', '127.0.0.1', '::1'].contains(uri.host)))) {
    throw const CloudError('请输入 Muse 提供的 HTTPS 产品服务地址。');
  }
  return uri.replace(path: uri.path.replaceAll(RegExp(r'/+$'), ''));
}

class SessionVault {
  const SessionVault();
  static const storage = FlutterSecureStorage();
  Future<String?> read() => storage.read(key: 'couple.product.session');
  Future<void> save(String value) =>
      storage.write(key: 'couple.product.session', value: value);
  Future<void> remove() => storage.delete(key: 'couple.product.session');
}

class CloudSession extends ChangeNotifier {
  CloudSession({http.Client? client, this.vault = const SessionVault()})
    : _client = client ?? http.Client();
  final http.Client _client;
  final SessionVault vault;
  String endpoint = const String.fromEnvironment('COUPLE_SERVICE_URL');
  String _token = '';
  int _epoch = 0;
  int _syncNumber = 0;
  Json state = {};
  Json get user => (state['user'] as Json?) ?? {};
  bool get signedIn => _token.isNotEmpty;
  bool get paired => state['paired'] == true;
  String? connectionError;
  bool _closed = false;
  Timer? _timer;
  bool _syncing = false;
  List<Json> rows(String key) =>
      (state[key] as List? ?? []).whereType<Json>().toList();
  List<Json> messages(String scope) =>
      ((state['messages'] as Json?)?[scope] as List? ?? [])
          .whereType<Json>()
          .toList();
  void _updated() {
    if (!_closed) notifyListeners();
  }

  Future<void> _checkServiceVersion() async {
    final health = await request('GET', '/v1/health');
    if (health is! Json || health['ok'] != true || health['schema'] != 3) {
      throw const CloudError(
        '这个地址还没有匹配的产品服务。请使用 Muse 为 0.4 测试版核准的 HTTPS 地址。',
        409,
        'service_version',
      );
    }
  }

  Future<void> restore() async {
    final raw = await vault.read();
    if (raw == null) return;
    final data = jsonDecode(raw) as Json;
    endpoint = serviceUri(data['endpoint'] as String).toString();
    await _checkServiceVersion();
    _token = data['token'] as String;
    if (_token.isEmpty) return;
    await refresh();
    setPolling(true);
  }

  Future<void> login(String address, String email, String password) async {
    if (signedIn) throw const CloudError('请先退出当前会话。');
    endpoint = serviceUri(address).toString();
    await _checkServiceVersion();
    final value = await request('POST', '/v1/login', {
      'email': email.trim(),
      'password': password,
    }) as Json;
    final token = value['token'];
    if (token is! String || token.isEmpty) {
      throw const CloudError('服务端没有返回有效会话。');
    }
    _epoch++;
    _token = token;
    try {
      await vault.save(jsonEncode({'token': token, 'endpoint': endpoint}));
    } catch (_) {
      try {
        await request('POST', '/v1/logout');
      } catch (_) {}
      await _forget();
      throw const CloudError('设备未能安全保存会话，请重试。');
    }
    await refresh();
    setPolling(true);
  }

  Future<dynamic> request(String method, String path, [Json? body]) async {
    if (!path.startsWith('/v1/')) throw ArgumentError.value(path);
    final epoch = _epoch;
    final req = http.Request(method, Uri.parse('${serviceUri(endpoint)}$path'))
      ..followRedirects = false;
    req.headers['Accept'] = 'application/json';
    if (_token.isNotEmpty) req.headers['Authorization'] = 'Bearer $_token';
    if (body != null) {
      req.headers['Content-Type'] = 'application/json; charset=utf-8';
      req.bodyBytes = utf8.encode(jsonEncode(body));
    }
    final modelRequest =
        method == 'POST' &&
        (path == '/v1/messages' ||
            path == '/v1/games' ||
            path == '/v1/ai/tools' ||
            path == '/v1/ai/attachments' ||
            path.endsWith('/conversation'));
    late final http.Response response;
    try {
      response = await _client
          .send(req)
          .then(http.Response.fromStream)
          .timeout(Duration(seconds: modelRequest ? 120 : 25));
    } on TimeoutException {
      throw const CloudError('服务响应超时，请检查连接并重试。');
    } on http.ClientException {
      throw const CloudError('无法连接产品服务，请检查网络和 HTTPS 地址。');
    }
    if (_epoch != epoch || _closed) throw const CloudError('此会话已结束。', 401);
    dynamic payload;
    try {
      payload = jsonDecode(utf8.decode(response.bodyBytes));
    } on FormatException {
      payload = null;
    }
    final status = response.statusCode;
    if (status < 200 || status >= 300) {
      final error = payload is Json ? payload['error'] : null;
      final msg = error is Json ? error['message'] : null;
      final code = error is Json ? error['code'] : null;
      final revoked =
          status == 403 &&
          (path == '/v1/state' ||
              const {
                'channel_forbidden',
                'not_paired',
                'not_member',
              }.contains(code));
      if (_token.isNotEmpty && (status == 401 || revoked)) {
        await _forget();
      }
      final fallback = switch (status) {
        401 => '登录凭据无效或会话已过期，请重新登录。',
        403 => '此账号未获该空间的访问权限，请由 Muse 核对配对与频道。',
        409 => '内容有新版本，请刷新后重新核对。',
        429 => '服务调用已达限额，请稍后再试。',
        >= 500 => '服务暂不可用，请稍后再试。',
        _ => '产品服务拒绝了请求（$status）。',
      };
      throw CloudError(
        msg is String && msg.isNotEmpty ? msg : fallback,
        status,
        code?.toString() ?? 'service',
      );
    }
    if (payload == null && status != 204) {
      throw const CloudError('响应格式有误，请核对产品服务地址。');
    }
    return payload;
  }

  Future<void> refresh() async {
    if (!signedIn) return;
    final id = ++_syncNumber;
    final epoch = _epoch;
    try {
      final next = await request('GET', '/v1/state');
      if (next is! Json || next['user'] is! Json || next['messages'] is! Json) {
        throw const CloudError('服务端未返回完整的空间数据。');
      }
      if (id != _syncNumber || epoch != _epoch) return;
      state = next;
      connectionError = null;
    } catch (e) {
      if (id == _syncNumber && epoch == _epoch) connectionError = e.toString();
      rethrow;
    } finally {
      _updated();
    }
  }

  Future<dynamic> mutate(String method, String path, [Json? body]) async {
    try {
      final result = await request(method, path, body);
      // A confirmed write must not be submitted twice if the following read fails.
      try {
        await refresh();
      } on CloudError {
        /* surfaced by connection status */
      }
      return result;
    } on CloudError catch (e) {
      if (e.status == 409) {
        try {
          await refresh();
        } catch (_) {}
      }
      rethrow;
    }
  }

  void setPolling(bool active) {
    _timer?.cancel();
    if (!active || !signedIn || _closed) return;
    _timer = Timer.periodic(const Duration(seconds: 4), (_) async {
      if (_syncing) return;
      _syncing = true;
      try {
        await refresh();
      } catch (_) {
      } finally {
        _syncing = false;
      }
    });
  }

  Future<void> logout() async {
    if (signedIn) await request('POST', '/v1/logout');
    await _forget();
  }

  Future<void> forgetDevice() => _forget();

  Future<void> _forget() async {
    _epoch++;
    _syncNumber++;
    _token = '';
    state = {};
    connectionError = null;
    setPolling(false);
    try {
      await vault.remove();
    } finally {
      _updated();
    }
  }

  @override
  void dispose() {
    _closed = true;
    _timer?.cancel();
    _client.close();
    super.dispose();
  }
}
