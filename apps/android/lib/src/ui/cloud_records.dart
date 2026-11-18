import 'package:material_ui/material_ui.dart';

import '../data/catalog.dart';
import '../services/cloud_session.dart';
import '../data/pair_activity.dart';
import 'theme.dart';
import 'dp_module_chat.dart';

const cloudModules = {
  'date': '约会',
  'calendar': '共同日程',
  'wish': '心愿',
  'memory': '共同记忆',
};
String moduleName(dynamic code) => cloudModules[code] ?? code.toString();
String pathId(Json row) => Uri.encodeComponent(row['id'].toString());

Future<bool> askCloud(
  BuildContext context,
  String title,
  String detail,
  String accept,
) async =>
    await showDialog<bool>(
      context: context,
      builder: (c) => AlertDialog(
        title: Text(title),
        content: SingleChildScrollView(child: Text(detail)),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(c, false),
            child: const Text('返回'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(c, true),
            child: Text(accept),
          ),
        ],
      ),
    ) ??
    false;

class CloudRecords extends StatelessWidget {
  const CloudRecords({required this.session, required this.shared, super.key});
  final CloudSession session;
  final bool shared;
  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(title: Text(shared ? '共同草稿与记忆' : '我的草稿与记忆')),
    body: ListenableBuilder(
      listenable: session,
      builder: (c, _) {
        final drafts = session
            .rows('drafts')
            .where(
              (d) => shared
                  ? d['scope'] == 'shared'
                  : d['owner'] == session.user['id'] && d['scope'] == 'private',
            )
            .toList();
        final memories = session
            .rows('memories')
            .where(
              (m) => shared
                  ? m['scope'] == 'shared'
                  : m['owner'] == session.user['id'],
            )
            .toList();
        return ListView(
          padding: const EdgeInsets.all(18),
          children: [
            Text(shared ? '此处展示双方获准查看的内容。' : '候选仅自己可见。保存为私人或共享记忆前，请先核对内容。'),
            const SizedBox(height: 16),
            const Text(
              '草稿',
              style: TextStyle(fontWeight: FontWeight.bold, fontSize: 20),
            ),
            if (drafts.isEmpty) const ListTile(title: Text('暂无草稿')),
            for (final d in drafts)
              ListTile(
                leading: const Icon(Icons.edit_note),
                title: Text(
                  (d['items'] as List)
                      .whereType<Json>()
                      .map((i) => i['title'])
                      .join(' · '),
                ),
                subtitle: Text(
                  d['status'] == 'confirmed'
                      ? '已确认并写入'
                      : d['status'] == 'cancelled'
                      ? '已取消'
                      : '待确认',
                ),
                trailing: const Icon(Icons.chevron_right),
                onTap: () => Navigator.push(
                  c,
                  MaterialPageRoute(
                    builder: (_) => DraftEditor(session: session, draft: d),
                  ),
                ),
              ),
            const Divider(),
            const Text(
              '记忆',
              style: TextStyle(fontWeight: FontWeight.bold, fontSize: 20),
            ),
            if (memories.isEmpty) const ListTile(title: Text('暂无获准记忆')),
            for (final m in memories)
              ListTile(
                leading: Icon(
                  m['scope'] == 'shared'
                      ? Icons.people_outline
                      : Icons.lock_outline,
                ),
                title: Text(m['text'].toString()),
                subtitle: Text(switch (m['scope']) {
                  'shared' => '配对双方可用',
                  'candidate' => '待本人确认',
                  _ => '仅本人可用',
                }),
                onTap: m['owner'] == session.user['id']
                    ? () => Navigator.push(
                        c,
                        MaterialPageRoute(
                          builder: (_) =>
                              MemoryEditor(session: session, row: m),
                        ),
                      )
                    : null,
              ),
          ],
        );
      },
    ),
  );
}

class MemoryEditor extends StatefulWidget {
  const MemoryEditor({required this.session, required this.row, super.key});
  final CloudSession session;
  final Json row;
  @override
  State<MemoryEditor> createState() => _MemoryEditorState();
}

class _MemoryEditorState extends State<MemoryEditor> {
  late final input = TextEditingController(text: widget.row['text'].toString());
  bool busy = false;
  String? error;
  Future<void> save(String scope) async {
    if (busy) return;
    final remove = scope == 'delete';
    final text = input.text.trim();
    if (!remove && text.isEmpty) {
      setState(() => error = '请输入要保存的记忆。');
      return;
    }
    if ((remove || scope == 'shared') &&
        !await askCloud(
          context,
          remove ? '移除此条记忆？' : '发布这条记忆？',
          remove ? '之后的模型检索将不再使用它。' : '伴侣和共同群的 AI 将能使用这条信息。',
          remove ? '移除' : '确认发布',
        )) {
      return;
    }
    if (!mounted) return;
    setState(() {
      busy = true;
      error = null;
    });
    final base = '/v1/memories/${pathId(widget.row)}';
    try {
      if (remove) {
        await widget.session.mutate(
          'DELETE',
          '$base?version=${widget.row['version']}',
        );
      } else {
        await widget.session.mutate('PUT', base, {
          'version': widget.row['version'],
          'text': text,
          'scope': scope,
        });
      }
      if (mounted) Navigator.pop(context);
    } catch (e) {
      if (mounted) setState(() => error = e.toString());
    } finally {
      if (mounted) setState(() => busy = false);
    }
  }

