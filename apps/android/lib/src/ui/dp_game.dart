import 'package:material_ui/material_ui.dart';

import '../services/cloud_session.dart';
import 'theme.dart';

class DpGameScreen extends StatefulWidget {
  const DpGameScreen({super.key, required this.session});
  final CloudSession session;

  @override
  State<DpGameScreen> createState() => _DpGameScreenState();
}

class _DpGameScreenState extends State<DpGameScreen> {
  final _selected = <String>{};
  String? _requestId;
  bool _busy = false;
  String? _error;

  void _open(String id) {
    Navigator.push<void>(
      context,
      MaterialPageRoute(
        builder: (_) => _GameRound(session: widget.session, id: id),
      ),
    );
  }

  Future<void> _generate() async {
    if (_busy || _selected.isEmpty) return;
    _requestId ??= newRequestId();
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      final result = await widget.session.mutate('POST', '/v1/games', {
        'source_ids': _selected.toList(),
        'request_id': _requestId,
      }) as Json;
      if (!mounted) return;
      _requestId = null;
      _open(result['id'] as String);
    } catch (e) {
      if (mounted) {
        setState(() {
          _error = e.toString();
          // Only discard the key for a definitive response. A lost response may be billable.
          if (e is CloudError &&
              {
                'game_format',
                'model_format',
                'insufficient_memories',
                'source_changed',
                'generation_unknown',
              }.contains(e.code)) {
            _requestId = null;
          }
        });
      }
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(title: const Text('共同回忆小游戏')),
    body: ListenableBuilder(
      listenable: widget.session,
      builder: (context, _) {
        final memories = widget.session
            .rows('modules')
            .where((m) => m['module'] == 'memory')
            .toList();
        final games = widget.session.rows('games');
        final generation = widget.session.state['game_generation_status'];
        return ListView(
          padding: const EdgeInsets.all(20),
          children: [
            Text('给一段回忆出三道题', style: Theme.of(context).textTheme.headlineSmall),
            const SizedBox(height: 8),
            const Text('选一至三条共同回忆交给 DP。你来作答，对方猜你的选择；两人都同意后再揭晓。'),
            const SizedBox(height: 16),
            if (memories.isEmpty)
              const Text('请先到「共同记忆」写下一段一起经历的事，再回来选材。')
            else
              Wrap(
                spacing: 8,
                runSpacing: 6,
                children: [
                  for (final memory in memories)
                    FilterChip(
                      label: Text(memory['title'] as String),
                      selected: _selected.contains(memory['id']),
                      onSelected:
                          _busy ||
                              (_selected.length >= 3 &&
                                  !_selected.contains(memory['id']))
                          ? null
                          : (checked) => setState(() {
                              final id = memory['id'] as String;
                              if (checked) {
                                _selected.add(id);
                              } else {
                                _selected.remove(id);
                              }
                              _requestId = null;
                              _error = null;
                            }),
                    ),
                ],
              ),
            const SizedBox(height: 12),
            if (generation == 'unknown')
              const Text('上一笔出题没有取得完整回执。另开一轮会再次使用模型额度。'),
            FilledButton(
              onPressed: _busy || generation == 'pending' || _selected.isEmpty
                  ? null
                  : _generate,
              child: Text(
                _busy || generation == 'pending'
                    ? '正在出题…'
                    : generation == 'unknown'
                    ? (_requestId == null ? '另开一轮' : '核对上次请求')
                    : '生成三道题',
              ),
            ),
            if (_error != null)
              Text(_error!, style: const TextStyle(color: amber)),
            const SizedBox(height: 22),
            const Divider(),
            Text('我们的游戏', style: Theme.of(context).textTheme.titleLarge),
            if (games.isEmpty)
              const Padding(
                padding: EdgeInsets.symmetric(vertical: 14),
                child: Text('还没有开始的游戏。'),
              ),
            for (final g in games)
              ListTile(
                contentPadding: EdgeInsets.zero,
                title: Text((g['questions'] as List).first['anchor'] as String),
                subtitle: Text(
                  g['result'] != null
                      ? '已揭晓 · 查看结果'
                      : g['role'] == 'answer'
                      ? '我作答 · 继续'
                      : '我来猜 · 继续',
                ),
                trailing: const Icon(Icons.chevron_right),
                onTap: () => _open(g['id'] as String),
              ),
          ],
        );
      },
    ),
  );
}

