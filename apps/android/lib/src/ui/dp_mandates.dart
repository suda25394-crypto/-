import 'package:material_ui/material_ui.dart';

import '../services/cloud_session.dart';
import 'theme.dart';

const _statusLabels = {
  'active': '等待相关话题',
  'paused': '已暂缓',
  'completed': '已完成',
  'cancelled': '已取消',
};

class MandateInboxButton extends StatelessWidget {
  const MandateInboxButton({required this.session, super.key});
  final CloudSession session;

  @override
  Widget build(BuildContext context) => TextButton(
    onPressed: () => Navigator.push(
      context,
      MaterialPageRoute(builder: (_) => _MandatesPage(session: session)),
    ),
    child: const Text('共同委托'),
  );
}

class MandateFromMessage extends StatelessWidget {
  const MandateFromMessage({
    required this.session,
    required this.message,
    super.key,
  });
  final CloudSession session;
  final Json message;

  @override
  Widget build(BuildContext context) {
    if (message['role'] != 'user' || message['id'] == null) {
      return const SizedBox.shrink();
    }
    final saved = session
        .rows('mandates')
        .any((row) => row['source_id'] == message['id']);
    return TextButton(
      onPressed: () => Navigator.push(
        context,
        MaterialPageRoute(
          builder: (_) => saved
              ? _MandatesPage(session: session)
              : _SaveMandatePage(session: session, message: message),
        ),
      ),
      child: Text(saved ? '查看共同委托' : '设为委托'),
    );
  }
}

String _person(CloudSession session, dynamic id) =>
    id == session.user['id'] ? '我' : '伴侣';

class _SaveMandatePage extends StatefulWidget {
  const _SaveMandatePage({required this.session, required this.message});
  final CloudSession session;
  final Json message;
  @override
  State<_SaveMandatePage> createState() => _SaveMandatePageState();
}

class _SaveMandatePageState extends State<_SaveMandatePage> {
  final _form = GlobalKey<FormState>();
  late final TextEditingController _task;
  late final TextEditingController _cue;
  bool _saving = false;
  String? _error;

  @override
  void initState() {
    super.initState();
    final original = widget.message['text'] as String;
    final split = RegExp(r'^(?:下次|以后)([^，,。；;]{2,100})[，,；;](.+)$')
        .firstMatch(original.trim());
    _task = TextEditingController(text: split?.group(2) ?? original);
    _cue = TextEditingController(text: split?.group(1) ?? '');
  }

  @override
  void dispose() {
    _task.dispose();
    _cue.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    if (_saving || !_form.currentState!.validate()) return;
    setState(() {
      _saving = true;
      _error = null;
    });
    try {
      await widget.session.mutate('POST', '/v1/mandates', {
        'source_id': widget.message['id'],
        'source_text': widget.message['text'],
        'task': _task.text.trim(),
        'cue': _cue.text.trim(),
      });
      if (mounted) {
        ScaffoldMessenger.of(context)
            .showSnackBar(const SnackBar(content: Text('已保存到共同委托')));
        Navigator.pop(context);
      }
    } catch (e) {
      if (mounted) setState(() => _error = e.toString());
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(title: const Text('设为共同委托')),
    body: SafeArea(
      child: Form(
        key: _form,
        child: ListView(
          padding: const EdgeInsets.all(20),
          children: [
            Text(
              '来自共同群 · ${_person(widget.session, widget.message['owner'])}',
              style: editionMeta,
            ),
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 12),
              child: Text(widget.message['text'] as String),
            ),
            TextFormField(
              controller: _cue,
              enabled: !_saving,
              maxLength: 160,
              maxLines: 2,
              minLines: 1,
              decoration: const InputDecoration(
                labelText: '什么情境下提醒',
                hintText: '例如，一起挑电影时',
              ),
              validator: (value) =>
                  (value ?? '').trim().isEmpty ? '请填写适用情境' : null,
            ),
            TextFormField(
              controller: _task,
              enabled: !_saving,
              maxLength: 400,
              minLines: 1,
              maxLines: 4,
              decoration: const InputDecoration(labelText: '托付给 DP 的事'),
              validator: (value) =>
                  (value ?? '').trim().isEmpty || value!.trim().length > 400
                  ? '请填写 400 字以内的事项'
                  : null,
            ),
            const Text('双方都能查看和管理。有人向 DP 征求相关建议时，它会想起这件事。'),
            if (_error != null)
              Padding(
                padding: const EdgeInsets.only(top: 8),
                child: Text(_error!, style: const TextStyle(color: amber)),
              ),
            const SizedBox(height: 16),
            FilledButton(
              onPressed: _saving ? null : _save,
              child: Text(_saving ? '正在保存…' : '确认保存共同委托'),
            ),
          ],
        ),
      ),
    ),
  );
}