  @override
  void dispose() {
    input.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(title: const Text('核对记忆')),
    body: ListView(
      padding: const EdgeInsets.all(20),
      children: [
        TextField(
          controller: input,
          enabled: !busy,
          maxLines: 4,
          maxLength: 300,
          decoration: const InputDecoration(labelText: '记忆内容'),
        ),
        if (error != null) Text(error!, style: const TextStyle(color: amber)),
        FilledButton(
          onPressed: busy ? null : () => save('private'),
          child: Text(
            widget.row['scope'] == 'shared' ? '撤回共享，仅自己保存' : '确认，仅自己保存',
          ),
        ),
        OutlinedButton(
          onPressed: busy ? null : () => save('shared'),
          child: const Text('确认并发布给伴侣'),
        ),
        TextButton(
          onPressed: busy ? null : () => save('delete'),
          child: Text(widget.row['scope'] == 'candidate' ? '拒绝记住' : '删除记忆'),
        ),
      ],
    ),
  );
}

class _ItemFields {
  _ItemFields(Json data, {this.activity})
    : module = data['module'] as String,
      title = TextEditingController(text: data['title'] as String?),
      body = TextEditingController(
        text:
            activity?.withoutMarker(data['body'] as String? ?? '') ??
            data['body'] as String?,
      );
  final String module;
  final PairActivity? activity;
  final TextEditingController title, body;
  Json toJson() => {
    'module': module,
    'title': title.text.trim(),
    'body': activity?.storedBody(body.text.trim()) ?? body.text.trim(),
  };
  void dispose() {
    title.dispose();
    body.dispose();
  }
}

class DraftEditor extends StatefulWidget {
  const DraftEditor({required this.session, required this.draft, super.key});
  final CloudSession session;
  final Json draft;
  @override
  State<DraftEditor> createState() => _DraftEditorState();
}

class _DraftEditorState extends State<DraftEditor> {
  late final targetKind = PairActivity.forRecord(
    widget.session
        .rows('modules')
        .where(
          (row) =>
              widget.draft['target_id'] != null &&
              row['id'] == widget.draft['target_id'],
        )
        .firstOrNull,
  );
  late final items = (widget.draft['items'] as List)
      .whereType<Json>()
      .map(
        (item) => _ItemFields(
          item,
          activity: targetKind?.module == item['module'] ? targetKind : null,
        ),
      )
      .toList();
  bool busy = false;
  String? error;
  Future<void> finish(bool confirm) async {
    final d = widget.draft;
    if (confirm &&
        items.any(
          (i) => i.title.text.trim().isEmpty || i.body.text.trim().isEmpty,
        )) {
      setState(() => error = '请补全每一项的标题和内容。');
      return;
    }
    final ok = await askCloud(
      context,
      confirm ? '写入共同模块？' : '取消这份草稿？',
      confirm
          ? [
              if (d['target_id'] != null)
                '将更新原记录第 ${d['target_version']} 版。配对双方都能看到更新后的内容。'
              else
                '以下 ${items.length} 项将写入共同模块，配对双方都能看到。',
              for (final item in items)
                '${moduleName(item.module)} · ${item.title.text.trim()}\n${item.body.text.trim()}',
            ].join('\n\n')
          : '取消以后不会写入共同模块。',
      confirm ? '确认发布' : '取消草稿',
    );
    if (!ok || !mounted) return;
    setState(() {
      busy = true;
      error = null;
    });
    try {
      await widget.session.mutate(
        'POST',
        '/v1/drafts/${pathId(d)}/${confirm ? 'confirm' : 'cancel'}',
        {
          'version': d['version'],
          if (confirm) 'items': items.map((i) => i.toJson()).toList(),
        },
      );
      if (mounted) Navigator.pop(context);
    } catch (e) {
      if (mounted) setState(() => error = e.toString());
    } finally {
      if (mounted) setState(() => busy = false);
    }
  }

  @override
  void dispose() {
    for (final i in items) {
      i.dispose();
    }
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final editable = widget.draft['status'] == 'pending' && !busy;
    return Scaffold(
      appBar: AppBar(title: const Text('核对草稿')),
      body: ListView(
        padding: const EdgeInsets.all(18),
        children: [
          Text(
            widget.draft['scope'] == 'shared'
                ? '共同草稿 · 双方可见'
                : '私人草稿 · 发布前仅自己可见',
          ),
          if (widget.draft['target_id'] != null)
            Text(
              '修改原记录 · 基于第 ${widget.draft['target_version']} 版',
              style: editionMeta,
            ),
          for (final i in items) ...[
            const SizedBox(height: 18),
            Text(moduleName(i.module), style: editionMeta),
            const SizedBox(height: 5),
            TextField(
              controller: i.title,
              readOnly: !editable,
              maxLength: 120,
              decoration: const InputDecoration(labelText: '标题'),
            ),
            TextField(
              controller: i.body,
              readOnly: !editable,
              minLines: 2,
              maxLines: 8,
              maxLength: 2000,
              decoration: const InputDecoration(labelText: '内容与时间'),
            ),
          ],
          if (error != null) Text(error!, style: const TextStyle(color: amber)),
          if (widget.draft['status'] == 'pending') ...[
            FilledButton(
              onPressed: editable ? () => finish(true) : null,
              child: const Text('确认写入共同模块'),
            ),
            TextButton(
              onPressed: editable ? () => finish(false) : null,
              child: const Text('取消草稿'),
            ),
          ],
        ],
      ),
    );
  }
}

