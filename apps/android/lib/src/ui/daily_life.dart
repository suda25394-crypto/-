import 'dart:convert';
import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:material_ui/material_ui.dart';
import 'package:url_launcher/url_launcher.dart';

import '../services/cloud_session.dart';
import '../services/device_media.dart';
import 'cloud_records.dart';
import 'dp_module_chat.dart';

const _fields = {
  'title': '标题',
  'body': '内容',
  'day': '日期',
  'clock': '时间',
  'place': '集合点',
  'address': '地图地址',
};
const _actions = {
  'meeting': '更新了集合安排',
  'edit': '修改了记录',
  'scheduled': '排进了日程',
  'to_plan': '把心愿变成了计划',
  'returned': '把计划放回了心愿',
  'wish_again': '重新打开了心愿',
  'remembered': '为出行留下回忆',
  'memory': '添加了共同回忆',
  'photo_removed': '撤回了照片',
};
String _line(Json row) => [
  row['clock'] == '' ? '时间待补充' : row['clock'],
  row['place'] == '' ? '集合点待补充' : row['place'],
].join(' · ');
void _open(BuildContext c, CloudSession s, String id) => Navigator.push(
  c,
  MaterialPageRoute(
    builder: (_) => CloudModuleDetail(session: s, moduleId: id),
  ),
);
Future<void> _map(BuildContext c, Json p) async {
  final address = (p['address'] as String? ?? '').trim();
  if (address.isEmpty) return;
  final place = p['place'] as String? ?? '';
  final search = address.contains(place) ? address : '$address $place';
  var opened = false;
  try {
    opened = await launchUrl(
      Uri.parse('geo:0,0?q=${Uri.encodeComponent(search)}'),
      mode: LaunchMode.externalApplication,
    );
  } catch (_) {}
  if (!opened && c.mounted) {
    await showDialog<void>(
      context: c,
      builder: (dialog) => AlertDialog(
        title: const Text('未找到可用的地图应用'),
        content: SelectableText(search),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialog),
            child: const Text('关闭'),
          ),
        ],
      ),
    );
  }
}

class DailyLifeHome extends StatelessWidget {
  const DailyLifeHome({required this.session, super.key});
  final CloudSession session;
  @override
  Widget build(BuildContext context) => ListenableBuilder(
    listenable: session,
    builder: (c, _) {
      final today = session.rows('today_plans');
      final changes = session.rows('joint_changes');
      final unread = changes.where((e) => e['seen'] != true).length;
      if (today.isEmpty && changes.isEmpty) return const SizedBox.shrink();
      return Padding(
        padding: const EdgeInsets.symmetric(horizontal: 12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            if (today.isNotEmpty)
              Row(
                children: [
                  Expanded(
                    child: TextButton.icon(
                      icon: const Icon(Icons.event_available_outlined),
                      onPressed: () {
                        if (today.length == 1) {
                          _open(c, session, today.first['plan'] as String);
                          return;
                        }
                        showModalBottomSheet<void>(
                          context: c,
                          builder: (sheet) => SafeArea(
                            child: ListView(
                              shrinkWrap: true,
                              children: [
                                for (final p in today)
                                  ListTile(
                                    title: Text(p['title'] as String),
                                    subtitle: Text(_line(p)),
                                    onTap: () {
                                      Navigator.pop(sheet);
                                      _open(c, session, p['plan'] as String);
                                    },
                                  ),
                              ],
                            ),
                          ),
                        );
                      },
                      label: Text(
                        '今天 · ${today.first['title']}\n${_line(today.first)}${today.first['agreed_current'] == false ? ' · 变更待表态' : ''}${today.length > 1 ? ' 等 ${today.length} 项' : ''}',
                        maxLines: 3,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                  ),
                  if ((today.first['address'] as String? ?? '').isNotEmpty)
                    IconButton(
                      tooltip: '地图导航',
                      icon: const Icon(Icons.directions_outlined),
                      onPressed: () => _map(c, today.first),
                    ),
                ],
              ),
            if (changes.isNotEmpty)
              Align(
                alignment: Alignment.centerLeft,
                child: TextButton.icon(
                  onPressed: () => Navigator.push(
                    c,
                    MaterialPageRoute(
                      builder: (_) => _ChangeFeed(session: session),
                    ),
                  ),
                  icon: Icon(
                    unread > 0 ? Icons.markunread_outlined : Icons.history,
                  ),
                  label: Text(unread > 0 ? '伴侣的更新 · $unread 条未读' : '查看伴侣的更新'),
                ),
              ),
          ],
        ),
      );
    },
  );
}

class _ChangeFeed extends StatefulWidget {
  const _ChangeFeed({required this.session});
  final CloudSession session;
  @override
  State<_ChangeFeed> createState() => _ChangeFeedState();
}

class _ChangeFeedState extends State<_ChangeFeed> {
  final earlier = <Json>[];
  final locallyRead = <int>{};
  String? error;
  bool loading = false, last = false;
  Future<void> read(Json e) async {
    try {
      await widget.session.mutate('PUT', '/v1/life/changes/${e['id']}/read');
      if (mounted) {
        setState(() {
          locallyRead.add(e['id'] as int);
          error = null;
        });
      }
    } catch (x) {
      if (mounted) setState(() => error = x.toString());
    }
  }

