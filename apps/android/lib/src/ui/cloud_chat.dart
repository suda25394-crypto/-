import 'official_tools.dart';
import 'reflections.dart';

import 'package:material_ui/material_ui.dart';

import '../services/cloud_session.dart';
import 'theme.dart';
import 'dp_mandates.dart';
import 'profile_mode.dart';

part 'cloud_login.dart';
part 'cloud_chat_message.dart';

const _chatInk = Color(0xff242328);
const _chatSecondary = Color(0xff64626b);
const _chatLine = Color(0xffe9e8ec);
const _chatSurface = Color(0xfff5f5f6);
const _chatLilac = mist;
const _chatViolet = pine;

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

class CloudChat extends StatelessWidget {
  const CloudChat({
    required this.session,
    required this.scope,
    required this.openRecords,
    this.moduleId,
    this.hasBackground = false,
    this.openPlan,
    this.thread,
    this.sendInModule,
    super.key,
  });
  final CloudSession session;
  final String scope;
  final VoidCallback openRecords;
  final String? moduleId;
  final ValueChanged<String>? openPlan;
  final bool hasBackground;
  final Json? thread;
  final Future<void> Function(String text, String requestId)? sendInModule;
  @override
  Widget build(BuildContext context) => ListenableBuilder(
    listenable: session,
    builder: (_, _) => _ScopedChat(
      key: ValueKey((session, session.user['id'], scope, moduleId)),
      config: this,
    ),
  );
}

class _ScopedChat extends StatefulWidget {
  const _ScopedChat({required this.config, required super.key});
  final CloudChat config;
  @override
  State<_ScopedChat> createState() => _CloudChatState();
}

class _CloudChatState extends State<_ScopedChat> {
  CloudChat get chat => widget.config;
  final _focus = FocusNode();
  static final _dp = RegExp(
    r'(?<![A-Za-z0-9_@])@DP(?![A-Za-z0-9_])',
    caseSensitive: false,
  );
  static final _legacyAi = RegExp(
    r'(?<![A-Za-z0-9_@])@AI(?![A-Za-z0-9_])',
    caseSensitive: false,
  );
  final _input = TextEditingController();
  late final _scroll = ScrollController()..addListener(_onScroll);
  Object? _historyTail;
  int _heldMessages = 0;
  String? _outgoing, _outgoingId;
  bool _sending = false;
  Json? _receipt;
  String? _key, _failedText, _error;
  bool _unknown = false;
  bool get _shared => chat.scope == 'shared';

  void _onScroll() {
    if (_heldMessages > 0 && _scroll.offset <= 1) {
      setState(() => _historyTail = null);
    }
  }

  void _returnToLatest() {
    setState(() => _historyTail = null);
    if (_scroll.hasClients) _scroll.jumpTo(0);
  }

  List<Json> get _rows => chat.thread == null
      ? chat.session.messages(chat.scope)
      : (chat.thread!['messages'] as List).whereType<Json>().toList();

  Future<void> _send() async {
    final text = _input.text.trim();
    if (_sending || text.isEmpty) return;
    if (_shared &&
        chat.moduleId == null &&
        _legacyAi.hasMatch(text) &&
        !_dp.hasMatch(text)) {
      setState(() => _error = '要邀请 DP 请用 @DP。发普通消息时请去掉 @AI 的 @。');
      return;
    }
    if (_failedText != text || _key == null) _key = newRequestId();
    _returnToLatest();
    setState(() {
      _sending = true;
      _error = null;
      _outgoing = text;
      _outgoingId = _key;
    });
    _input.clear();
    try {
      if (chat.sendInModule case final send?) {
        await send(text, _key!);
      } else {
        final posted = await chat.session.mutate('POST', '/v1/messages', {
          'scope': chat.scope,
          'text': text,
          'request_id': _key,
        });
        if (!mounted) return;
        _receipt = posted is Json && posted['receipt'] is Json
            ? posted['receipt']
            : null;
      }
      if (!mounted) return;
      if (chat.session.connectionError == null) _outgoing = null;
      _key = null;
      _failedText = null;
      _unknown = false;
      _focus.unfocus();
    } catch (e) {
      if (!mounted) return;
      _outgoing = null;
      _input.value = TextEditingValue(
        text: text,
        selection: TextSelection.collapsed(offset: text.length),
      );
      _failedText = text;
      if (e is CloudError && e.code == 'version_conflict') _key = null;
      _error = e.toString();
      _unknown =
          e is CloudError &&
          ['outcome_unknown', 'model_outcome_unknown'].contains(e.code);
      if (e is! CloudError || e.status != 409) {
        try {
          await chat.session.refresh();
        } catch (_) {}
      }
    } finally {
      if (mounted) setState(() => _sending = false);
    }
  }

