import 'dart:math' as math;

import 'package:material_ui/material_ui.dart';
import 'package:url_launcher/url_launcher.dart';

import '../data/profile_questionnaire.dart';
import '../services/cloud_session.dart';
import 'cloud_records.dart' show MemoryEditor;
import 'theme.dart';

Map<String, dynamic> _map(dynamic value) =>
    value is Map ? Map<String, dynamic>.from(value) : {};
Future<bool> _confirm(
  BuildContext context,
  String title,
  String detail,
  String action,
) async {
  return await showDialog<bool>(
        context: context,
        builder: (context) => AlertDialog(
          title: Text(title),
          content: SingleChildScrollView(child: Text(detail)),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context, false),
              child: const Text('取消'),
            ),
            FilledButton(
              onPressed: () => Navigator.pop(context, true),
              child: Text(action),
            ),
          ],
        ),
      ) ??
      false;
}

class CloudProfilesScreen extends StatefulWidget {
  const CloudProfilesScreen({
    required this.session,
    this.openPrivateChat,
    super.key,
  });
  final CloudSession session;
  final VoidCallback? openPrivateChat;
  @override
  State<CloudProfilesScreen> createState() => _ProfilesState();
}

class _ProfilesState extends State<CloudProfilesScreen> {
  bool partner = false;
  bool saving = false;
  String? error;

  Future<void> change(String method, String path, Json? body) async {
    setState(() {
      saving = true;
      error = null;
    });
    try {
      await widget.session.mutate(method, path, body);
    } catch (e) {
      if (mounted) setState(() => error = e.toString());
    } finally {
      if (mounted) setState(() => saving = false);
    }
  }