  Future<void> more(int before) async {
    setState(() => loading = true);
    try {
      final data = await widget.session.request(
        'GET',
        '/v1/life/changes?before=$before',
      );
      final rows = (data['changes'] as List).whereType<Json>().toList();
      if (mounted) {
        setState(() {
          earlier.addAll(rows);
          last = rows.length < 50;
          error = null;
        });
      }
    } catch (x) {
      if (mounted) setState(() => error = x.toString());
    } finally {
      if (mounted) setState(() => loading = false);
    }
  }

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(title: const Text('伴侣的更新')),
    body: ListenableBuilder(
      listenable: widget.session,
      builder: (c, _) {
        final recent = widget.session.rows('joint_changes');
        final unique = <int>{};
        final all = [
          ...recent,
          ...earlier,
        ].where((e) => unique.add(e['id'] as int)).toList();
        return ListView(
          padding: const EdgeInsets.all(12),
          children: [
            if (error != null) Text(error!),
            if (all.isEmpty) const Text('暂时没有共同事项更新。'),
            for (final e in all)
              Builder(
                builder: (c) {
                  final values = e['current'] as Json? ?? {};
                  final previous = e['previous'] as Json? ?? {};
                  final details = (e['fields'] as List)
                      .map((f) {
                        if (values[f] == null) return _fields[f];
                        return '${_fields[f]}：${previous[f] == null ? '' : '${previous[f]} → '}${values[f]}';
                      })
                      .join(' · ');
                  final stale = e['version'] != e['current_version'];
                  final seen =
                      e['seen'] == true || locallyRead.contains(e['id']);
                  return ListTile(
                    title: Text(
                      '${e['author']}${_actions[e['action']] ?? '更新了记录'}',
                    ),
                    subtitle: Text(
                      '${e['title']}${details.isEmpty ? '' : '\n$details'}${stale ? '\n已有更新版本' : ''}',
                      maxLines: 4,
                      overflow: TextOverflow.ellipsis,
                    ),
                    trailing: seen
                        ? const Icon(Icons.done, size: 18)
                        : IconButton(
                            tooltip: '标为已读',
                            icon: const Icon(Icons.mark_email_read_outlined),
                            onPressed: () => read(e),
                          ),
                    onTap: () {
                      if (!seen) read(e);
                      _open(c, widget.session, e['module_id'] as String);
                    },
                  );
                },
              ),
            if (!last && recent.length >= 50)
              TextButton(
                onPressed: loading ? null : () => more(all.last['id'] as int),
                child: Text(loading ? '加载中' : '更早的更新'),
              ),
          ],
        );
      },
    ),
  );
}

