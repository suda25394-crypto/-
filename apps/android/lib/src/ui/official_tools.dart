import 'dart:convert';

import 'package:flutter/services.dart';
import 'package:material_ui/material_ui.dart';
import 'package:url_launcher/url_launcher.dart';

import '../services/cloud_session.dart';
import '../services/device_media.dart';
import 'cloud_records.dart';

const toolNames = {
  'web': '网页搜索',
  'image_search': '图片搜索',
  'deep_search': '深度搜索',
  'read_url': '阅读链接',
  'search': '独立文字搜索',
  'fetch': '独立网页抓取',
  'vision': '理解图片',
  'parse_text': '提取文档文字',
  'parse_rich': '图文解析',
  'ocr': '识别图片或 PDF',
  'poster_draft': '从海报起草约会',
  'asr': '语音转文字',
  'tts': '朗读文字',
  'title': '生成会话标题',
};
const _files = {
  'image_search',
  'vision',
  'parse_text',
  'parse_rich',
  'ocr',
  'poster_draft',
  'asr',
};
const _online = {'web', 'image_search', 'deep_search', 'read_url'};

class OfficialTools extends StatefulWidget {
  const OfficialTools({
    required this.session,
    required this.scope,
    this.moduleId,
    super.key,
  });
  final CloudSession session;
  final String scope;
  final String? moduleId;
  @override
  State<OfficialTools> createState() => _OfficialToolsState();
}

class _OfficialToolsState extends State<OfficialTools> {
  final text = TextEditingController(),
      language = TextEditingController(),
      region = TextEditingController();
  String kind = 'web';
  String? error, previous, retryId, lastPayload;
  Json? attachment, result;
  List<Json> past = [], savedFiles = [];
  bool busy = false, recording = false, dateAllowed = false, unknown = false;
  Json get scope => {'scope': widget.scope, 'module_id': ?widget.moduleId};
  @override
  void initState() {
    super.initState();
    DeviceMedia.onPlaybackFailure((message) {
      if (mounted) setState(() => error = message);
    });
    _history();
  }

  Future<void> _history() async {
    try {
      final query = Uri(
        queryParameters: {'scope': widget.scope, 'module_id': ?widget.moduleId},
      ).query;
      final json = await widget.session.request('GET', '/v1/ai/tools?$query');
      final media = await widget.session.request(
        'GET',
        '/v1/ai/attachments?$query',
      );
      if (mounted) {
        setState(() {
          past = (json['results'] as List).whereType<Json>().toList();
          savedFiles = (media['attachments'] as List)
              .whereType<Json>()
              .toList();
        });
      }
    } catch (e) {
      if (mounted) setState(() => error = e.toString());
    }
  }

  Future<void> action(Future<void> Function() fn) async {
    if (busy) return;
    setState(() {
      busy = true;
      error = null;
    });
    try {
      await fn();
    } catch (e) {
      if (mounted) {
        setState(() {
          error = e is PlatformException
              ? (e.message ?? '设备操作失败')
              : e.toString();
        });
      }
    } finally {
      if (mounted) setState(() => busy = false);
    }
  }

  Future<void> upload(PickedMedia f) async {
    final value = await widget.session.request('POST', '/v1/ai/attachments', {
      ...scope,
      'name': f.name,
      'mime': f.mime,
      'data_b64': base64Encode(f.data),
    });
    if (mounted) setState(() => attachment = value as Json);
    await _history();
  }