class CloudModuleScreen extends StatelessWidget {
  const CloudModuleScreen({required this.session, required this.id, super.key});
  final CloudSession session;
  final ModuleId id;
  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(title: Text(catalog[id]!.name)),
    body: ListenableBuilder(
      listenable: session,
      builder: (context, _) {
        final rows = session
            .rows('modules')
            .where((m) => m['module'] == id.name)
            .toList();
        return ListView(
          padding: const EdgeInsets.all(18),
          children: [
            const Text('已发布的共同记录 · 点开查看、表态或续聊', style: editionMeta),
            const SizedBox(height: 12),
            if (rows.isEmpty) const Text('还没有记录，可以手动添加，也可以从 AI 草稿确认写入。'),
            for (final m in rows)
              ListTile(
                contentPadding: EdgeInsets.zero,
                title: Text(m['title'].toString()),
                subtitle: Text(m['body'].toString()),
                trailing: IconButton(
                  icon: const Icon(Icons.edit_outlined),
                  tooltip: '编辑记录',
                  onPressed: () => Navigator.push(
                    context,
                    MaterialPageRoute(
                      builder: (_) =>
                          CloudModuleEditor(session: session, id: id, row: m),
                    ),
                  ),
                ),
                onTap: () => Navigator.push(
                  context,
                  MaterialPageRoute(
                    builder: (_) => CloudModuleDetail(
                      session: session,
                      moduleId: m['id'] as String,
                    ),
                  ),
                ),
              ),
            const SizedBox(height: 20),
            OutlinedButton.icon(
              icon: const Icon(Icons.add),
              label: const Text('添加共同记录'),
              onPressed: () => Navigator.push(
                context,
                MaterialPageRoute(
                  builder: (_) => CloudModuleEditor(session: session, id: id),
                ),
              ),
            ),
          ],
        );
      },
    ),
  );
}

class CloudModuleEditor extends StatefulWidget {
  const CloudModuleEditor({
    required this.session,
    required this.id,
    this.row,
    super.key,
  });
  final CloudSession session;
  final ModuleId id;
  final Json? row;
  @override
  State<CloudModuleEditor> createState() => _CloudModuleEditorState();
}

class _CloudModuleEditorState extends State<CloudModuleEditor> {
  late final input = _ItemFields({
    'module': widget.id.name,
    ...?widget.row,
  }, activity: PairActivity.forRecord(widget.row));
  String requestId = newRequestId();
  String? lastContent, error;
  bool busy = false;
  Future<void> save() async {
    if (input.title.text.trim().isEmpty || input.body.text.trim().isEmpty) {
      setState(() => error = '请填写标题和内容。');
      return;
    }
    if (!await askCloud(context, '确认共同记录', '保存后，伴侣可以看到这次修改。', '确认保存') ||
        !mounted) {
      return;
    }
    setState(() {
      busy = true;
      error = null;
    });
    final row = widget.row;
    final payload = input.toJson();
    final signature = payload.toString();
    if (lastContent != signature) requestId = newRequestId();
    lastContent = signature;
    try {
      if (row == null) {
        await widget.session.mutate('POST', '/v1/modules', {
          ...payload,
          'request_id': requestId,
          'confirmed': true,
        });
      } else {
        await widget.session.mutate('PUT', '/v1/modules/${pathId(row)}', {
          'title': payload['title'],
          'body': payload['body'],
          'version': row['version'],
        });
      }
      if (mounted) Navigator.pop(context);
    } catch (e) {
      if (mounted) setState(() => error = e.toString());
    } finally {
      if (mounted) setState(() => busy = false);
    }
  }

  @override
  void dispose() {
    input.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(title: Text('编辑${catalog[widget.id]!.name}')),
    body: ListView(
      padding: const EdgeInsets.all(20),
      children: [
        TextField(
          controller: input.title,
          enabled: !busy,
          maxLength: 120,
          decoration: const InputDecoration(labelText: '标题'),
        ),
        TextField(
          controller: input.body,
          enabled: !busy,
          minLines: 3,
          maxLines: 8,
          maxLength: 2000,
          decoration: const InputDecoration(labelText: '内容'),
        ),
        if (error != null) Text(error!, style: const TextStyle(color: amber)),
        FilledButton(onPressed: busy ? null : save, child: const Text('预览并保存')),
      ],
    ),
  );
}
