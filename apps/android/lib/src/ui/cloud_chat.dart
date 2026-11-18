import 'package:material_ui/material_ui.dart';

import '../services/cloud_session.dart';
import 'theme.dart';
import 'dp_mandates.dart';

class LoginScreen extends StatefulWidget {
  const LoginScreen({required this.session, required this.onDemo, super.key});
  final CloudSession session;
  final VoidCallback onDemo;
  @override
  State<LoginScreen> createState() => _LoginScreenState();
}

class _LoginScreenState extends State<LoginScreen> {
  late final _base = TextEditingController(text: widget.session.endpoint);
  final _email = TextEditingController();
  final _password = TextEditingController();
  final _form = GlobalKey<FormState>();
  bool _busy = false;
  String? _error;
  Future<void> _submit() async {
    if (_busy || !_form.currentState!.validate()) return;
    FocusManager.instance.primaryFocus?.unfocus();
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      await widget.session.login(_base.text, _email.text, _password.text);
    } catch (e) {
      if (mounted) setState(() => _error = e.toString());
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  void dispose() {
    _base.dispose();
    _email.dispose();
    _password.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(title: const Text('两个人')),
    body: SafeArea(
      child: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 540),
          child: ListView(
            shrinkWrap: true,
            padding: const EdgeInsets.all(22),
            children: [
              const Text(
                '登录私人空间',
                style: TextStyle(fontSize: 30, fontFamily: 'serif', color: ink),
              ),
              const Padding(
                padding: EdgeInsets.symmetric(vertical: 14),
                child: Text('使用已有的 Open WebUI 账号，进入你和伴侣的配对空间。'),
              ),
              Form(
                key: _form,
                child: Column(
                  children: [
                    TextFormField(
                      key: const Key('service-url'),
                      controller: _base,
                      autocorrect: false,
                      keyboardType: TextInputType.url,
                      enabled: !_busy,
                      decoration: const InputDecoration(
                        labelText: 'Muse 提供的产品服务地址',
                        hintText: 'https://…',
                      ),
                      validator: (v) {
                        try {
                          serviceUri(v ?? '');
                          return null;
                        } catch (e) {
                          return e.toString();
                        }
                      },
                    ),
                    const SizedBox(height: 12),
                    TextFormField(
                      key: const Key('account-email'),
                      controller: _email,
                      autocorrect: false,
                      keyboardType: TextInputType.emailAddress,
                      enabled: !_busy,
                      autofillHints: const [AutofillHints.username],
                      decoration: const InputDecoration(labelText: '账号邮箱'),
                      validator: (v) =>
                          (v ?? '').trim().isEmpty ? '请输入邮箱' : null,
                    ),
                    const SizedBox(height: 12),
                    TextFormField(
                      key: const Key('account-password'),
                      controller: _password,
                      obscureText: true,
                      enableSuggestions: false,
                      autocorrect: false,
                      enabled: !_busy,
                      autofillHints: const [AutofillHints.password],
                      onFieldSubmitted: (_) => _submit(),
                      decoration: const InputDecoration(labelText: '密码'),
                      validator: (v) => (v ?? '').isEmpty ? '请输入密码' : null,
                    ),
                  ],
                ),
              ),
              if (_error != null)
                Padding(
                  padding: const EdgeInsets.only(top: 12),
                  child: Semantics(
                    liveRegion: true,
                    child: Text(_error!, style: const TextStyle(color: amber)),
                  ),
                ),
              const SizedBox(height: 16),
              FilledButton(
                onPressed: _busy ? null : _submit,
                child: Text(_busy ? '正在连接…' : '登录'),
              ),
              TextButton(
                onPressed: _busy ? null : widget.onDemo,
                child: const Text('体验本机演示'),
              ),
            ],
          ),
        ),
      ),
    ),
  );
}

class CloudFeedback extends StatelessWidget {
  const CloudFeedback({
    required this.message,
    required this.onRetry,
    super.key,
  });
  final String message;
  final VoidCallback onRetry;
  @override
  Widget build(BuildContext context) => Material(
    color: amberWash,
    child: Padding(
      padding: const EdgeInsets.symmetric(horizontal: 12),
      child: Row(
        children: [
          Expanded(
            child: Semantics(
              liveRegion: true,
              child: Text(message, style: const TextStyle(color: ink)),
            ),
          ),
          TextButton(onPressed: onRetry, child: const Text('重试')),
        ],
      ),
    ),
  );
}