class _GameRound extends StatefulWidget {
  const _GameRound({required this.session, required this.id});
  final CloudSession session;
  final String id;

  @override
  State<_GameRound> createState() => _GameRoundState();
}

class _GameRoundState extends State<_GameRound> {
  bool _busy = false;
  String? _error;

  Future<void> _write(String action, [Json? data]) async {
    if (_busy) return;
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      await widget.session.mutate(
        action == 'choices' ? 'PUT' : 'POST',
        '/v1/games/${Uri.encodeComponent(widget.id)}/$action',
        data,
      );
    } catch (e) {
      if (mounted) setState(() => _error = e.toString());
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(title: const Text('三道回忆题')),
    body: ListenableBuilder(
      listenable: widget.session,
      builder: (context, _) {
        final g = widget.session
            .rows('games')
            .where((g) => g['id'] == widget.id)
            .firstOrNull;
        if (g == null) {
          return Center(
            child: Text(
              widget.session.connectionError ?? '这轮游戏的共同素材已更新，请返回重新选材。',
            ),
          );
        }
        final qs = (g['questions'] as List).cast<Json>();
        final choices = (g['my_choices'] as List).cast<int?>();
        final isAnswer = g['role'] == 'answer';
        final locked = g['my_locked'] == true;
        final result = g['result'] as Json?;
        return ListView(
          padding: const EdgeInsets.all(20),
          children: [
            Text(
              result == null
                  ? (isAnswer ? '你来作答' : '猜猜对方会怎么选')
                  : '猜中了 ${result["score"]} / 3 题',
              style: Theme.of(context).textTheme.headlineSmall,
            ),
            const SizedBox(height: 6),
            if (result == null) const Text('每次点选都会保存进度。提交后锁定，揭晓前只有你能看到自己的选择。'),
            for (var i = 0; i < qs.length; i++) ...[
              const SizedBox(height: 20),
              Text('共同回忆 · ${qs[i]["anchor"]}', style: editionMeta),
              const SizedBox(height: 5),
              Text(
                '${i + 1}. ${qs[i]["prompt"]}',
                style: Theme.of(context).textTheme.titleMedium,
              ),
              const SizedBox(height: 8),
              if (result == null)
                Wrap(
                  spacing: 7,
                  runSpacing: 3,
                  children: [
                    for (var j = 0; j < (qs[i]['options'] as List).length; j++)
                      ChoiceChip(
                        label: Text(qs[i]['options'][j] as String),
                        selected: choices[i] == j,
                        onSelected: locked || _busy
                            ? null
                            : (_) {
                                final updated = [...choices];
                                updated[i] = j;
                                _write('choices', {
                                  'choices': updated,
                                  'version': g['version'],
                                });
                              },
                      ),
                  ],
                )
              else ...[
                Text('本人选择 · ${qs[i]["options"][result["answers"][i]]}'),
                Text('对方猜测 · ${qs[i]["options"][result["guesses"][i]]}'),
              ],
            ],
            const SizedBox(height: 22),
            if (!locked)
              FilledButton(
                onPressed: _busy || choices.contains(null)
                    ? null
                    : () => _write('lock', {
                        'choices': choices,
                        'version': g['version'],
                      }),
                child: const Text('确认提交三个选择'),
              )
            else if (result == null && g['other_locked'] != true)
              const Text('已提交，等待对方选完三题。')
            else if (result == null && g['my_consent'] != true)
              FilledButton(
                onPressed: _busy ? null : () => _write('reveal'),
                child: const Text('同意一起揭晓'),
              )
            else if (result == null)
              const Text('你已同意揭晓，等待另一位确认。'),
            if (_error != null || widget.session.connectionError != null)
              Text(
                _error ?? widget.session.connectionError!,
                style: const TextStyle(color: amber),
              ),
          ],
        );
      },
    ),
  );
}