  Future<void> _submit() async {
    if (_unknown && _input.text.trim() == _failedText) {
      setState(() => _sending = true);
      try {
        await chat.session.refresh();
        if (mounted) setState(() => _error = '已重新查看聊天记录。上次调用的结果待核对，未再次请求模型。');
      } catch (e) {
        if (mounted) setState(() => _error = e.toString());
      } finally {
        if (mounted) setState(() => _sending = false);
      }
      return;
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
    _scroll.dispose();
    _focus.dispose();
    _input.dispose();
    super.dispose();
  }

  void _includeMention() {
    if (!_dp.hasMatch(_input.text)) {
      final value = '@DP ${_input.text}';
      _input.value = TextEditingValue(
        text: value,
        selection: TextSelection.collapsed(offset: value.length),
      );
    }
    _focus.requestFocus();
  }

  Future<void> _showTools() async {
    final choice = await showModalBottomSheet<String>(
      context: context,
      showDragHandle: true,
      builder: (sheet) => SafeArea(
        child: ListView(
          shrinkWrap: true,
          children: [
            if (_shared && chat.moduleId == null)
              ListTile(
                leading: const Icon(Icons.alternate_email),
                title: const Text('@DP'),
                subtitle: const Text('邀请 DP 回复这条群消息'),
                onTap: () => Navigator.pop(sheet, 'mention'),
              ),
            ListTile(
              leading: const Icon(Icons.notes_outlined),
              title: Text(chat.moduleId == null ? '草稿与记忆' : '本条草稿'),
              onTap: () => Navigator.pop(sheet, 'records'),
            ),
            ListTile(
              leading: const Icon(Icons.auto_awesome_outlined),
              title: const Text('DP 工具'),
              onTap: () => Navigator.pop(sheet, 'tools'),
            ),
            if (_receipt != null)
              ListTile(
                leading: const Icon(Icons.receipt_long_outlined),
                title: const Text('调用回执'),
                onTap: () => Navigator.pop(sheet, 'receipt'),
              ),
            if (_shared && chat.moduleId == null) ...[
              ListTile(
                leading: const Icon(Icons.forum_outlined),
                title: const Text('共同复盘'),
                onTap: () => Navigator.pop(sheet, 'review'),
              ),
              Align(
                alignment: Alignment.center,
                child: MandateInboxButton(session: chat.session),
              ),
            ],
          ],
        ),
      ),
    );
    if (!mounted || choice == null) return;
    if (choice == 'mention') {
      _includeMention();
    } else if (choice == 'records') {
      chat.openRecords();
    } else if (choice == 'receipt') {
      final r = _receipt!;
      await showDialog<void>(
        context: context,
        builder: (c) => AlertDialog(
          scrollable: true,
          title: const Text('最近一次发送回执'),
          content: SelectableText(
            r['called'] != true
                ? '服务端未发起模型调用。'
                : '模式 ${r['mode']}\n请求模型 ${r['requested_model']}\n上游报告 ${r['reported_model'] ?? "未提供"}\n时间 ${r['at'] == null ? "未知" : DateTime.fromMillisecondsSinceEpoch(r['at'] * 1000).toLocal()}\n状态 ${r['outcome']}\n输入 ${r['in_tokens'] ?? "未知"} · 输出 ${r['out_tokens'] ?? "未知"} tokens',
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(c),
              child: const Text('关闭'),
            ),
          ],
        ),
      );
    } else if (choice == 'review') {
      await Navigator.push(
        context,
        MaterialPageRoute(builder: (_) => Reflections(session: chat.session)),
      );
    } else if (choice == 'tools') {
      final draft = await Navigator.push<String>(
        context,
        MaterialPageRoute(
          builder: (_) => OfficialTools(
            session: chat.session,
            scope: chat.scope,
            moduleId: chat.moduleId,
          ),
        ),
      );
      if (mounted && draft != null) {
        _input.value = TextEditingValue(
          text: draft,
          selection: TextSelection.collapsed(offset: draft.length),
        );
        _focus.requestFocus();
      }
    }
  }