class CloudChat extends StatefulWidget {
  const CloudChat({
    required this.session,
    required this.scope,
    required this.openRecords,
    this.moduleId,
    this.thread,
    this.sendInModule,
    super.key,
  });
  final CloudSession session;
  final String scope;
  final VoidCallback openRecords;
  final String? moduleId;
  final Json? thread;
  final Future<void> Function(String text, String requestId)? sendInModule;
  @override
  State<CloudChat> createState() => _CloudChatState();
}

class _CloudChatState extends State<CloudChat> {
  final _input = TextEditingController();
  bool _sending = false;
  String? _key, _failedText, _error;
  bool _unknown = false;
  bool get _shared => widget.scope == 'shared';
  Future<void> _send() async {
    final text = _input.text.trim();
    if (_sending || text.isEmpty) return;
    if (_failedText != text || _key == null) _key = newRequestId();
    setState(() {
      _sending = true;
      _error = null;
    });
    try {
      if (widget.sendInModule case final send?) {
        await send(text, _key!);
      } else {
        await widget.session.mutate('POST', '/v1/messages', {
          'scope': widget.scope,
          'text': text,
          'request_id': _key,
        });
      }
      if (!mounted) return;
      _input.clear();
      _key = null;
      _failedText = null;
      _unknown = false;
      FocusManager.instance.primaryFocus?.unfocus();
    } catch (e) {
      if (!mounted) return;
      _failedText = text;
      if (e is CloudError && e.code == 'version_conflict') _key = null;
      _error = e.toString();
      _unknown =
          e is CloudError &&
          ['outcome_unknown', 'model_outcome_unknown'].contains(e.code);
      try {
        await widget.session.refresh();
      } catch (_) {}
    } finally {
      if (mounted) setState(() => _sending = false);
    }
  }