  Future<void> discuss(Json memory) async {
    if (saving) return;
    setState(() {
      saving = true;
      error = null;
    });
    try {
      await widget.session.mutate('POST', '/v1/profile-focus/${memory['id']}', {
        'version': memory['version'],
      });
      if (mounted) widget.openPrivateChat?.call();
    } catch (e) {
      if (mounted) setState(() => error = e.toString());
    } finally {
      if (mounted) setState(() => saving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final session = widget.session;
    final selfId = session.user['id'];
    final profiles = session.rows('profiles');
    final profile =
        profiles
            .where((p) => partner ? p['owner'] != selfId : p['owner'] == selfId)
            .firstOrNull ??
        {};
    final own = !partner;
    final chatAvailable =
        session.state['profile_mode'] is Json && widget.openPrivateChat != null;
    final portrait = own
        ? _map(session.state['daily_portrait'])
        : <String, dynamic>{};
    final observations = (portrait['observations'] as List? ?? const [])
        .whereType<Json>();
    final pending = (portrait['pending'] as List? ?? const [])
        .whereType<Json>();
    final ownMemories = {
      for (final row in session.rows('memories'))
        if (row['owner'] == selfId) row['id']: row,
    };
    final published = profile['published'] == true;
    final data = _map(own ? profile['published_data'] : profile['data']);
    final life = _map(data['life']);
    final comm = _map(data['communication']);
    final scale = _map(data['mini_ipip']);
    final scores = _map(scale['scores']);
    final version = profile['version'] as int? ?? 0;
    final memories = session
        .rows('memories')
        .where(
          (m) =>
              m['scope'] == 'shared' &&
              (own ? m['owner'] == selfId : m['owner'] != selfId),
        )
        .toList();
    return ListView(
      padding: const EdgeInsets.fromLTRB(22, 18, 22, 32),
      children: [
        Text('我们的档案', style: Theme.of(context).textTheme.headlineMedium),
        const SizedBox(height: 12),
        Wrap(
          spacing: 8,
          children: [
            ChoiceChip(
              label: const Text('我'),
              selected: own,
              onSelected: (_) => setState(() => partner = false),
            ),
            ChoiceChip(
              label: const Text('伴侣'),
              selected: partner,
              onSelected: (_) => setState(() => partner = true),
            ),
          ],
        ),
        const SizedBox(height: 16),
        if (own && chatAvailable) ...[
          Text('我的每日档案', style: Theme.of(context).textTheme.titleMedium),
          Text(
            observations.isEmpty && pending.isEmpty
                ? '仅自己可见 · 与 DP 聊过的偏好会在这里整理。'
                : '仅自己可见 · 整理于 ${portrait['as_of']}',
            style: editionMeta,
          ),
          if (observations.isNotEmpty) const Text('已确认'),
          for (final observation in observations)
            ListTile(
              contentPadding: EdgeInsets.zero,
              title: Text(observation['text'] as String),
              trailing: ownMemories[observation['id']] == null
                  ? null
                  : const Icon(Icons.chat_bubble_outline),
              onTap: ownMemories[observation['id']] == null || saving
                  ? null
                  : () => discuss(ownMemories[observation['id']]!),
            ),
          if (pending.isNotEmpty) const Text('待我核对'),
          for (final item in pending)
            ListTile(
              contentPadding: EdgeInsets.zero,
              title: Text(item['text'] as String),
              trailing: const Icon(Icons.chevron_right),
              onTap: ownMemories[item['id']] == null
                  ? null
                  : () => Navigator.push(
                      context,
                      MaterialPageRoute(
                        builder: (_) => MemoryEditor(
                          session: session,
                          row: ownMemories[item['id']]!,
                        ),
                      ),
                    ),
            ),
          Align(
            alignment: Alignment.centerLeft,
            child: TextButton.icon(
              onPressed: widget.openPrivateChat,
              icon: const Icon(Icons.chat_bubble_outline),
              label: const Text('和 DP 聊聊我的档案'),
            ),
          ),
          const Divider(),
        ],
        if (chatAvailable &&
            (ownMemories.isNotEmpty || memories.isNotEmpty)) ...[
          Text(
            own ? '我的对话档案' : '伴侣的对话档案',
            style: Theme.of(context).textTheme.titleMedium,
          ),
          for (final row
              in (own
                  ? ownMemories.values.where(
                      (r) =>
                          !pending.any((p) => p['id'] == r['id']) &&
                          !observations.any((p) => p['id'] == r['id']),
                    )
                  : memories))
            ListTile(
              contentPadding: EdgeInsets.zero,
              leading: Icon(
                row['scope'] == 'shared'
                    ? Icons.people_outline
                    : Icons.lock_outline,
              ),
              title: Text(row['text'].toString()),
              subtitle: Text(switch (row['scope']) {
                'shared' => '已向伴侣发布',
                'private' => '仅自己保存',
                _ => '待本人确认',
              }),
              trailing: own ? const Icon(Icons.chat_bubble_outline) : null,
              onTap: own && !saving ? () => discuss(row) : null,
            ),
        ],
        if (!chatAvailable || version > 0)
          Text(published ? '原有档案 · 已发布给伴侣' : '原有档案 · 尚未发布', style: editionMeta),
        if (published) ...[
          if (life.isNotEmpty || comm.isNotEmpty)
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 14),
              child: Text(
                [
                  if (life['interests'] != null) '喜欢${life['interests']}',
                  if (life['avoid'] != null) '想避开${life['avoid']}',
                  if (comm['support'] != null) '希望得到的支持是${comm['support']}',
                ].join('。'),
                style: Theme.of(context).textTheme.titleMedium,
              ),
            ),
          for (final entry in {
            ...lifeQuestions,
            ...communicationQuestions,
          }.entries)
            if (life[entry.key] != null || comm[entry.key] != null)
              ListTile(
                contentPadding: EdgeInsets.zero,
                title: Text(entry.value),
                subtitle: Text('${life[entry.key] ?? comm[entry.key]}'),
              ),
          if (scores.isNotEmpty) ...[
            const Divider(),
            const Text('五维倾向 · Mini-IPIP'),
            Semantics(
              label: '五维人格图，下方有完整的数值。',
              child: SizedBox(
                height: 150,
                child: CustomPaint(painter: _Radar(scores)),
              ),
            ),
            Wrap(
              spacing: 16,
              runSpacing: 8,
              children: [
                for (final e in traitNames.entries)
                  Text('${e.value} ${scores[e.key]} / 5'),
              ],
            ),
            const SizedBox(height: 8),
            const Text('每维来自四道自评题；分数只描述这次回答。'),
          ],
        ],
        if (!chatAvailable && memories.isNotEmpty) ...[
          const Divider(),
          const Text('本人已共享的记忆'),
          for (final m in memories) Text('• ${m['text']}'),
        ],
        if (own) ...[
          const SizedBox(height: 16),
          if (!chatAvailable || version > 0)
            OutlinedButton(
              onPressed: saving
                  ? null
                  : () async {
                      await Navigator.of(context).push<void>(
                        MaterialPageRoute(
                          builder: (_) =>
                              _EditProfile(session: session, profile: profile),
                        ),
                      );
                      if (mounted) setState(() {});
                    },
              child: Text(version == 0 ? '填写我的档案' : '编辑原有档案'),
            ),
          if (published)
            TextButton(
              onPressed: saving
                  ? null
                  : () async {
                      if (await _confirm(
                        context,
                        '撤回已发布档案？',
                        '伴侣和共同 AI 将无法继续读取这份档案。你的草稿仍可编辑。',
                        '撤回发布',
                      )) {
                        await change('POST', '/v1/profile/withdraw', {
                          'version': version,
                        });
                      }
                    },
              child: const Text('撤回发布'),
            ),
          if (version > 0)
            TextButton(
              onPressed: saving
                  ? null
                  : () async {
                      if (await _confirm(
                        context,
                        '删除我的档案？',
                        '这会删除当前档案草稿和已发布版本。单独保存的记忆可在记忆页管理。',
                        '删除档案',
                      )) {
                        await change(
                          'DELETE',
                          '/v1/profile?version=$version',
                          null,
                        );
                      }
                    },
              child: const Text('删除档案'),
            ),
        ],
        if (saving) const LinearProgressIndicator(),
        if (error != null)
          Text(
            error!,
            style: TextStyle(color: Theme.of(context).colorScheme.error),
          ),
      ],
    );
  }
}

