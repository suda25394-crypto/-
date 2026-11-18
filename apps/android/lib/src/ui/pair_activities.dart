import 'dart:math';

import 'package:material_ui/material_ui.dart';

import '../data/pair_activity.dart';
import '../services/cloud_session.dart';
import 'dp_module_chat.dart';

const _ideas = <String, List<(String, String)>>{
  '出门走走': [
    ('交换向导', '每人挑一条平时不会拐进去的小路。轮流带路，最后一起选一处想再来的地方。'),
    ('同色散步', '出发前选一种颜色。沿途各找三样这个颜色的东西，选出最意外的一个。'),
    ('街角声音', '一起安静走三分钟。停下来时，交换刚才听见的、最想让对方也注意到的声音。'),
  ],
  '待在家里': [
    ('客厅点歌台', '各挑一首最近想分享的歌，轮流播放，告诉对方最喜欢的是哪一句。'),
    ('交换小菜单', '各用手边现有的食材给对方搭一份小点心，再一起给今天的组合起个名字。'),
    ('三件小物', '各找三件平时不起眼的东西。让对方挑一件，说说它是什么时候来到你身边的。'),
  ],
  '异地也能玩': [
    ('窗口交换', '各自从窗边选一个小细节，通话时只用三句话描述，让对方猜猜你看见了什么。'),
    ('同步听歌', '选一首两人都没听过的歌，一起按下播放。结束后交换脑海里最先出现的画面。'),
    ('远程一分钟', '各找身边最想给对方看的东西，留一分钟讲讲原因，然后交换。'),
  ],
};

class PairActivitiesPage extends StatelessWidget {
  const PairActivitiesPage({
    required this.session,
    required this.kind,
    super.key,
  });

  final CloudSession session;
  final PairActivity kind;

  void _compose(BuildContext context) => showDialog<void>(
    context: context,
    barrierDismissible: false,
    builder: (_) => _ComposeActivity(kind: kind, session: session),
  );

  @override
  Widget build(BuildContext context) {
    final note = kind == PairActivity.notebook;
    return Scaffold(
      appBar: AppBar(title: Text(kind.label)),
      body: ListenableBuilder(
        listenable: session,
        builder: (_, _) {
          final records = session.rows('modules').where(kind.contains).toList();
          final activities = {
            for (final a in session.rows('activities')) a['module_id']: a,
          };
          final journeys = {
            if (!note)
              for (final j in session.rows('journeys'))
                if (j['wish'] != null) j['wish']: j,
          };
          return ListView.builder(
            padding: const EdgeInsets.fromLTRB(16, 12, 16, 28),
            itemCount: records.length + 1,
            itemBuilder: (context, index) {
              if (index == 0) {
                return Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    FilledButton.icon(
                      key: Key('pair-compose-${kind.name}'),
                      onPressed: () => _compose(context),
                      icon: Icon(
                        note
                            ? Icons.edit_outlined
                            : Icons.auto_awesome_outlined,
                      ),
                      label: Text(note ? '写一张便签' : '抽一张行动签'),
                    ),
                    const SizedBox(height: 16),
                    if (records.isEmpty)
                      Text(
                        note
                            ? '还没有便签。写给对方的第一张，会留在这里。'
                            : '还没有发出的行动签。抽到想试的活动，就可以邀请对方。',
                      ),
                    if (session.connectionError case final error?)
                      Text('同步暂时中断：$error'),
                  ],
                );
              }
              final record = records[index - 1];
              return _SharedActivityCard(
                key: ValueKey(record['id']),
                kind: kind,
                session: session,
                record: record,
                activity: activities[record['id']],
                journey: journeys[record['id']],
              );
            },
          );
        },
      ),
    );
  }
}

class _ComposeActivity extends StatefulWidget {
  const _ComposeActivity({required this.kind, required this.session});
  final PairActivity kind;
  final CloudSession session;

  @override
  State<_ComposeActivity> createState() => _ComposeActivityState();
}

class _ComposeActivityState extends State<_ComposeActivity> {
  final text = TextEditingController();
  String category = _ideas.keys.first;
  (String, String)? picked;
  final random = Random();
  String? error, lastBody;
  String requestId = newRequestId();
  bool busy = false;

  @override
  void dispose() {
    text.dispose();
    super.dispose();
  }

  void _pick() {
    final choices = _ideas[category]!.where((v) => v != picked).toList();
    setState(() {
      picked = choices[random.nextInt(choices.length)];
      error = null;
    });
  }

