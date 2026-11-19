part of 'main.dart';

class ErrorMessage extends StatelessWidget {
  const ErrorMessage(this.message, {super.key});
  final String message;

  @override
  Widget build(BuildContext context) => Semantics(
    liveRegion: true,
    child: Text(
      message,
      style: Theme.of(context).textTheme.bodyMedium
          ?.copyWith(color: Theme.of(context).colorScheme.error),
    ),
  );
}

class MeetingListPage extends StatefulWidget {
  const MeetingListPage({super.key, required this.controller});
  final CoupleController controller;

  @override
  State<MeetingListPage> createState() => _MeetingListPageState();
}

class _MeetingListPageState extends State<MeetingListPage> {
  bool opening = false;

  Future<void> open(Meeting meeting) async {
    if (opening) return;
    setState(() => opening = true);
    final c = widget.controller;
    try {
      await c.selectMeeting(meeting.id);
      if (!mounted || !c.signedIn || c.selected?.id != meeting.id) return;
      await Navigator.of(context).push<void>(
        MaterialPageRoute(
          builder: (_) => _MeetingDetail(controller: c, id: meeting.id),
        ),
      );
    } finally {
      if (mounted) setState(() => opening = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final c = widget.controller, text = Theme.of(context).textTheme;
    return Scaffold(
      appBar: AppBar(
        title: const Text('共同日程'),
        actions: [
          IconButton(
            tooltip: '刷新日程',
            onPressed: c.busy ? null : c.refresh,
            icon: const Icon(Icons.refresh_rounded),
          ),
          PopupMenuButton<String>(
            tooltip: '账号',
            itemBuilder: (context) => [
              if (c.userName.isNotEmpty)
                PopupMenuItem<String>(enabled: false, child: Text(c.userName)),
              const PopupMenuItem<String>(
                value: 'source',
                child: Text('本版源码与许可'),
              ),
              const PopupMenuItem<String>(value: 'logout', child: Text('退出账号')),
            ],
            onSelected: (choice) {
              if (choice == 'source') {
                showSourceInformation(context);
              } else if (choice == 'logout') {
                c.logout();
              }
            },
          ),
        ],
      ),
      body: SafeArea(
        top: false,
        child: Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 620),
            child: RefreshIndicator(
              onRefresh: c.refresh,
              child: ListView(
                physics: const AlwaysScrollableScrollPhysics(),
                padding: const EdgeInsets.fromLTRB(18, 12, 18, 36),
                children: [
                  if (c.error case final error?) ...[
                    ErrorMessage(error),
                    const SizedBox(height: 16),
                  ],
                  if (c.meetings.isEmpty)
                    Padding(
                      padding: const EdgeInsets.only(top: 56),
                      child: Column(
                        children: [
                          const Icon(
                            Icons.calendar_month_outlined,
                            size: 46,
                            color: grape,
                          ),
                          const SizedBox(height: 18),
                          Text('还没有可改期的约会', style: text.titleLarge),
                          const SizedBox(height: 8),
                          const Text(
                            '在现版双生宇宙的共同日程里保存有日期和时间的约会，再回来刷新。',
                            textAlign: TextAlign.center,
                          ),
                          const SizedBox(height: 12),
                          TextButton(
                            onPressed: c.refresh,
                            child: const Text('刷新日程'),
                          ),
                        ],
                      ),
                    ),
                  for (final m in c.meetings)
                    Padding(
                      padding: const EdgeInsets.only(bottom: 12),
                      child: GestureDetector(
                        excludeFromSemantics: true,
                        onTap: () => open(m),
                        child: ChatCard(
                          key: ValueKey(m.id),
                          icon: Icons.event_outlined,
                          title: m.title,
                          titleMaxLines: 2,
                          children: [
                            Padding(
                              padding: const EdgeInsets.symmetric(
                                horizontal: ChatCard.inset,
                              ),
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text(
                                    m.clock.isEmpty ? '时间待定' : m.clock,
                                    style: text.headlineMedium?.copyWith(
                                      color: grape,
                                      fontWeight: FontWeight.w600,
                                    ),
                                  ),
                                  Text(
                                    [
                                      m.day,
                                      if (m.place.isNotEmpty) m.place,
                                    ].join(' · '),
                                    style: text.bodyMedium?.copyWith(
                                      color: muted,
                                    ),
                                  ),
                                ],
                              ),
                            ),
                            ChatCardFooter(
                              label: '打开约会',
                              semanticsLabel: '打开约会，${m.title}',
                              icon: Icons.chevron_right,
                              onTap: () => open(m),
                            ),
                          ],
                        ),
                      ),
                    ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _MeetingDetail extends StatefulWidget {
  const _MeetingDetail({required this.controller, required this.id});
  final CoupleController controller;
  final String id;

  @override
  State<_MeetingDetail> createState() => _MeetingDetailState();
}

class _MeetingDetailState extends State<_MeetingDetail> {
  final input = TextEditingController();
  final list = ScrollController();
  final drafts = <String, String>{};
  bool acted = false;
  bool leaving = false;
  String? decisionNotice;

  CoupleController get c => widget.controller;

  @override
  void dispose() {
    input.dispose();
    list.dispose();
    super.dispose();
  }

  void toEnd() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted || !list.hasClients) return;
      list.animateTo(
        list.position.maxScrollExtent,
        duration: const Duration(milliseconds: 180),
        curve: Curves.easeOut,
      );
    });
  }

  Future<void> changeScope(String scope) async {
    if (scope == c.scope || acted || c.busy) return;
    FocusScope.of(context).unfocus();
    final previousScope = c.scope;
    drafts[previousScope] = input.text;
    input.clear();
    setState(() {
      acted = true;
      decisionNotice = null;
    });
    try {
      await c.setScope(scope);
      if (!mounted) return;
      input.text = drafts[c.scope] ?? '';
      toEnd();
    } finally {
      if (mounted) setState(() => acted = false);
    }
  }

  Future<void> send() async {
    final value = input.text.trim();
    if (value.isEmpty || acted || c.busy || c.proposal != null) return;
    setState(() {
      acted = true;
      decisionNotice = null;
    });
    FocusScope.of(context).unfocus();
    try {
      await c.send(value);
      if (!mounted) return;
      if (c.error == null || c.proposal != null) {
        input.clear();
        drafts.remove(c.scope);
      }
      toEnd();
    } finally {
      if (mounted) setState(() => acted = false);
    }
  }

  Future<void> decide(bool confirm) async {
    if (acted || c.busy || c.proposal == null) return;
    setState(() {
      acted = true;
      decisionNotice = null;
    });
    try {
      if (confirm) {
        await c.confirm();
      } else {
        await c.cancel();
      }
      if (!mounted) return;
      if (c.error == null && c.proposal == null) {
        decisionNotice = confirm ? '已更新原约会' : '已取消本次改期';
      }
      toEnd();
    } finally {
      if (mounted) setState(() => acted = false);
    }
  }

  void fillExample() {
    const value = '把约会推迟半小时';
    input.value = const TextEditingValue(
      text: value,
      selection: TextSelection.collapsed(offset: value.length),
    );
  }

  @override
  Widget build(BuildContext context) => ListenableBuilder(
    listenable: c,
    builder: (context, _) {
      if (!c.signedIn && !leaving) {
        leaving = true;
        WidgetsBinding.instance.addPostFrameCallback((_) {
          if (mounted && Navigator.of(context).canPop())
            Navigator.of(context).pop();
        });
      }
      final m = c.selected;
      if (!c.signedIn || m == null || m.id != widget.id) {
        return Scaffold(
          appBar: AppBar(title: const Text('约会详情')),
          body: const Center(child: Text('这条约会暂时不可用，请返回共同日程查看。')),
        );
      }
      final text = Theme.of(context).textTheme;
      final lines = projectTranscript(c.messages, c.userId);
      final proposal = c.proposal;
      final busy = c.busy || acted;
      return Scaffold(
        appBar: AppBar(
          toolbarHeight: 72,
          title: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(m.title, maxLines: 1, overflow: TextOverflow.ellipsis),
              Text(
                m.clock.isEmpty ? '尚未安排集合时间' : '已确认时间 ${m.clock}',
                key: const Key('confirmed-time'),
                style: text.labelLarge?.copyWith(
                  color: grape,
                  fontWeight: FontWeight.w700,
                ),
              ),
            ],
          ),
          actions: [
            IconButton(
              tooltip: '刷新约会',
              onPressed: busy ? null : c.refresh,
              icon: const Icon(Icons.refresh_rounded),
            ),
          ],
        ),
        body: SafeArea(
          top: false,
          child: Center(
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 620),
              child: Column(
                children: [
                  Expanded(
                    child: ListView(
                      controller: list,
                      padding: const EdgeInsets.fromLTRB(16, 4, 16, 16),
                      children: [
                        Row(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            const Icon(
                              Icons.calendar_today_outlined,
                              size: 18,
                              color: muted,
                            ),
                            const SizedBox(width: 8),
                            Expanded(
                              child: Text(
                                [
                                  m.day,
                                  if (m.place.isNotEmpty) m.place,
                                  if (m.address.isNotEmpty &&
                                      m.address != m.place)
                                    m.address,
                                ].join(' · '),
                                style: text.bodyMedium?.copyWith(color: muted),
                              ),
                            ),
                          ],
                        ),
                        const SizedBox(height: 18),
                        SegmentedButton<String>(
                          segments: const [
                            ButtonSegment(
                              value: 'private',
                              label: Text('私下问 DP'),
                              icon: Icon(Icons.lock_outline_rounded),
                            ),
                            ButtonSegment(
                              value: 'shared',
                              label: Text('两人共同聊'),
                              icon: Icon(Icons.people_outline),
                            ),
                          ],
                          selected: {c.scope},
                          showSelectedIcon: false,
                          onSelectionChanged: busy
                              ? null
                              : (s) => changeScope(s.single),
                        ),
                        const SizedBox(height: 8),
                        Text(
                          c.scope == 'private'
                              ? '这里的对话只对你可见。确认改期后，对方会看到新时间。'
                              : '你们两人都能查看这段对话和已确认的约会。',
                          style: text.bodySmall?.copyWith(color: muted),
                        ),
                        const SizedBox(height: 16),
                        for (final line in lines)
                          _LineBubble(key: ValueKey(line.id), line: line),
                        if (decisionNotice case final notice?)
                          Semantics(
                            liveRegion: true,
                            child: Padding(
                              padding: const EdgeInsets.only(bottom: 8),
                              child: Text(
                                notice,
                                style: text.labelLarge?.copyWith(color: muted),
                              ),
                            ),
                          ),
                        if (proposal != null)
                          _ProposalCard(
                            proposal: proposal,
                            enabled: !busy,
                            onConfirm: () => decide(true),
                            onCancel: () => decide(false),
                          ),
                        if (c.error case final error?) ...[
                          const SizedBox(height: 10),
                          ErrorMessage(error),
                          Align(
                            alignment: Alignment.centerLeft,
                            child: TextButton.icon(
                              icon: const Icon(Icons.refresh, size: 16),
                              label: const Text('核对最新状态'),
                              onPressed: busy ? null : c.refresh,
                            ),
                          ),
                        ],
                      ],
                    ),
                  ),
                  if (proposal == null)
                    Padding(
                      padding: const EdgeInsets.fromLTRB(16, 4, 16, 12),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          if (MediaQuery.viewInsetsOf(context).bottom == 0)
                            ActionChip(
                              onPressed: busy ? null : fillExample,
                              label: const Text('把约会推迟半小时'),
                              avatar: const Icon(
                                Icons.schedule_outlined,
                                size: 16,
                              ),
                            ),
                          const SizedBox(height: 4),
                          Row(
                            crossAxisAlignment: CrossAxisAlignment.end,
                            children: [
                              Expanded(
                                child: TextField(
                                  key: const Key('dp-input'),
                                  controller: input,
                                  minLines: 1,
                                  maxLines: 3,
                                  readOnly: busy,
                                  decoration: const InputDecoration(
                                    labelText: '告诉 DP 怎么改',
                                  ),
                                ),
                              ),
                              const SizedBox(width: 8),
                              ValueListenableBuilder<TextEditingValue>(
                                valueListenable: input,
                                builder: (_, value, _) => IconButton.filled(
                                  key: const Key('dp-send'),
                                  tooltip: '发送',
                                  onPressed:
                                      !busy && value.text.trim().isNotEmpty
                                      ? send
                                      : null,
                                  icon: busy
                                      ? const SizedBox.square(
                                          dimension: 19,
                                          child: CircularProgressIndicator(
                                            strokeWidth: 2,
                                          ),
                                        )
                                      : const Icon(Icons.arrow_upward_rounded),
                                ),
                              ),
                            ],
                          ),
                        ],
                      ),
                    ),
                ],
              ),
            ),
          ),
        ),
      );
    },
  );
}