  Future<void> _submit() async {
    if (_unknown && _input.text.trim() == _failedText) {
      final yes = await showDialog<bool>(
        context: context,
        builder: (c) => AlertDialog(
          title: const Text('重新请求模型？'),
          content: const Text('上次调用结果尚未确定。再次调用可能消耗一次额度。'),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(c, false),
              child: const Text('返回'),
            ),
            FilledButton(
              onPressed: () => Navigator.pop(c, true),
              child: const Text('重新请求'),
            ),
          ],
        ),
      );
      if (yes != true || !mounted) return;
      _key = null;
      _unknown = false;
    }
    await _send();
  }

  Future<void> _resumePending(List<Json> pending) async {
    final selected = await showModalBottomSheet<Json>(
      context: context,
      builder: (sheet) => SafeArea(
        child: ListView(
          shrinkWrap: true,
          children: [
            const ListTile(
              title: Text('我的待处理消息'),
              subtitle: Text('选取一条恢复到输入框。保持原文提交，将使用原来的提交编号。'),
            ),
            for (final row in pending)
              ListTile(
                title: Text(
                  row['text'].toString(),
                  maxLines: 3,
                  overflow: TextOverflow.ellipsis,
                ),
                subtitle: Text(
                  row['busy'] == true
                      ? '服务端正在处理'
                      : row['uncertain'] == true
                      ? '模型结果尚未确定'
                      : '等待重试',
                ),
                enabled: row['busy'] != true,
                onTap: () => Navigator.pop(sheet, row),
              ),
          ],
        ),
      ),
    );
    if (selected == null || !mounted) return;
    final value = selected['text'].toString();
    setState(() {
      _input.value = TextEditingValue(
        text: value,
        selection: TextSelection.collapsed(offset: value.length),
      );
      _key = selected['request_id'].toString();
      _failedText = value;
      _unknown = selected['uncertain'] == true;
      _error = '已恢复原消息，请核对后重试。';
    });
  }

  @override
  void dispose() {
    _input.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => ListenableBuilder(
    listenable: widget.session,
    builder: (context, _) {
      final thread = widget.thread;
      final rows = thread == null
          ? widget.session.messages(widget.scope)
          : (thread['messages'] as List).whereType<Json>().toList();
      final pending = widget.session
          .rows('pending_messages')
          .where(
            (r) =>
                r['scope'] == widget.scope && r['module_id'] == widget.moduleId,
          )
          .toList();
      final drafts = thread == null
          ? widget.session.rows('drafts')
          : (thread['drafts'] as List).whereType<Json>();
      final draftCount = drafts
          .where((d) => d['scope'] == widget.scope && d['status'] == 'pending')
          .length;
      return SafeArea(
        top: false,
        child: Column(
          children: [
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 14),
              child: Row(
                children: [
                  Expanded(
                    child: Text(
                      thread != null && _shared
                          ? '双方可见 · DP 围绕本条记录回复'
                          : _shared
                          ? '双方可见 · @DP 或 @AI 邀请回复'
                          : '仅自己可见 · 发给 DP',
                      style: editionMeta,
                    ),
                  ),
                  if (_shared && thread == null)
                    MandateInboxButton(session: widget.session),
                  TextButton(
                    onPressed: widget.openRecords,
                    child: Text(
                      thread != null
                          ? '本条草稿（$draftCount）'
                          : draftCount > 0
                          ? '草稿 $draftCount / 记忆'
                          : '草稿与记忆',
                    ),
                  ),
                ],
              ),
            ),
            if (pending.isNotEmpty && !_sending)
              TextButton.icon(
                onPressed: () => _resumePending(pending),
                icon: const Icon(Icons.replay, size: 16),
                label: Text('我的待处理消息（${pending.length}）'),
              ),
            Expanded(
              child: rows.isEmpty
                  ? Center(
                      child: Text(_shared ? '给共同空间写下第一条消息。' : '你的私人对话从这里开始。'),
                    )
                  : ListView.builder(
                      key: PageStorageKey('messages-${widget.scope}'),
                      reverse: true,
                      padding: const EdgeInsets.symmetric(
                        horizontal: 20,
                        vertical: 8,
                      ),
                      itemCount: rows.length,
                      itemBuilder: (c, index) {
                        final m = rows[rows.length - index - 1],
                            ai = m['role'] == 'assistant';
                        final own = m['owner'] == widget.session.user['id'];
                        return Padding(
                          padding: const EdgeInsets.only(bottom: 15),
                          child: Column(
                            crossAxisAlignment: own && !ai
                                ? CrossAxisAlignment.end
                                : CrossAxisAlignment.start,
                            children: [
                              Text(
                                ai
                                    ? (widget.session.state['mode'] == 'fixture'
                                          ? 'AI · 合成联调'
                                          : 'AI')
                                    : own
                                    ? '我'
                                    : '伴侣',
                                style: editionMeta,
                              ),
                              const SizedBox(height: 3),
                              Container(
                                padding: const EdgeInsets.symmetric(
                                  horizontal: 12,
                                  vertical: 9,
                                ),
                                color: ai
                                    ? mist
                                    : own
                                    ? warmSurface
                                    : amberWash,
                                child: SelectableText(
                                  m['text'] as String? ?? '',
                                ),
                              ),
                              if (_shared && thread == null && !ai)
                                MandateFromMessage(
                                  session: widget.session,
                                  message: m,
                                ),
                            ],
                          ),
                        );
                      },
                    ),
            ),
            if (_error != null)
              Padding(
                padding: const EdgeInsets.all(7),
                child: Text(_error!, style: const TextStyle(color: amber)),
              ),
            Padding(
              padding: const EdgeInsets.fromLTRB(10, 5, 10, 10),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.end,
                children: [
                  if (_shared && thread == null)
                    TextButton(
                      onPressed: _sending
                          ? null
                          : () {
                              if (!RegExp(
                                r'(?<![A-Za-z0-9_@])@(?:AI|DP)(?![A-Za-z0-9_])',
                                caseSensitive: false,
                              ).hasMatch(_input.text)) {
                                _input.value = TextEditingValue(
                                  text: '@DP ${_input.text}',
                                  selection: TextSelection.collapsed(
                                    offset: _input.text.length + 4,
                                  ),
                                );
                              }
                            },
                      child: const Text('@DP'),
                    ),
                  Expanded(
                    child: TextField(
                      key: ValueKey('cloud-${widget.scope}-input'),
                      controller: _input,
                      minLines: 1,
                      maxLines: 3,
                      maxLength: 2000,
                      buildCounter: (
                        _, {
                        required currentLength,
                        required isFocused,
                        required maxLength,
                      }) => null,
                      enabled: !_sending,
                      decoration: InputDecoration(
                        labelText: _shared ? '共同消息' : '私人消息',
                      ),
                    ),
                  ),
                  const SizedBox(width: 6),
                  TextButton(
                    onPressed: _sending ? null : _submit,
                    child: Text(
                      _sending
                          ? '发送中'
                          : _error != null
                          ? '重试'
                          : '发送',
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      );
    },
  );
}