class DailyLifeDetails extends StatelessWidget {
  const DailyLifeDetails({
    required this.session,
    required this.record,
    super.key,
  });
  final CloudSession session;
  final Json record;
  @override
  Widget build(BuildContext context) {
    if (!session.state.containsKey('journeys')) return const SizedBox.shrink();
    final key = record['id'] as String, type = record['module'];
    final journey = session
        .rows('journeys')
        .where((j) => [j['plan'], j['wish'], j['memory']].contains(key))
        .firstOrNull;
    final photo = session
        .rows('memory_photos')
        .where((p) => p['memory'] == key)
        .firstOrNull;
    final plan = type == 'calendar' || type == 'date',
        stage = journey?['stage'];
    void edit(String action) => Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => _LifeEditor(
          session: session,
          record: record,
          journey: journey,
          action: action,
        ),
      ),
    );
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        if (plan && journey != null && stage == 'planned') ...[
          Text(
            '${journey['day']} · 北京时间',
            style: Theme.of(context).textTheme.labelLarge,
          ),
          Text(_line(journey)),
          if ((journey['address'] as String? ?? '').isNotEmpty)
            TextButton.icon(
              onPressed: () => _map(context, journey),
              icon: const Icon(Icons.directions),
              label: Text('地图导航 · ${journey['address']}'),
            ),
        ],
        if (type == 'wish' && (stage == null || stage == 'wish'))
          OutlinedButton.icon(
            onPressed: () => edit('meeting'),
            icon: const Icon(Icons.event_outlined),
            label: const Text('排进共同日程'),
          ),
        if (plan && (stage == null || stage == 'planned'))
          Wrap(
            spacing: 6,
            children: [
              TextButton(
                onPressed: () => edit('meeting'),
                child: Text(journey == null ? '设置集合安排' : '修改时间或集合点'),
              ),
              if (journey?['wish'] != null)
                TextButton(
                  onPressed: () => edit('return'),
                  child: const Text('放回原心愿'),
                ),
              TextButton(
                onPressed: () => edit('remember'),
                child: const Text('留下这次出行的回忆'),
              ),
            ],
          ),
        if (journey != null)
          Wrap(
            spacing: 4,
            children: [
              for (final link in {
                'wish': '最初的心愿',
                'plan': stage == 'wish' ? '原计划（已放回）' : '关联计划',
                'memory': '共同回忆',
              }.entries)
                if (journey[link.key] != null && journey[link.key] != key)
                  TextButton.icon(
                    onPressed: () =>
                        _open(context, session, journey[link.key] as String),
                    icon: const Icon(Icons.link, size: 16),
                    label: Text(link.value),
                  ),
            ],
          ),
        if (photo != null)
          Wrap(
            children: [
              OutlinedButton.icon(
                onPressed: () => Navigator.push(
                  context,
                  MaterialPageRoute(
                    builder: (_) => _PhotoScreen(session: session, memory: key),
                  ),
                ),
                icon: const Icon(Icons.image_outlined),
                label: const Text('查看出行照片'),
              ),
              if (photo['owner'] == session.user['id'])
                TextButton(
                  onPressed: () async {
                    if (!await askCloud(
                      context,
                      '撤回出行照片？',
                      '伴侣之后也无法从这条回忆打开照片。',
                      '撤回照片',
                    )) {
                      return;
                    }
                    try {
                      await session.mutate(
                        'DELETE',
                        '/v1/modules/${pathId(record)}/life/photo',
                      );
                    } catch (e) {
                      if (context.mounted) {
                        ScaffoldMessenger.of(
                          context,
                        ).showSnackBar(SnackBar(content: Text(e.toString())));
                      }
                    }
                  },
                  child: const Text('撤回照片'),
                ),
            ],
          ),
      ],
    );
  }
}

class _PhotoScreen extends StatefulWidget {
  const _PhotoScreen({required this.session, required this.memory});
  final CloudSession session;
  final String memory;
  @override
  State<_PhotoScreen> createState() => _PhotoScreenState();
}

class _PhotoScreenState extends State<_PhotoScreen> {
  Future<Uint8List> load() async {
    final r = await widget.session.request(
      'GET',
      '/v1/modules/${Uri.encodeComponent(widget.memory)}/life/photo',
    );
    return base64Decode(r['png'] as String);
  }

  late Future<Uint8List> image = load();
  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(title: const Text('出行照片')),
    body: Center(
      child: ListenableBuilder(
        listenable: widget.session,
        builder: (c, _) {
          if (!widget.session
              .rows('memory_photos')
              .any((e) => e['memory'] == widget.memory)) {
            return const Text('这张照片已撤回。');
          }
          return FutureBuilder<Uint8List>(
            future: image,
            builder: (c, s) {
              if (s.hasError) {
                return TextButton(
                  onPressed: () => setState(() => image = load()),
                  child: const Text('暂时无法读取照片，重试'),
                );
              }
              if (!s.hasData) return const CircularProgressIndicator();
              return InteractiveViewer(
                child: Image.memory(s.data!, semanticLabel: '共同出行照片'),
              );
            },
          );
        },
      ),
    ),
  );
}