class _MandatesPage extends StatelessWidget {
  const _MandatesPage({required this.session});
  final CloudSession session;

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(title: const Text('共同委托')),
    body: ListenableBuilder(
      listenable: session,
      builder: (context, _) {
        final rows = session.rows('mandates');
        return SafeArea(
          child: ListView(
            padding: const EdgeInsets.all(16),
            children: [
              if (rows.isEmpty)
                const Padding(
                  padding: EdgeInsets.only(top: 16),
                  child: Text('在共同群找到想托付给 DP 的那句话，点「设为委托」即可保存。'),
                ),
              for (final row in rows)
                _MandateEntry(
                  key: ValueKey(row['id']),
                  session: session,
                  row: row,
                ),
            ],
          ),
        );
      },
    ),
  );
}

class _MandateEntry extends StatefulWidget {
  const _MandateEntry({required this.row, required this.session, super.key});
  final CloudSession session;
  final Json row;
  @override
  State<_MandateEntry> createState() => _MandateEntryState();
}

class _MandateEntryState extends State<_MandateEntry> {
  bool _busy = false;
  String? _error;

  Future<void> _change(String status) async {
    if (_busy) return;
    final row = widget.row;
    if (status == 'cancelled' || status == 'completed') {
      final confirm = await showDialog<bool>(
        context: context,
        builder: (c) => AlertDialog(
          title: Text(status == 'cancelled' ? '取消这项委托？' : '标记为已完成？'),
          content: const Text('双方会看到新状态，DP 会停止用这项委托推荐。'),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(c, false),
              child: const Text('返回'),
            ),
            FilledButton(
              onPressed: () => Navigator.pop(c, true),
              child: const Text('确认'),
            ),
          ],
        ),
      );
      if (confirm != true || !mounted) return;
    }
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      final id = Uri.encodeComponent(row['id'] as String);
      await widget.session.mutate('PUT', '/v1/mandates/$id', {
        'status': status,
        'version': row['version'],
      });
    } catch (e) {
      if (mounted) setState(() => _error = e.toString());
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final row = widget.row, status = row['status'];
    final time = row['source_at'] as int? ?? 0;
    final date = time > 0
        ? DateTime.fromMillisecondsSinceEpoch(time * 1000)
              .toLocal()
              .toString()
              .substring(0, 16)
        : null;
    return ExpansionTile(
      title: Text(row['task'] as String),
      subtitle: Text('${_statusLabels[status]} · ${row['cue']}'),
      childrenPadding: const EdgeInsets.fromLTRB(16, 0, 16, 12),
      expandedCrossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          '由${_person(widget.session, row['owner'])}保存 · 来自共同群',
          style: editionMeta,
        ),
        Text(
          [_person(widget.session, row['source_owner']), ?date].join(' · '),
          style: editionMeta,
        ),
        Text(row['source_text'] as String),
        if (_error != null) Text(_error!, style: const TextStyle(color: amber)),
        if (status == 'active' || status == 'paused')
          Wrap(
            children: [
              TextButton(
                onPressed: _busy
                    ? null
                    : () => _change(status == 'active' ? 'paused' : 'active'),
                child: Text(status == 'active' ? '暂缓' : '恢复提醒'),
              ),
              TextButton(
                onPressed: _busy ? null : () => _change('completed'),
                child: const Text('完成'),
              ),
              TextButton(
                onPressed: _busy ? null : () => _change('cancelled'),
                child: const Text('取消委托'),
              ),
            ],
          ),
      ],
    );
  }
}