class _Radar extends CustomPainter {
  _Radar(this.data);
  final Json data;
  @override
  void paint(Canvas canvas, Size size) {
    final center = size.center(Offset.zero),
        radius = math.min(size.width, size.height) * .43;
    Offset point(int i, double factor) {
      final angle = -math.pi / 2 + 2 * math.pi * i / 5;
      return center +
          Offset(math.cos(angle), math.sin(angle)) * radius * factor;
    }

    Path shape(List<double> lengths) {
      final p = Path();
      for (var i = 0; i < 5; i++) {
        final pos = point(i, lengths[i]);
        if (i == 0) {
          p.moveTo(pos.dx, pos.dy);
        } else {
          p.lineTo(pos.dx, pos.dy);
        }
      }
      return p..close();
    }

    final line = Paint()
      ..color = edge
      ..style = PaintingStyle.stroke;
    for (var level = 1; level <= 5; level++) {
      canvas.drawPath(shape(List.filled(5, level / 5)), line);
    }
    for (var i = 0; i < 5; i++) {
      canvas.drawLine(center, point(i, 1), line);
    }
    final actual = shape([
      for (final key in traitNames.keys)
        ((data[key] as num?)?.toDouble() ?? 0) / 5,
    ]);
    canvas.drawPath(actual, Paint()..color = pine.withValues(alpha: .18));
    canvas.drawPath(
      actual,
      Paint()
        ..color = pine
        ..style = PaintingStyle.stroke
        ..strokeWidth = 2,
    );
  }

  @override
  bool shouldRepaint(_Radar old) => old.data != data;
}

class _EditProfile extends StatefulWidget {
  const _EditProfile({required this.session, required this.profile});
  final CloudSession session;
  final Json profile;
  @override
  State<_EditProfile> createState() => _EditState();
}

class _EditState extends State<_EditProfile> {
  late final Json life, comm;
  late List<int?> answers;
  String? respondedAt;
  bool more = false, scaleOpen = false, working = false;
  int page = 0;
  String? error;
  @override
  void initState() {
    super.initState();
    final data = _map(widget.profile['data']);
    life = _map(data['life']);
    comm = _map(data['communication']);
    final mini = _map(data['mini_ipip']);
    final raw = mini['answers'];
    answers = raw is List && raw.length == 20
        ? raw.cast<int?>().toList()
        : List<int?>.filled(20, null);
    respondedAt = mini['responded_at'] as String?;
  }

  Widget field(MapEntry<String, String> entry, Json group) => Padding(
    padding: const EdgeInsets.only(bottom: 10),
    child: TextFormField(
      key: ValueKey(entry.key),
      initialValue: group[entry.key]?.toString() ?? '',
      maxLength: 240,
      decoration: InputDecoration(labelText: entry.value, counterText: ''),
      onChanged: (v) => group[entry.key] = v.trim(),
    ),
  );