Future<Uint8List> _thumbnail(Uint8List original) async {
  if (original.length > 16 * 1024 * 1024) {
    throw const CloudError('请选择 16 MB 以内的照片。');
  }
  final buf = await ui.ImmutableBuffer.fromUint8List(original);
  try {
    final descriptor = await ui.ImageDescriptor.encoded(buf);
    try {
      if (descriptor.width * descriptor.height > 64000000) {
        throw const CloudError('图片尺寸过大。');
      }
      final longest = descriptor.width > descriptor.height
          ? descriptor.width
          : descriptor.height;
      for (final cap in [512, 384, 256]) {
        final ratio = (cap / longest).clamp(0.0, 1.0);
        final codec = await descriptor.instantiateCodec(
          targetWidth: (descriptor.width * ratio).round().clamp(1, cap),
          targetHeight: (descriptor.height * ratio).round().clamp(1, cap),
        );
        try {
          final frame = await codec.getNextFrame();
          try {
            final bytes = await frame.image.toByteData(
              format: ui.ImageByteFormat.png,
            );
            if (bytes != null && bytes.lengthInBytes <= 384 * 1024) {
              return bytes.buffer.asUint8List(
                bytes.offsetInBytes,
                bytes.lengthInBytes,
              );
            }
          } finally {
            frame.image.dispose();
          }
        } finally {
          codec.dispose();
        }
      }
      throw const CloudError('照片压缩后仍过大，请另选一张。');
    } finally {
      descriptor.dispose();
    }
  } finally {
    buf.dispose();
  }
}

class _LifeEditor extends StatefulWidget {
  const _LifeEditor({
    required this.session,
    required this.record,
    this.journey,
    required this.action,
  });
  final CloudSession session;
  final Json record;
  final Json? journey;
  final String action;
  @override
  State<_LifeEditor> createState() => _LifeEditorState();
}

class _LifeEditorState extends State<_LifeEditor> {
  late final day = TextEditingController(
    text:
        widget.journey?['day'] as String? ??
        DateTime.now()
            .toUtc()
            .add(const Duration(hours: 8))
            .toIso8601String()
            .substring(0, 10),
  );
  late final clock = TextEditingController(
    text: widget.journey?['clock'] as String? ?? '',
  );
  late final place = TextEditingController(
    text: widget.journey?['place'] as String? ?? '',
  );
  late final address = TextEditingController(
    text: widget.journey?['address'] as String? ?? '',
  );
  final note = TextEditingController();
  Uint8List? photo;
  bool busy = false;
  String? error, signature;
  String token = newRequestId();
  @override
  void dispose() {
    for (final t in [day, clock, place, address, note]) {
      t.dispose();
    }
    super.dispose();
  }

  Future<void> pick() async {
    setState(() {
      busy = true;
      error = null;
    });
    try {
      final chosen = await DeviceMedia.pick(imageOnly: true);
      if (chosen != null) {
        final value = await _thumbnail(chosen.data);
        if (mounted) setState(() => photo = value);
      }
    } catch (_) {
      if (mounted) setState(() => error = '无法读取这张照片，可重新选择或只留一句话。');
    } finally {
      if (mounted) setState(() => busy = false);
    }
  }