  void _messageActions(Json message) {
    showModalBottomSheet<void>(
      context: context,
      showDragHandle: true,
      builder: (_) => SafeArea(
        child: MandateFromMessage(session: chat.session, message: message),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final thread = chat.thread;
    var rows = _rows;
    // Keep the last visible history window while the reader is away from the
    // newest messages. Edits and removals still come from the current snapshot.
    _heldMessages = 0;
    if (_scroll.hasClients &&
        _scroll.offset > 1 &&
        _historyTail != null &&
        rows.isNotEmpty &&
        rows.last['id'] != _historyTail) {
      final tail = rows.lastIndexWhere(
        (message) => message['id'] == _historyTail,
      );
      if (tail >= 0) {
        _heldMessages = rows.length - tail - 1;
        rows = rows.sublist(0, tail + 1);
      }
    }
    _historyTail = rows.lastOrNull?['id'];
    if (!_sending && chat.session.connectionError == null) _outgoing = null;
    // R2 shared rows carry server-assigned IDs. Keep the labeled local
    // submission separate until its POST and read finish. Private rows can
    // already be reconciled by their exact request ID.
    final preview = _outgoing;
    if (preview != null &&
        _heldMessages == 0 &&
        !rows.any(
          (m) =>
              m['role'] == 'user' &&
              m['owner'] == chat.session.user['id'] &&
              (m['request_id'] == _outgoingId || m['id'] == _outgoingId),
        )) {
      rows = [
        ...rows,
        {
          'id': 'local-$_outgoingId',
          'role': 'user',
          'owner': chat.session.user['id'],
          'text': preview,
          '_localDelivery': _sending ? '发送中' : '已发送，等待同步',
        },
      ];
    }
    final pending = chat.session
        .rows('pending_messages')
        .where(
          (r) => r['scope'] == chat.scope && r['module_id'] == chat.moduleId,
        )
        .toList();
    final drafts = thread == null
        ? chat.session.rows('drafts')
        : (thread['drafts'] as List).whereType<Json>();
    final draftCount = drafts
        .where((d) => d['scope'] == chat.scope && d['status'] == 'pending')
        .length;
    final fixture = chat.session.state['mode'] == 'fixture';
    final privacy = _shared
        ? (thread == null ? '双方可见 · @DP 可提问' : '双方可见 · DP 围绕本条记录回复')
        : '仅自己可见 · 发给 DP';
    final plans = chat.session.rows('today_plans');
    final retired = chat.session
        .rows('journeys')
        .where((j) => j['stage'] == 'remembered' || j['stage'] == 'wish')
        .map((j) => j['plan'])
        .toSet();
    final modulePlan = chat.session
        .rows('modules')
        .where(
          (m) =>
              (m['module'] == 'date' || m['module'] == 'calendar') &&
              !retired.contains(m['id']),
        )
        .firstOrNull;
    final plan = plans.firstOrNull ?? modulePlan;
    final planId = plan?['plan'] ?? plan?['id'];
    final planCard =
        (_shared &&
            thread == null &&
            chat.openPlan != null &&
            planId is String &&
            plan != null)
        ? Padding(
            padding: const EdgeInsets.only(bottom: 12),
            child: Material(
              color: Colors.white,
              shape: RoundedRectangleBorder(
                side: const BorderSide(color: _chatLine),
                borderRadius: BorderRadius.circular(12),
              ),
              clipBehavior: Clip.antiAlias,
              child: ListTile(
                key: const Key('chat-plan'),
                onTap: () => chat.openPlan!(planId),
                leading: const Icon(
                  Icons.calendar_today_outlined,
                  color: _chatViolet,
                ),
                title: Text(
                  plan['title'] as String? ?? '共同计划',
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                ),
                subtitle: Text(
                  [
                    if (plans.isNotEmpty) '今天',
                    if (plan['clock'] is String && plan['clock'] != '')
                      plan['clock'],
                    if (plan['place'] is String && plan['place'] != '')
                      plan['place'],
                    if (plans.isEmpty) '共同计划',
                  ].join(' · '),
                ),
                trailing: const Icon(Icons.chevron_right),
              ),
            ),
          )
        : null;
    final controls = Column(
      children: [
        Padding(
          padding: const EdgeInsets.symmetric(vertical: 7),
          child: _ChatLabel(
            fixture && thread == null ? '$privacy · 合成联调' : privacy,
            onPhoto: chat.hasBackground,
          ),
        ),
        if (!_shared && thread == null)
          Material(
            color: chat.hasBackground ? Colors.white : Colors.transparent,
            child: PrivateProfileMode(session: chat.session, sending: _sending),
          ),
        if (draftCount > 0 || thread != null)
          TextButton(
            onPressed: chat.openRecords,
            child: Text(
              thread != null ? '本条草稿（$draftCount）' : '草稿 $draftCount / 记忆',
            ),
          ),
        if (pending.isNotEmpty && !_sending)
          TextButton.icon(
            onPressed: () => _resumePending(pending),
            icon: const Icon(Icons.replay, size: 16),
            label: Text('我的待处理消息（${pending.length}）'),
          ),
      ],
    );
    return SafeArea(
      top: false,
      bottom: false,
      child: Column(
        children: [
          ConstrainedBox(
            constraints: BoxConstraints(
              maxHeight:
                  (MediaQuery.sizeOf(context).height -
                          MediaQuery.viewInsetsOf(context).bottom)
                      .clamp(160.0, 1100.0) *
                  .28,
            ),
            child: SingleChildScrollView(
              padding: const EdgeInsets.symmetric(horizontal: 14),
              child: controls,
            ),
          ),
          Expanded(
            child: Stack(
              fit: StackFit.expand,
              children: [
                LayoutBuilder(
                  builder: (context, box) => Align(
                    alignment: Alignment.topCenter,
                    child: ListView.builder(
                      key: PageStorageKey((
                        'conversation',
                        chat.session.user['id'],
                        chat.scope,
                        chat.moduleId,
                      )),
                      reverse: true,
                      controller: _scroll,
                      findChildIndexCallback: (key) {
                        if (key is! ValueKey) return null;
                        final position = rows.lastIndexWhere(
                          (row) => row['id'] == key.value,
                        );
                        if (position < 0) return null;
                        return rows.length -
                            1 -
                            position +
                            (planCard == null ? 0 : 1);
                      },
                      shrinkWrap: true,
                      padding: const EdgeInsets.fromLTRB(14, 2, 14, 8),
                      itemCount:
                          (rows.isEmpty ? 1 : rows.length) +
                          (planCard == null ? 0 : 1),
                      itemBuilder: (_, index) {
                        if (index == 0 && planCard != null) return planCard;
                        if (rows.isEmpty) {
                          return Padding(
                            padding: EdgeInsets.symmetric(
                              vertical: (box.maxHeight * .1).clamp(12.0, 60.0),
                            ),
                            child: Center(
                              child: _ChatLabel(
                                _shared ? '给共同空间写下第一条消息。' : '你的私人对话从这里开始。',
                                onPhoto: chat.hasBackground,
                              ),
                            ),
                          );
                        }
                        final m =
                            rows[rows.length -
                                index -
                                1 +
                                (planCard == null ? 0 : 1)];
                        return _ChatMessage(
                          key: m['id'] == null ? null : ValueKey(m['id']),
                          message: m,
                          own:
                              m['owner'] == chat.session.user['id'] &&
                              m['role'] != 'assistant',
                          onPhoto: chat.hasBackground,
                          onActions:
                              _shared &&
                                  thread == null &&
                                  m['role'] == 'user' &&
                                  m['_localDelivery'] == null &&
                                  m['id'] != null
                              ? () => _messageActions(m)
                              : null,
                        );
                      },
                    ),
                  ),
                ),
                if (_heldMessages > 0)
                  Positioned(
                    right: 14,
                    bottom: 8,
                    child: FilledButton.tonal(
                      key: const Key('chat-new-messages'),
                      onPressed: _returnToLatest,
                      child: Text('查看 $_heldMessages 条新消息'),
                    ),
                  ),
              ],
            ),
          ),
          if (_error != null)
            Container(
              color: Colors.white,
              width: double.infinity,
              padding: const EdgeInsets.fromLTRB(12, 4, 12, 2),
              constraints: BoxConstraints(
                maxHeight: MediaQuery.sizeOf(context).height * .13,
              ),
              child: SingleChildScrollView(
                child: Semantics(
                  liveRegion: true,
                  child: Text(
                    _error!,
                    style: TextStyle(
                      color: Theme.of(context).colorScheme.error,
                      fontSize: 13,
                    ),
                  ),
                ),
              ),
            ),
          DecoratedBox(
            decoration: const BoxDecoration(
              color: Colors.white,
              border: Border(top: BorderSide(color: _chatLine)),
            ),
            child: SafeArea(
              top: false,
              child: Padding(
                padding: const EdgeInsets.fromLTRB(7, 7, 7, 8),
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.end,
                  children: [
                    IconButton(
                      key: const Key('chat-more'),
                      tooltip: '更多聊天操作',
                      onPressed: _sending ? null : _showTools,
                      icon: const Icon(Icons.add),
                    ),
                    Expanded(
                      child: TextField(
                        key: ValueKey('cloud-${chat.scope}-input'),
                        controller: _input,
                        focusNode: _focus,
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
                        style: const TextStyle(
                          color: _chatInk,
                          fontSize: 15,
                          height: 1.45,
                        ),
                        decoration: InputDecoration(
                          hintText: thread != null
                              ? '围绕这条记录聊聊…'
                              : _shared
                              ? '发到我们仨，@DP 可提问…'
                              : '只发给 DP…',
                          hintStyle: const TextStyle(color: _chatSecondary),
                          filled: true,
                          fillColor: _chatSurface,
                          isDense: true,
                          contentPadding: const EdgeInsets.symmetric(
                            horizontal: 12,
                            vertical: 11,
                          ),
                          border: OutlineInputBorder(
                            borderRadius: BorderRadius.circular(11),
                            borderSide: BorderSide.none,
                          ),
                          enabledBorder: OutlineInputBorder(
                            borderRadius: BorderRadius.circular(11),
                            borderSide: BorderSide.none,
                          ),
                          focusedBorder: OutlineInputBorder(
                            borderRadius: BorderRadius.circular(11),
                            borderSide: const BorderSide(color: _chatViolet),
                          ),
                        ),
                      ),
                    ),
                    const SizedBox(width: 3),
                    ValueListenableBuilder<TextEditingValue>(
                      valueListenable: _input,
                      builder: (_, value, _) {
                        final enabled =
                            value.text.trim().isNotEmpty && !_sending;
                        final retry =
                            _failedText != null &&
                            value.text.trim() == _failedText;
                        return IconButton(
                          key: const Key('chat-send'),
                          tooltip: _sending
                              ? '发送中'
                              : retry
                              ? (_unknown ? '核对结果' : '重试')
                              : '发送',
                          onPressed: enabled ? _submit : null,
                          icon: Container(
                            width: 42,
                            height: 42,
                            decoration: BoxDecoration(
                              shape: BoxShape.circle,
                              color: enabled ? _chatViolet : _chatSurface,
                            ),
                            child: Center(
                              child: _sending
                                  ? const SizedBox(
                                      width: 20,
                                      height: 20,
                                      child: CircularProgressIndicator(
                                        strokeWidth: 2,
                                      ),
                                    )
                                  : Icon(
                                      retry
                                          ? Icons.replay
                                          : Icons.arrow_upward_rounded,
                                      size: 21,
                                      color: enabled
                                          ? Colors.white
                                          : _chatSecondary,
                                    ),
                            ),
                          ),
                          padding: const EdgeInsets.all(3),
                        );
                      },
                    ),
                  ],
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}