  Future<void> save(bool publish) async {
    final done = answers.every((a) => a != null);
    if (publish) {
      final fields = [
        for (final group in [lifeQuestions, communicationQuestions])
          for (final e in group.entries)
            if ((life[e.key] ?? comm[e.key] ?? '').toString().isNotEmpty)
              '${e.value}：${life[e.key] ?? comm[e.key]}',
      ];
      if (fields.isEmpty && !done) {
        setState(() => error = '先填写一项愿意发布的偏好，或完成五维问卷。');
        return;
      }
      final detail = [
        ...fields,
        if (done) '五维倾向将共享五个分数，原始作答仅本人可见。',
        '发布后，这些资料可用于共同 AI 建议。',
      ].join('\n');
      if (!await _confirm(context, '发布给伴侣？', detail, '确认发布')) return;
    }
    if (!mounted) return;
    setState(() {
      working = true;
      error = null;
    });
    try {
      final body = {
        'life': life,
        'communication': comm,
        if (answers.any((a) => a != null))
          'mini_ipip': {
            ...scaleInfo,
            'answers': answers,
            if (done)
              'responded_at':
                  respondedAt ?? DateTime.now().toUtc().toIso8601String(),
          },
      };
      await widget.session.mutate('PUT', '/v1/profile', {
        'version': widget.profile['version'] ?? 0,
        'published': publish,
        'data': body,
      });

      if (mounted) Navigator.pop(context);
    } catch (e) {
      if (mounted) setState(() => error = e.toString());
    } finally {
      if (mounted) setState(() => working = false);
    }
  }

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(title: const Text('我的档案草稿')),
    body: SafeArea(
      child: ListView(
        padding: const EdgeInsets.all(20),
        children: [
          const Text('以下均可跳过。个人草稿仅本人可见。'),
          const SizedBox(height: 16),
          ...lifeQuestions.entries
              .take(more ? 8 : 4)
              .map((e) => field(e, life)),
          if (!more)
            TextButton(
              onPressed: () => setState(() => more = true),
              child: const Text('继续填写其余生活偏好'),
            ),
          ExpansionTile(
            title: const Text('相处偏好 · 6 项'),
            maintainState: true,
            children: [
              ...communicationQuestions.entries.map((e) => field(e, comm)),
            ],
          ),
          const SizedBox(height: 12),
          ListTile(
            contentPadding: EdgeInsets.zero,
            title: const Text('五维人格 · 自愿作答'),
            subtitle: Text('已填写 ${answers.whereType<int>().length} / 20'),
            trailing: Icon(scaleOpen ? Icons.expand_less : Icons.expand_more),
            onTap: () => setState(() => scaleOpen = !scaleOpen),
          ),
          if (scaleOpen) ...[
            const Text(
              '请对照 Li 等（2012）第 651 页中文原题，按原题号填写。1 非常不同意，2 不同意，3 没有意见，4 同意，5 非常同意。',
            ),
            TextButton.icon(
              icon: const Icon(Icons.open_in_new),
              onPressed: () async {
                try {
                  if (!await launchUrl(
                    Uri.parse(scaleSource),
                    mode: LaunchMode.externalApplication,
                  )) {
                    throw StateError('unavailable');
                  }
                } catch (_) {
                  if (mounted) setState(() => error = '未能打开题本，请检查网络，稍后重试。');
                }
              },
              label: const Text('打开中文题本 · 第 651 页'),
            ),
            for (var i = page * 5; i < page * 5 + 5; i++)
              Padding(
                padding: const EdgeInsets.only(bottom: 8),
                child: DropdownButtonFormField<int>(
                  key: ValueKey('answer-$i'),
                  initialValue: answers[i],
                  decoration: InputDecoration(labelText: '原题第 ${i + 1} 题'),
                  items: [
                    for (var n = 1; n <= 5; n++)
                      DropdownMenuItem(
                        value: n,
                        child: Text(
                          '$n · ${['非常不同意', '不同意', '没有意见', '同意', '非常同意'][n - 1]}',
                        ),
                      ),
                  ],
                  onChanged: (v) => setState(() {
                    answers[i] = v;
                    respondedAt = null;
                  }),
                ),
              ),
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                TextButton(
                  onPressed: page == 0 ? null : () => setState(() => page--),
                  child: const Text('上一组'),
                ),
                Text('${page + 1} / 4'),
                TextButton(
                  onPressed: page == 3 ? null : () => setState(() => page++),
                  child: const Text('下一组'),
                ),
              ],
            ),
          ],
          if (error != null)
            Text(
              error!,
              style: TextStyle(color: Theme.of(context).colorScheme.error),
            ),
          if (working) const LinearProgressIndicator(),
          const SizedBox(height: 16),
          OutlinedButton(
            onPressed: working ? null : () => save(false),
            child: const Text('仅保存个人草稿'),
          ),
          FilledButton(
            onPressed: working ? null : () => save(true),
            child: const Text('预览并发布'),
          ),
        ],
      ),
    ),
  );
}