  Future<void> save() async {
    final act = widget.action;
    if (act == 'meeting' &&
        (!RegExp(r'^\d{4}-\d{2}-\d{2}$').hasMatch(day.text.trim()) ||
            (clock.text.trim().isNotEmpty &&
                !RegExp(r'^(?:[01]\d|2[0-3]):[0-5]\d$')
                    .hasMatch(clock.text.trim())))) {
      setState(() => error = '请检查日期和 24 小时制时间。');
      return;
    }
    if (act == 'remember' && note.text.trim().isEmpty && photo == null) {
      setState(() => error = '请留下一句话或选择照片。');
      return;
    }
    final body = <String, dynamic>{
      'version': widget.record['version'],
      if (act == 'meeting') ...{
        'day': day.text.trim(),
        'clock': clock.text.trim(),
        'place': place.text.trim(),
        'address': address.text.trim(),
      },
      if (act == 'remember') ...{
        'note': note.text.trim(),
        'occurred': true,
        if (photo != null) 'photo': base64Encode(photo!),
      },
    };
    final next = jsonEncode(body);
    if (next != signature) {
      token = newRequestId();
      signature = next;
    }
    setState(() {
      busy = true;
      error = null;
    });
    try {
      final reply = await widget.session.mutate(
        'POST',
        '/v1/modules/${pathId(widget.record)}/life/$act',
        {...body, 'request_id': token},
      );
      if (!mounted) return;
      final target = reply['module_id'] as String;
      if (target == widget.record['id']) {
        Navigator.pop(context);
      } else {
        Navigator.pushReplacement(
          context,
          MaterialPageRoute(
            builder: (_) =>
                CloudModuleDetail(session: widget.session, moduleId: target),
          ),
        );
      }
    } catch (e) {
      if (mounted) setState(() => error = e.toString());
    } finally {
      if (mounted) setState(() => busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final act = widget.action;
    return Scaffold(
      appBar: AppBar(
        title: Text(switch (act) {
          'remember' => '留下共同回忆',
          'return' => '放回原心愿',
          _ => '集合安排',
        }),
      ),
      body: ListView(
        padding: const EdgeInsets.all(20),
        children: [
          Text(
            widget.record['title'] as String,
            style: Theme.of(context).textTheme.titleLarge,
          ),
          const SizedBox(height: 12),
          if (act == 'meeting') ...[
            TextField(
              controller: day,
              enabled: !busy,
              decoration: InputDecoration(
                labelText: '日期 · 北京时间（YYYY-MM-DD）',
                suffixIcon: IconButton(
                  tooltip: '选择日期',
                  icon: const Icon(Icons.calendar_month),
                  onPressed: busy
                      ? null
                      : () async {
                          final now = DateTime.now();
                          final d = DateTime.tryParse(day.text) ?? now;
                          final picked = await showDatePicker(
                            context: context,
                            initialDate: d.year < 1900 || d.year > 2199
                                ? now
                                : d,
                            firstDate: DateTime(1900),
                            lastDate: DateTime(2199, 12, 31),
                          );
                          if (picked != null && mounted) {
                            day.text = picked.toIso8601String().substring(
                              0,
                              10,
                            );
                          }
                        },
                ),
              ),
            ),
            TextField(
              controller: clock,
              enabled: !busy,
              decoration: const InputDecoration(labelText: '集合时间 · 例如 14:30'),
            ),
            TextField(
              controller: place,
              enabled: !busy,
              maxLength: 160,
              decoration: const InputDecoration(labelText: '集合点 · 可以稍后补充'),
            ),
            TextField(
              controller: address,
              enabled: !busy,
              maxLength: 240,
              decoration: const InputDecoration(labelText: '地图地址 · 城市和完整地名或门牌'),
            ),
          ],
          if (act == 'return') const Text('计划会保留关联和历史，从原心愿可以再次安排。'),
          if (act == 'remember') ...[
            TextField(
              controller: note,
              enabled: !busy,
              minLines: 2,
              maxLines: 6,
              maxLength: 1500,
              decoration: const InputDecoration(labelText: '这次出行的一句话'),
            ),
            if (photo != null)
              Image.memory(photo!, height: 120, semanticLabel: '待分享的照片'),
            TextButton.icon(
              onPressed: busy ? null : pick,
              icon: const Icon(Icons.add_photo_alternate_outlined),
              label: Text(photo == null ? '添加照片' : '重新选择照片'),
            ),
            if (photo != null)
              TextButton(
                onPressed: busy ? null : () => setState(() => photo = null),
                child: const Text('移除照片'),
              ),
            const Text('发布后配对双方可以查看，同时记录我实际参加过。'),
          ],
          if (error != null)
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 8),
              child: Text(error!),
            ),
          FilledButton(
            onPressed: busy ? null : save,
            child: Text(
              busy
                  ? '保存中'
                  : switch (act) {
                      'remember' => '我已成行，发布共同回忆',
                      'return' => '确认放回心愿',
                      _ => '保存到共同计划',
                    },
            ),
          ),
        ],
      ),
    );
  }
}