  Future<void> _save() async {
    final kind = widget.kind;
    final note = kind == PairActivity.notebook;
    final content = note ? text.text.trim() : picked?.$2 ?? '';
    if (busy || content.isEmpty) return;
    final title = note
        ? '便签 · ${content.split('\n').first.characters.take(22)}'
        : picked!.$1;
    final body = kind.storedBody(content);
    if (lastBody != body) requestId = newRequestId();
    lastBody = body;
    setState(() {
      busy = true;
      error = null;
    });
    try {
      await widget.session.mutate('POST', '/v1/modules', {
        'request_id': requestId,
        'module': kind.module,
        'title': title,
        'body': body,
        'confirmed': true,
      });
      if (!mounted) return;
      Navigator.pop(context);
    } catch (e) {
      if (mounted) {
        setState(() {
          error = e.toString();
          busy = false;
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final note = widget.kind == PairActivity.notebook;
    return PopScope(
      canPop: !busy,
      child: AlertDialog(
        scrollable: true,
        title: Text(note ? '写一张便签' : '约会行动签'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            if (note)
              TextField(
                key: const Key('pair-note-body'),
                controller: text,
                enabled: !busy,
                minLines: 3,
                maxLines: 6,
                maxLength: 600,
                decoration: const InputDecoration(labelText: '想留给对方的话'),
                onChanged: (_) => setState(() {}),
              )
            else ...[
              Wrap(
                spacing: 6,
                children: [
                  for (final label in _ideas.keys)
                    ChoiceChip(
                      label: Text(label),
                      selected: category == label,
                      onSelected: busy
                          ? null
                          : (_) => setState(() {
                              category = label;
                              picked = null;
                              error = null;
                            }),
                    ),
                ],
              ),
              if (picked case final result?) ...[
                const SizedBox(height: 12),
                Text(result.$1, style: Theme.of(context).textTheme.titleMedium),
                const SizedBox(height: 6),
                Text(result.$2),
              ],
              TextButton.icon(
                key: const Key('pair-reveal'),
                onPressed: busy ? null : _pick,
                icon: const Icon(Icons.auto_awesome_outlined),
                label: Text(picked == null ? '揭晓行动签' : '换一张'),
              ),
            ],
            Text(
              note ? '贴出后，你们都能在便签本和共同回忆中看到。' : '发出邀请后，双方可以各自表态，这张签也会存入共同心愿。',
            ),
            if (error != null) Text(error!),
          ],
        ),
        actions: [
          TextButton(
            onPressed: busy ? null : () => Navigator.pop(context),
            child: const Text('取消'),
          ),
          FilledButton(
            key: const Key('pair-publish'),
            onPressed:
                busy || (note ? text.text.trim().isEmpty : picked == null)
                ? null
                : _save,
            child: Text(note ? '贴给伴侣' : '邀请伴侣'),
          ),
        ],
      ),
    );
  }
}

class _SharedActivityCard extends StatefulWidget {
  const _SharedActivityCard({
    super.key,
    required this.kind,
    required this.session,
    required this.record,
    required this.activity,
    required this.journey,
  });
  final PairActivity kind;
  final CloudSession session;
  final Json record;
  final Json? activity, journey;

  @override
  State<_SharedActivityCard> createState() => _SharedActivityCardState();
}

class _SharedActivityCardState extends State<_SharedActivityCard> {
  bool busy = false;
  String? error, unsentReply;

  // Capture the version displayed before opening the editor. R2 checks both
  // the proposal version and the caller's own response version.
  Future<void> _respond(
    Json mine,
    String choice, {
    bool writeNote = false,
  }) async {
    if (busy) return;
    final session = widget.session, record = widget.record;
    final version = record['version'];
    String note = mine['note'] as String? ?? '';
    if (writeNote) {
      final result = await showDialog<String>(
        context: context,
        builder: (_) => _ReplyDialog(initial: unsentReply ?? note),
      );
      if (!mounted || result == null) return;
      note = result;
      unsentReply = result;
    }
    setState(() {
      busy = true;
      error = null;
    });
    try {
      await session.mutate('PUT', '/v1/modules/${record['id']}/vote', {
        'proposal_version': version,
        'version': mine['version'],
        'choice': choice,
        'note': note,
      });
      unsentReply = null;
    } catch (e) {
      if (mounted) setState(() => error = e.toString());
    } finally {
      if (mounted) setState(() => busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final record = widget.record, activity = widget.activity;
    final note = widget.kind == PairActivity.notebook;
    final myId = widget.session.user['id'];
    final author = record['owner'];
    final own = author == myId;
    final votes = (activity?['votes'] as List? ?? []).whereType<Json>();
    final mine = votes.where((v) => v['owner'] == myId).firstOrNull;
    final recipient = votes.where((v) => v['owner'] != author).firstOrNull;
    final received = recipient?['choice'] == 'accept';
    final partnerName = recipient?['name'] as String? ?? '伴侣';
    final reply = recipient?['note'] as String? ?? '';
    final agrees = activity?['agreed'] == true;
    const labels = {'accept': '愿意', 'decline': '这次不约', 'pending': '再想想'};
    final journey = widget.journey;
    final planned = journey?['stage'] == 'planned';
    final linkedId = switch (journey?['stage']) {
      'planned' => journey?['plan'] as String?,
      'remembered' => journey?['memory'] as String?,
      _ => null,
    };
    return Card(
      semanticContainer: false,
      margin: const EdgeInsets.only(top: 12),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              note ? (own ? '我写的便签' : '伴侣写给我的便签') : record['title'] as String,
              style: Theme.of(context).textTheme.titleMedium,
            ),
            const SizedBox(height: 6),
            SelectableText(widget.kind.content(record)),
            const Divider(height: 24),
            if (note) ...[
              Text(
                received
                    ? (own ? '$partnerName 已收下' : '我已收下')
                    : (own ? '等伴侣收下' : '等待我收下'),
              ),
              if (received && reply.isNotEmpty) Text('回信 · $reply'),
              if (!own && mine != null)
                TextButton(
                  key: Key('pair-reply-${record['id']}'),
                  onPressed: busy
                      ? null
                      : () => _respond(mine, 'accept', writeNote: true),
                  child: Text(received ? '修改回信' : '收下并回信'),
                ),
            ] else if (linkedId != null) ...[
              Text(planned ? '已排进共同日程' : '已留下共同回忆'),
              if (planned)
                Text(
                  [
                    journey?['day'],
                    journey?['clock'],
                    journey?['place'],
                  ].whereType<String>().where((s) => s.isNotEmpty).join(' · '),
                ),
            ] else ...[
              Text(agrees ? '两人都愿意' : '你们各自的选择'),
              for (final v in votes)
                Text(
                  "${v['owner'] == myId ? '我' : v['name']} · ${labels[v['choice']] ?? '尚未选择'}",
                ),
              if (mine != null)
                Wrap(
                  spacing: 8,
                  children: [
                    for (final entry in labels.entries)
                      ChoiceChip(
                        label: Text(entry.value),
                        selected: mine['choice'] == entry.key,
                        onSelected: busy
                            ? null
                            : (_) => _respond(mine, entry.key),
                      ),
                  ],
                ),
            ],
            if (!note)
              TextButton(
                onPressed: () => Navigator.push(
                  context,
                  MaterialPageRoute(
                    builder: (_) => CloudModuleDetail(
                      session: widget.session,
                      moduleId: linkedId ?? record['id'] as String,
                    ),
                  ),
                ),
                child: Text(
                  linkedId != null
                      ? (planned ? '查看共同日程' : '查看共同回忆')
                      : (agrees ? '打开共同心愿，安排日期' : '查看共同心愿或和 DP 讨论'),
                ),
              ),
            if (error != null) Text(error!),
          ],
        ),
      ),
    );
  }
}

class _ReplyDialog extends StatefulWidget {
  const _ReplyDialog({required this.initial});
  final String initial;

  @override
  State<_ReplyDialog> createState() => _ReplyDialogState();
}

class _ReplyDialogState extends State<_ReplyDialog> {
  late final text = TextEditingController(text: widget.initial);

  @override
  void dispose() {
    text.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => AlertDialog(
    scrollable: true,
    title: const Text('给这张便签回信'),
    content: TextField(
      key: const Key('pair-reply-body'),
      controller: text,
      autofocus: true,
      minLines: 2,
      maxLines: 4,
      maxLength: 300,
      decoration: const InputDecoration(labelText: '对方会看到你的回信'),
      onChanged: (_) => setState(() {}),
    ),
    actions: [
      TextButton(
        onPressed: () => Navigator.pop(context),
        child: const Text('取消'),
      ),
      FilledButton(
        key: const Key('pair-reply-save'),
        onPressed: text.text.trim().isEmpty
            ? null
            : () => Navigator.pop(context, text.text.trim()),
        child: const Text('确认回信'),
      ),
    ],
  );
}