  Future<void> run() async {
    final tags = {
      'language': ifSet(language.text),
      'region': ifSet(region.text),
      'date': dateAllowed
          ? DateTime.now().toIso8601String().substring(0, 10)
          : null,
    }..removeWhere((_, v) => v == null);
    final body = <String, dynamic>{
      ...scope,
      'kind': kind,
      'text': text.text.trim(),
      'previous_id': ?previous,
      if (_files.contains(kind) && attachment != null)
        'attachment_id': attachment!['id'],
      if (tags.isNotEmpty) 'context': tags,
    };
    final signature = jsonEncode(body);
    if (signature != lastPayload || retryId == null) {
      retryId = newRequestId();
      unknown = false;
    }
    lastPayload = signature;
    if (unknown) {
      final agree = await showDialog<bool>(
        context: context,
        builder: (c) => AlertDialog(
          title: const Text('再次调用？'),
          content: const Text('上一请求的扣费状态未知。重新调用可能再次计费。'),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(c, false),
              child: const Text('返回'),
            ),
            TextButton(
              onPressed: () => Navigator.pop(c, true),
              child: const Text('新建请求'),
            ),
          ],
        ),
      );
      if (agree != true) return;
      retryId = newRequestId();
      unknown = false;
    }
    try {
      final v = await widget.session.mutate('POST', '/v1/ai/tools', {
        ...body,
        'request_id': retryId,
      });
      if (!mounted) return;
      setState(() {
        result = v;
        retryId = null;
      });
      await _history();
    } on CloudError catch (e) {
      if (e.code.contains('unknown') || e.code == 'tool_incomplete') {
        unknown = true;
      }
      rethrow;
    }
  }

  String? ifSet(String s) => s.trim().isEmpty ? null : s.trim();
  void change(String type) {
    if (recording) return;
    setState(() {
      kind = type;
      result = null;
      previous = null;
      error = null;
      retryId = null;
    });
  }

  @override
  void dispose() {
    DeviceMedia.onPlaybackFailure(null);
    DeviceMedia.cancel().catchError((_) {});
    DeviceMedia.stop().catchError((_) {});
    text.dispose();
    language.dispose();
    region.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final v = result;
    final current = attachment;
    final src = (v?['sources'] as List? ?? []).whereType<Json>();
    return Scaffold(
      appBar: AppBar(
        title: Text(widget.scope == 'private' ? '私人 DP 工具' : '共同 DP 工具'),
      ),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          Text(
            widget.scope == 'shared'
                ? (kind == 'asr' ? '录音和转写仅自己可见。修订后可发到共同会话。' : '结果在此共同会话内可见。')
                : '本页的结果仅当前账号可见。',
          ),
          if (kind == 'image_search')
            const Text('图片搜索暂限合成联调。当前真实网关无法为此工具限定整轮输出。'),
          if (kind == 'deep_search') const Text('当前额度内先检索一次，再用思考模式整理来源。'),
          DropdownButton<String>(
            isExpanded: true,
            value: kind,
            items: toolNames.entries
                .map(
                  (e) => DropdownMenuItem(value: e.key, child: Text(e.value)),
                )
                .toList(),
            onChanged: busy || recording
                ? null
                : (v) {
                    if (v != null) change(v);
                  },
          ),
          TextField(
            controller: text,
            minLines: 1,
            maxLines: 4,
            maxLength: 2000,
            decoration: InputDecoration(
              labelText:
                  (_online.contains(kind) || {'search', 'fetch'}.contains(kind))
                  ? '公开关键词、网址或追问'
                  : '文字或处理要求',
            ),
          ),
          if (previous != null)
            TextButton(
              onPressed: busy ? null : () => setState(() => previous = null),
              child: const Text('正在沿用上次来源 · 取消关联'),
            ),
          if (_files.contains(kind))
            OutlinedButton.icon(
              icon: const Icon(Icons.attach_file),
              label: const Text('选择文件（最多 4 MiB）'),
              onPressed: busy || recording
                  ? null
                  : () => action(() async {
                      final f = await DeviceMedia.pick(
                        imageOnly: {
                          'vision',
                          'poster_draft',
                          'image_search',
                        }.contains(kind),
                      );
                      if (f != null) await upload(f);
                    }),
            ),
          if (kind == 'asr')
            TextButton.icon(
              icon: const Icon(Icons.mic_none),
              label: Text(recording ? '结束录音' : '录一段语音'),
              onPressed: busy
                  ? null
                  : () => action(() async {
                      if (recording) {
                        try {
                          final f = await DeviceMedia.finish();
                          await upload(f);
                        } finally {
                          if (mounted) setState(() => recording = false);
                        }
                      } else {
                        await DeviceMedia.record();
                        if (mounted) setState(() => recording = true);
                      }
                    }),
            ),
          if (savedFiles.isNotEmpty)
            ExpansionTile(
              title: const Text('本会话的临时附件'),
              children: [
                for (final f in savedFiles)
                  ListTile(
                    title: Text(f['name'].toString()),
                    onTap: busy ? null : () => setState(() => attachment = f),
                  ),
              ],
            ),
          if (current != null)
            ListTile(
              title: Text(current['name'].toString()),
              subtitle: Text(
                '到期 · ${DateTime.fromMillisecondsSinceEpoch((current['expires_at'] as int) * 1000).toLocal()}',
              ),
              trailing: current['owner'] != widget.session.user['id']
                  ? null
                  : IconButton(
                      tooltip: '删除附件',
                      icon: const Icon(Icons.delete_outline),
                      onPressed: busy
                          ? null
                          : () => action(() async {
                              await widget.session.request(
                                'DELETE',
                                '/v1/ai/attachments/${current['id']}',
                              );
                              if (mounted) {
                                setState(() {
                                  attachment = null;
                                  result = null;
                                  previous = null;
                                });
                              }
                              await _history();
                            }),
                    ),
            ),
          ExpansionTile(
            title: const Text('本次自愿提供的上下文'),
            children: [
              CheckboxListTile(
                value: dateAllowed,
                title: const Text('附上今天的日期'),
                onChanged: (v) => setState(() => dateAllowed = v == true),
              ),
              TextField(
                controller: language,
                decoration: const InputDecoration(labelText: '语言（可留空）'),
              ),
              TextField(
                controller: region,
                decoration: const InputDecoration(labelText: '大致地区（可留空）'),
              ),
            ],
          ),
          if (error != null)
            Text(
              error!,
              style: TextStyle(color: Theme.of(context).colorScheme.error),
            ),
          FilledButton(
            onPressed: busy || recording ? null : () => action(run),
            child: Text(busy ? '处理中…' : '运行${toolNames[kind]}'),
          ),
          if (v != null) ...[
            if (v['search_mode'] == 'single_lookup') const Text('本次使用一次公开检索'),
            if (v['search_mode'] == 'same_source') const Text('本次沿用上次来源'),
            if (v['title'] != null)
              Text(
                v['title'].toString(),
                style: Theme.of(context).textTheme.titleMedium,
              ),
            SelectableText((v['text'] ?? '').toString()),
            for (final link in src)
              TextButton(
                onPressed: () => action(() async {
                  final u = Uri.tryParse(link['url'].toString());
                  if (u == null ||
                      !{'http', 'https'}.contains(u.scheme) ||
                      !await launchUrl(
                        u,
                        mode: LaunchMode.externalApplication,
                      )) {
                    throw const CloudError('无法打开此来源。');
                  }
                }),
                child: Text((link['title'] ?? link['url']).toString()),
              ),
            if (_online.contains(v['kind']))
              TextButton(
                onPressed: () => setState(() {
                  previous = v['id'];
                  kind = v['kind'];
                  text.clear();
                }),
                child: const Text('围绕同一来源追问'),
              ),
            if (v['kind'] == 'asr')
              TextButton(
                onPressed: () => Navigator.pop(context, v['text']),
                child: const Text('带回输入框，修订后发送'),
              ),
            if ((v['text'] ?? '').toString().isNotEmpty && v['kind'] != 'tts')
              TextButton(
                onPressed: () => setState(() {
                  kind = 'tts';
                  previous = v['id'];
                  result = null;
                  text.clear();
                }),
                child: const Text('朗读本条内容'),
              ),
            if (v['audio_b64'] is String)
              Wrap(
                children: [
                  TextButton(
                    onPressed: () => action(
                      () => DeviceMedia.play(base64Decode(v['audio_b64'])),
                    ),
                    child: const Text('播放'),
                  ),
                  TextButton(
                    onPressed: () => action(DeviceMedia.stop),
                    child: const Text('停止朗读'),
                  ),
                ],
              ),
            if (v['draft_id'] != null)
              TextButton(
                onPressed: () => action(() async {
                  await widget.session.refresh();
                  final d = widget.session
                      .rows('drafts')
                      .where((x) => x['id'] == v['draft_id'])
                      .firstOrNull;
                  if (d != null && context.mounted) {
                    await Navigator.push(
                      context,
                      MaterialPageRoute(
                        builder: (_) =>
                            DraftEditor(session: widget.session, draft: d),
                      ),
                    );
                  }
                }),
                child: const Text('核对并编辑草稿'),
              ),
          ],
          if (past.isNotEmpty)
            ExpansionTile(
              title: const Text('本会话以前的结果'),
              children: [
                for (final row in past)
                  ListTile(
                    title: Text(toolNames[row['kind']] ?? '结果'),
                    subtitle: Text(
                      (row['text'] ?? row['title'] ?? '').toString(),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                    onTap: busy
                        ? null
                        : () => action(() async {
                            final old = await widget.session.request(
                              'GET',
                              '/v1/ai/tools/${row['id']}',
                            );
                            if (mounted) {
                              setState(() {
                                result = old;
                                kind = old['kind'];
                                previous = null;
                              });
                            }
                          }),
                  ),
              ],
            ),
        ],
      ),
    );
  }
}