class _LineBubble extends StatelessWidget {
  const _LineBubble({super.key, required this.line});
  final CoupleLine line;

  @override
  Widget build(BuildContext context) {
    final text = Theme.of(context).textTheme;
    return Align(
      alignment: line.isMine ? Alignment.centerRight : Alignment.centerLeft,
      child: Container(
        constraints: BoxConstraints(
          maxWidth: MediaQuery.sizeOf(context).width.clamp(0.0, 620.0) * .8,
        ),
        margin: const EdgeInsets.only(bottom: 10),
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
        decoration: BoxDecoration(
          color: line.isMine ? grape : const Color(0xfff5edf7),
          borderRadius: BorderRadius.circular(16),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(
              line.authorLabel,
              style: text.labelMedium?.copyWith(
                color: line.isMine ? Colors.white : muted,
              ),
            ),
            const SizedBox(height: 3),
            SelectableText(
              line.text,
              style: text.bodyLarge?.copyWith(
                color: line.isMine ? Colors.white : ink,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _ProposalCard extends StatelessWidget {
  const _ProposalCard({
    required this.proposal,
    required this.enabled,
    required this.onConfirm,
    required this.onCancel,
  });
  final DelayProposal proposal;
  final bool enabled;
  final VoidCallback onConfirm, onCancel;

  @override
  Widget build(BuildContext context) {
    final text = Theme.of(context).textTheme;
    return ChatCard(
      key: const Key('proposal-card'),
      icon: Icons.edit_calendar_outlined,
      title: 'DP 的改期建议',
      titleMaxLines: 2,
      children: [
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: ChatCard.inset),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(proposal.title, style: text.titleMedium),
              const SizedBox(height: 10),
              Text(
                '原时间 ${proposal.before}',
                style: text.bodyMedium?.copyWith(color: muted),
              ),
              const SizedBox(height: 4),
              Text(
                '改为 ${proposal.after}',
                style: text.titleMedium?.copyWith(
                  color: grape,
                  fontWeight: FontWeight.w700,
                ),
              ),
            ],
          ),
        ),
        Padding(
          padding: const EdgeInsets.fromLTRB(
            ChatCard.inset,
            10,
            ChatCard.inset,
            8,
          ),
          child: Wrap(
            alignment: WrapAlignment.end,
            spacing: 8,
            runSpacing: 2,
            children: [
              TextButton(
                key: const Key('cancel-delay'),
                onPressed: enabled ? onCancel : null,
                child: const Text('取消'),
              ),
              FilledButton(
                key: const Key('confirm-delay'),
                onPressed: enabled ? onConfirm : null,
                child: const Text('确认改期'),
              ),
            ],
          ),
        ),
      ],
    );
  }
}
