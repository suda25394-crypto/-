import 'package:material_ui/material_ui.dart';

import '../data/catalog.dart';
import '../services/cloud_session.dart';
import 'cloud_chat.dart';
import 'cloud_records.dart';
import 'dp_activity.dart';
import 'theme.dart';

class CloudModuleDetail extends StatelessWidget {
  const CloudModuleDetail({
    required this.session,
    required this.moduleId,
    super.key,
  });
  final CloudSession session;
  final String moduleId;

  @override
  Widget build(BuildContext context) => ListenableBuilder(
    listenable: session,
    builder: (context, _) {
      final record = session
          .rows('modules')
          .where((r) => r['id'] == moduleId)
          .firstOrNull;
      if (record == null) {
        return Scaffold(
          appBar: AppBar(),
          body: const Center(child: Text('这条记录已不可用。')),
        );
      }
      final id = ModuleId.values.byName(record['module'] as String);
      void chat(String scope) {
        Navigator.push(
          context,
          MaterialPageRoute(
            builder: (_) => ModuleConversation(
              session: session,
              moduleId: moduleId,
              scope: scope,
            ),
          ),
        );
      }

      return Scaffold(
        appBar: AppBar(
          title: Text(moduleName(record['module'])),
          actions: [
            IconButton(
              tooltip: '编辑记录',
              icon: const Icon(Icons.edit_outlined),
              onPressed: () => Navigator.push(
                context,
                MaterialPageRoute(
                  builder: (_) =>
                      CloudModuleEditor(session: session, id: id, row: record),
                ),
              ),
            ),
          ],
        ),
        body: ListView(
          padding: const EdgeInsets.all(20),
          children: [
            Text('共同记录 · 第 ${record['version']} 版', style: editionMeta),
            const SizedBox(height: 8),
            Text(
              record['title'].toString(),
              style: Theme.of(context).textTheme.headlineSmall,
            ),
            const SizedBox(height: 10),
            SelectableText(record['body'].toString()),
            const SizedBox(height: 16),
            Wrap(
              spacing: 8,
              runSpacing: 4,
              children: [
                FilledButton.tonalIcon(
                  onPressed: () => chat('private'),
                  icon: const Icon(Icons.lock_outline),
                  label: const Text('私下问 DP'),
                ),
                OutlinedButton.icon(
                  onPressed: () => chat('shared'),
                  icon: const Icon(Icons.forum_outlined),
                  label: const Text('两人共同续聊'),
                ),
              ],
            ),
            const SizedBox(height: 10),
            const Divider(),
            ActivityActions(session: session, record: record),
          ],
        ),
      );
    },
  );
}

class ModuleConversation extends StatefulWidget {
  const ModuleConversation({
    required this.session,
    required this.moduleId,
    required this.scope,
    super.key,
  });
  final CloudSession session;
  final String moduleId;
  final String scope;
  @override
  State<ModuleConversation> createState() => _ModuleConversationState();
}

class _ModuleConversationState extends State<ModuleConversation> {
  Json? _thread;
  String? _error;
  bool _loading = false;
  bool _reload = false;
  String? _lastRequest;
  int? _lastVersion;
  String get _path =>
      '/v1/modules/${Uri.encodeComponent(widget.moduleId)}/conversation';

  @override
  void initState() {
    super.initState();
    widget.session.addListener(_load);
    _load();
  }

  @override
  void dispose() {
    widget.session.removeListener(_load);
    super.dispose();
  }

  Future<void> _load() async {
    if (_loading) {
      _reload = true;
      return;
    }
    _loading = true;
    do {
      _reload = false;
      try {
        final value = await widget.session.request(
          'GET',
          '$_path?scope=${widget.scope}',
        );
        if (!mounted) return;
        if (value is! Json ||
            value['record'] is! Json ||
            value['record']['id'] != widget.moduleId ||
            value['messages'] is! List ||
            value['drafts'] is! List) {
          throw const CloudError('服务端未返回这条记录的完整对话。');
        }
        setState(() {
          _thread = value;
          _error = null;
        });
      } catch (e) {
        if (!mounted) return;
        setState(() {
          _error = e.toString();
          if (e is CloudError && [401, 403, 404].contains(e.status)) {
            _thread = null;
          }
        });
      }
    } while (_reload && mounted);
    _loading = false;
  }

  Future<void> _send(String text, String requestId) async {
    final pending = widget.session
        .rows('pending_messages')
        .where(
          (m) =>
              m['module_id'] == widget.moduleId &&
              m['scope'] == widget.scope &&
              m['request_id'] == requestId,
        )
        .firstOrNull;
    if (_lastRequest != requestId) {
      _lastRequest = requestId;
      _lastVersion =
          pending?['version'] as int? ?? _thread!['record']['version'] as int;
    }
    await widget.session.mutate('POST', _path, {
      'scope': widget.scope,
      'text': text,
      'version': _lastVersion,
      'request_id': requestId,
    });
    await _load();
  }

  Future<void> _openDrafts() async {
    final rows = (_thread!['drafts'] as List).whereType<Json>().toList();
    final selected = await showModalBottomSheet<Json>(
      context: context,
      builder: (sheet) => SafeArea(
        child: ListView(
          shrinkWrap: true,
          padding: const EdgeInsets.all(12),
          children: [
            const ListTile(title: Text('本条记录的草稿')),
            if (rows.isEmpty) const ListTile(title: Text('还没有修改草稿')),
            for (final row in rows)
              ListTile(
                leading: const Icon(Icons.edit_note),
                title: Text(
                  (row['items'] as List)
                      .whereType<Json>()
                      .map((r) => r['title'])
                      .join(' · '),
                ),
                subtitle: Text(switch (row['status']) {
                  'pending' => '待核对',
                  'confirmed' => '已发布',
                  _ => '已取消',
                }),
                onTap: () => Navigator.pop(sheet, row),
              ),
          ],
        ),
      ),
    );
    if (selected != null && mounted) {
      await Navigator.push(
        context,
        MaterialPageRoute(
          builder: (_) => DraftEditor(session: widget.session, draft: selected),
        ),
      );
      if (mounted) await _load();
    }
  }

  @override
  Widget build(BuildContext context) {
    final thread = _thread;
    return Scaffold(
      appBar: AppBar(title: Text(widget.scope == 'shared' ? '共同续聊' : '私人续聊')),
      body: Column(
        children: [
          if (_error != null) CloudFeedback(message: _error!, onRetry: _load),
          if (thread != null) ...[
            ListTile(
              dense: true,
              leading: const Icon(Icons.subject),
              title: Text(
                thread['record']['title'].toString(),
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
              ),
              subtitle: Text(
                '第 ${thread['record']['version']} 版 · ${thread['record']['body']}',
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
              ),
            ),
            const Divider(height: 1),
            Expanded(
              child: CloudChat(
                session: widget.session,
                scope: widget.scope,
                moduleId: widget.moduleId,
                thread: thread,
                sendInModule: _send,
                openRecords: _openDrafts,
              ),
            ),
          ] else if (_error == null)
            const Expanded(child: Center(child: CircularProgressIndicator())),
        ],
      ),
    );
  }
}
