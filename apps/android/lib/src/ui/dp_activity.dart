import 'package:material_ui/material_ui.dart';

import '../services/cloud_session.dart';

const _choices = {'accept': '愿意', 'decline': '不参加', 'pending': '待定'};
const _steps = {'saved': '已收藏', 'planned': '已计划', 'happened': '实际参加过'};

/// Two people can respond independently to each published proposal.
class ActivityActions extends StatefulWidget {
  const ActivityActions({
    required this.session,
    required this.record,
    super.key,
  });
  final CloudSession session;
  final Json record;

  @override
  State<ActivityActions> createState() => _ActivityActionsState();
}

class _ActivityActionsState extends State<ActivityActions> {
  bool busy = false;
  String? error;

  Future<void> _write(String path, Json data, {String method = 'PUT'}) async {
    if (busy) return;
    setState(() {
      busy = true;
      error = null;
    });
    try {
      final id = Uri.encodeComponent(widget.record['id'].toString());
      await widget.session.mutate(method, '/v1/modules/$id/$path', data);
    } on CloudError catch (e) {
      if (mounted) {
        setState(() {
          error = e.message;
        });
      }
    } finally {
      if (mounted) {
        setState(() {
          busy = false;
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) => ListenableBuilder(
    listenable: widget.session,
    builder: (context, _) {
      final item = widget.session
          .rows('activities')
          .where((r) => r['module_id'] == widget.record['id'])
          .firstOrNull;
      if (item == null) return const SizedBox.shrink();
      if (item['proposal_version'] != widget.record['version']) {
        return const Text('活动已更新，请重新打开并核对后再表态。');
      }
      final votes = (item['votes'] as List).whereType<Json>();
      final myId = widget.session.user['id'];
      final mine = votes.where((v) => v['owner'] == myId).firstOrNull;
      if (mine == null) return const SizedBox.shrink();
      final agreed = item['agreed'] == true;
      final steps = item['steps'] as Json;
      final reviews = (item['reviews'] as List).whereType<Json>();
      final myReview = reviews.where((r) => r['owner'] == myId).firstOrNull;
      Json mutation(dynamic version) => {
        'proposal_version': item['proposal_version'],
        'version': version,
      };
      return Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          ListTile(
            contentPadding: EdgeInsets.zero,
            leading: Icon(
              agreed ? Icons.check_circle_outline : Icons.people_outline,
            ),
            title: Text(agreed ? '两人已定' : '各自的意愿'),
            subtitle: const Text('你们都选「愿意」后，这项活动才算两人已定。'),
          ),
          for (final v in votes)
            Padding(
              padding: const EdgeInsets.only(bottom: 6),
              child: Text(
                '${v['owner'] == myId ? '我' : v['name']} · ${_choices[v['choice']] ?? '尚未表态'}'
                "${v['note'] == '' ? '' : ' · ${v['note']}'}",
              ),
            ),
          Wrap(
            spacing: 8,
            runSpacing: 4,
            children: [
              for (final choice in _choices.entries)
                ChoiceChip(
                  label: Text(choice.value),
                  selected: mine['choice'] == choice.key,
                  onSelected: busy
                      ? null
                      : (_) => _write('vote', {
                          ...mutation(mine['version']),
                          'choice': choice.key,
                          'note': mine['note'],
                        }),
                ),
              if (mine['choice'] != null)
                TextButton(
                  onPressed: busy
                      ? null
                      : () async {
                          final note = await showDialog<String>(
                            context: context,
                            builder: (_) =>
                                _NoteDialog(initial: mine['note'].toString()),
                          );
                          if (note != null && mounted) {
                            await _write('vote', {
                              ...mutation(mine['version']),
                              'choice': mine['choice'],
                              'note': note,
                            });
                          }
                        },
                  child: const Text('补充我的想法'),
                ),
            ],
          ),
          const Divider(),
          ExpansionTile(
            tilePadding: EdgeInsets.zero,
            title: const Text('我的参与记录'),
            subtitle: const Text('分别记录收藏、计划和实际参加'),
            children: [
              for (final step in _steps.entries)
                CheckboxListTile(
                  contentPadding: EdgeInsets.zero,
                  title: Text(step.value),
                  value: steps[step.key]?['at'] != null,
                  onChanged: busy
                      ? null
                      : (v) => _write('steps/${step.key}', {
                          ...mutation(steps[step.key]?['version'] ?? 0),
                          'enabled': v == true,
                        }),
                ),
            ],
          ),
          for (final review in reviews)
            ListTile(
              contentPadding: EdgeInsets.zero,
              title: Text(review['text'].toString()),
              subtitle: Text(
                "${review['owner'] == myId ? '我的体验' : '${review['name']} 的体验'} · "
                "${review['scope'] == 'shared' ? '双方和共同 DP 可用' : '仅我和我的 DP 可用'}",
              ),
            ),
          if (steps['happened']?['at'] != null)
            Align(
              alignment: Alignment.centerLeft,
              child: TextButton.icon(
                icon: const Icon(Icons.edit_note),
                label: Text(myReview == null ? '记录我的实际体验' : '纠正或撤回我的体验'),
                onPressed: busy
                    ? null
                    : () async {
                        final result = await showDialog<Json>(
                          context: context,
                          builder: (_) => _ReviewDialog(review: myReview),
                        );
                        if (result == null || !mounted) return;
                        final data = mutation(item['my_review_version']);
                        if (result['withdraw'] == true) {
                          await _write('review/withdraw', data, method: 'POST');
                        } else {
                          await _write('review', {...data, ...result});
                        }
                      },
              ),
            ),
          if (error != null)
            Text(
              error!,
              style: TextStyle(color: Theme.of(context).colorScheme.error),
            ),
        ],
      );
    },
  );
}

class _NoteDialog extends StatefulWidget {
  const _NoteDialog({required this.initial});
  final String initial;
  @override
  State<_NoteDialog> createState() => _NoteDialogState();
}

class _NoteDialogState extends State<_NoteDialog> {
  late final text = TextEditingController(text: widget.initial);
  @override
  void dispose() {
    text.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => AlertDialog(
    title: const Text('我的想法'),
    content: SingleChildScrollView(
      child: TextField(
        controller: text,
        maxLength: 300,
        minLines: 1,
        maxLines: 4,
        decoration: const InputDecoration(labelText: '给伴侣的说明（选填）'),
      ),
    ),
    actions: [
      TextButton(
        onPressed: () => Navigator.pop(context),
        child: const Text('取消'),
      ),
      FilledButton(
        onPressed: () => Navigator.pop(context, text.text.trim()),
        child: const Text('保存说明'),
      ),
    ],
  );
}

class _ReviewDialog extends StatefulWidget {
  const _ReviewDialog({this.review});
  final Json? review;
  @override
  State<_ReviewDialog> createState() => _ReviewDialogState();
}

class _ReviewDialogState extends State<_ReviewDialog> {
  late final text = TextEditingController(
    text: widget.review?['text']?.toString() ?? '',
  );
  late bool shared = widget.review?['scope'] == 'shared';
  bool confirmingWithdrawal = false;
  @override
  void dispose() {
    text.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => AlertDialog(
    title: Text(confirmingWithdrawal ? '撤回这条体验？' : '我的实际体验'),
    content: SingleChildScrollView(
      child: confirmingWithdrawal
          ? const Text('DP 在之后的建议中会停止使用这条体验。')
          : Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                TextField(
                  controller: text,
                  decoration: const InputDecoration(labelText: '这次喜欢什么？想改变什么？'),
                  minLines: 2,
                  maxLines: 5,
                  maxLength: 600,
                  onChanged: (_) => setState(() {}),
                ),
                SwitchListTile(
                  contentPadding: EdgeInsets.zero,
                  value: shared,
                  title: const Text('分享给伴侣和共同 DP'),
                  subtitle: Text(shared ? '保存后双方都可查看和使用。' : '仅我和我的私人 DP 可用。'),
                  onChanged: (v) => setState(() {
                    shared = v;
                  }),
                ),
              ],
            ),
    ),
    actions: [
      TextButton(
        onPressed: () => Navigator.pop(context),
        child: const Text('取消'),
      ),
      if (widget.review != null && !confirmingWithdrawal)
        TextButton(
          onPressed: () => setState(() {
            confirmingWithdrawal = true;
          }),
          child: const Text('撤回体验'),
        ),
      FilledButton(
        onPressed: confirmingWithdrawal
            ? () => Navigator.pop(context, <String, dynamic>{'withdraw': true})
            : text.text.trim().isEmpty
            ? null
            : () => Navigator.pop(context, <String, dynamic>{
                'text': text.text.trim(),
                'scope': shared ? 'shared' : 'private',
              }),
        child: Text(
          confirmingWithdrawal
              ? '确认撤回'
              : shared
              ? '确认共享体验'
              : '仅为我保存',
        ),
      ),
    ],
  );
}
