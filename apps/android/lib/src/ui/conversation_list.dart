import 'package:material_ui/material_ui.dart';

import '../services/cloud_session.dart';
import 'theme.dart';

class ConversationList extends StatelessWidget {
  const ConversationList({required this.session, super.key});

  final CloudSession session;

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(title: const Text('会话')),
    backgroundColor: chatCanvas,
    body: SafeArea(
      top: false,
      child: ListenableBuilder(
        listenable: session,
        builder: (context, _) {
          final latest = session.messages('shared').lastOrNull;
          final text = latest?['text'];
          final preview = text is String && text.trim().isNotEmpty
              ? text.trim().replaceAll(RegExp(r'\s+'), ' ')
              : '两人共享，@DP 可提问';
          return ListView(
            padding: const EdgeInsets.all(16),
            children: [
              Material(
                color: paper,
                shape: RoundedRectangleBorder(
                  side: const BorderSide(color: chatBorder),
                  borderRadius: BorderRadius.circular(20),
                ),
                clipBehavior: Clip.antiAlias,
                child: Column(
                  children: [
                    _ConversationRow(
                      scope: 'shared',
                      title: '我们仨',
                      subtitle: preview,
                      icon: Icons.forum_outlined,
                    ),
                    const Divider(height: 1, indent: 72, endIndent: 16),
                    const _ConversationRow(
                      scope: 'private',
                      title: '我和 DP',
                      subtitle: '私聊 · 仅自己可见',
                      icon: Icons.lock_outline_rounded,
                    ),
                  ],
                ),
              ),
            ],
          );
        },
      ),
    ),
  );
}

class _ConversationRow extends StatelessWidget {
  const _ConversationRow({
    required this.scope,
    required this.title,
    required this.subtitle,
    required this.icon,
  });

  final String scope;
  final String title;
  final String subtitle;
  final IconData icon;

  @override
  Widget build(BuildContext context) => InkWell(
    key: ValueKey('conversation-$scope'),
    onTap: () => Navigator.of(context).pop(scope),
    child: Padding(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 14),
      child: Row(
        children: [
          Ink(
            width: 42,
            height: 42,
            decoration: BoxDecoration(
              color: chatTint,
              borderRadius: BorderRadius.circular(13),
            ),
            child: Icon(icon, size: 22, color: chatAccent),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  title,
                  style: const TextStyle(
                    color: ink,
                    fontSize: 16,
                    fontWeight: FontWeight.w700,
                  ),
                ),
                const SizedBox(height: 3),
                Text(
                  subtitle,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(color: quiet, fontSize: 13),
                ),
              ],
            ),
          ),
          const SizedBox(width: 8),
          const Icon(Icons.chevron_right_rounded, color: quiet, size: 20),
        ],
      ),
    ),
  );
}
