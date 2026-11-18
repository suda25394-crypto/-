import 'package:material_ui/material_ui.dart';

import '../services/cloud_session.dart';

class Reflections extends StatefulWidget {
  const Reflections({required this.session, super.key});
  final CloudSession session;
  @override
  State<Reflections> createState() => _ReflectionState();
}

class _ReflectionState extends State<Reflections> {
  final words = TextEditingController(), proposal = TextEditingController();
  bool busy = false;
  String? error, note;
  String? pendingInvite;
  Future<void> send(Json? r, String op, [String? value]) async {
    if (busy) return;
    setState(() {
      busy = true;
      error = null;
      note = null;
    });
    try {
      final result = r == null
          ? await widget.session.mutate('POST', '/v1/reflections', {
              'request_id': pendingInvite ??= newRequestId(),
              'shared': true,
            })
          : await widget.session.mutate('POST', '/v1/reflections/${r['id']}', {
              'version': r['version'],
              'action': op,
              'text': ?value,
            });
      if (r == null) pendingInvite = null;
      if (r == null ||
          result['phase'] == 'closed' ||
          result['phase'] == 'saved') {
        words.clear();
        proposal.clear();
      }
      if (mounted) {
        setState(() {
          note = result['phase'] == 'saved'
              ? '双方已确认，约定已写入共同回忆。'
              : result['phase'] == 'closed'
              ? '这次复盘已结束。'
              : null;
        });
      }
    } catch (e) {
      if (mounted) setState(() => error = e.toString());
    } finally {
      if (mounted) setState(() => busy = false);
    }
  }

  @override
  void dispose() {
    words.dispose();
    proposal.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(title: const Text('共同复盘')),
    body: ListenableBuilder(
      listenable: widget.session,
      builder: (context, _) {
        final r = widget.session.rows('reflections').firstOrNull;
        final people = (r?['members'] as List? ?? []).whereType<Json>();
        final me = people
            .where((p) => p['owner'] == widget.session.user['id'])
            .firstOrNull;
        return ListView(
          padding: const EdgeInsets.all(20),
          children: [
            const Text('双方分别同意后开始。你可以随时退出，也可以回到私聊寻求支持。'),
            if (error != null) Text(error!),
            if (note != null) Text(note!),
            if (r == null)
              OutlinedButton(
                onPressed: busy ? null : () => send(null, 'invite'),
                child: const Text('我愿意，邀请伴侣复盘'),
              )
            else ...[
              if (r['phase'] == 'invited') ...[
                Text(me?['joined'] == 1 ? '等待伴侣选择' : '伴侣邀请你一起复盘'),
                if (me?['joined'] != 1)
                  FilledButton(
                    onPressed: busy ? null : () => send(r, 'join'),
                    child: const Text('我愿意参加'),
                  ),
              ] else ...[
                for (final p in people)
                  ListTile(
                    title: Text(
                      p['owner'] == widget.session.user['id']
                          ? '我的表达'
                          : '伴侣的表达',
                    ),
                    subtitle: Text(
                      p['words'] == '' ? '尚未填写' : p['words'].toString(),
                    ),
                  ),
                TextField(
                  controller: words,
                  maxLength: 600,
                  decoration: const InputDecoration(labelText: '我想怎么表达（可跳过）'),
                ),
                TextButton(
                  onPressed: busy
                      ? null
                      : () => send(r, 'statement', words.text.trim()),
                  child: const Text('确认我的表达'),
                ),
                TextField(
                  controller: proposal,
                  maxLength: 600,
                  decoration: const InputDecoration(labelText: '拟议约定'),
                ),
                TextButton(
                  onPressed: busy
                      ? null
                      : () => send(r, 'propose', proposal.text.trim()),
                  child: const Text('交给双方核对'),
                ),
                if (r['proposal'] != '') ...[
                  SelectableText(r['proposal'].toString()),
                  FilledButton(
                    onPressed: busy || me?['approved'] == 1
                        ? null
                        : () => send(r, 'approve'),
                    child: Text(me?['approved'] == 1 ? '已确认，等待伴侣' : '我同意这段约定'),
                  ),
                ],
              ],
              TextButton(
                onPressed: busy ? null : () => send(r, 'leave'),
                child: const Text('退出这次复盘'),
              ),
            ],
          ],
        );
      },
    ),
  );
}
