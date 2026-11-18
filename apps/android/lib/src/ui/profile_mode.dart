import 'package:material_ui/material_ui.dart';

import 'package:url_launcher/url_launcher.dart';

import '../services/cloud_session.dart';
import 'theme.dart';

class ProfileModeBar extends StatelessWidget {
  const ProfileModeBar({
    required this.mode,
    required this.busy,
    required this.change,
    super.key,
  });
  final Json mode;
  final bool busy;
  final void Function(String action, int version) change;

  @override
  Widget build(BuildContext context) {
    final active = mode['active'] == true;
    final version = mode['version'] as int;
    final question = mode['question'] as Json?;
    if (!active || question == null) {
      return Align(
        alignment: Alignment.centerLeft,
        child: TextButton.icon(
          key: const Key('start-profile-mode'),
          icon: const Icon(Icons.person_outline, size: 18),
          label: const Text('让 DP 了解我'),
          onPressed: busy ? null : () => change('start', version),
        ),
      );
    }
    return Material(
      color: mist,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Wrap(
              children: [
                TextButton(
                  onPressed: () => showDialog<void>(
                    context: context,
                    builder: (dialog) => AlertDialog(
                      title: const Text('为什么问这个？'),
                      content: SingleChildScrollView(
                        child: SelectableText(
                          [
                            question['text'],
                            '这个话题参考${question['theme']}研究，回答只用于了解你的个人体验，不计心理测评分数。',
                            question['source'],
                            question['doi'],
                          ].whereType<String>().join('\n\n'),
                        ),
                      ),
                      actions: [
                        if (question['doi'] is String)
                          TextButton(
                            onPressed: () async {
                              final doi = question['doi'] as String;
                              if (!RegExp(r'^10\.[0-9]+/[A-Za-z0-9.()_/:-]+$')
                                  .hasMatch(doi)) {
                                return;
                              }
                              final ok = await launchUrl(
                                Uri.https('doi.org', '/$doi'),
                                mode: LaunchMode.externalApplication,
                              );
                              if (!ok && dialog.mounted) {
                                ScaffoldMessenger.maybeOf(dialog)?.showSnackBar(
                                  const SnackBar(
                                    content: Text('未能打开研究来源，可复制 DOI 查阅。'),
                                  ),
                                );
                              }
                            },
                            child: const Text('查看论文'),
                          ),
                        TextButton(
                          onPressed: () => Navigator.pop(dialog),
                          child: const Text('关闭'),
                        ),
                      ],
                    ),
                  ),
                  child: const Text('提问依据'),
                ),
                TextButton(
                  onPressed: busy ? null : () => change('skip', version),
                  child: const Text('换个话题'),
                ),
                TextButton(
                  onPressed: busy ? null : () => change('end', version),
                  child: const Text('结束了解'),
                ),
              ],
            ),
            Semantics(
              liveRegion: true,
              child: Text(
                (mode['answered'] == true
                        ? question['theme']
                        : question['text'])
                    as String,
                style: const TextStyle(color: ink),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class PrivateProfileMode extends StatefulWidget {
  const PrivateProfileMode({
    required this.session,
    required this.sending,
    super.key,
  });
  final CloudSession session;
  final bool sending;

  @override
  State<PrivateProfileMode> createState() => _PrivateProfileModeState();
}

class _PrivateProfileModeState extends State<PrivateProfileMode> {
  bool _busy = false;
  String? _error;

  Future<void> _change(String action, int version) async {
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      await widget.session.mutate('POST', '/v1/profile-mode/$action', {
        'version': version,
      });
    } catch (e) {
      if (mounted) setState(() => _error = e.toString());
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final mode = widget.session.state['profile_mode'];
    if (mode is! Json) return const SizedBox.shrink();
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        ProfileModeBar(
          mode: mode,
          busy: _busy || widget.sending,
          change: _change,
        ),
        if (widget.session.rows('profile_focus').isNotEmpty &&
            mode['active'] != true)
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 14),
            child: Text(
              "这次可核对：${widget.session.rows('profile_focus').map((p) => p['text']).join('；')}",
              style: editionMeta,
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
            ),
          ),
        if (_error != null)
          Text(
            _error!,
            style: TextStyle(color: Theme.of(context).colorScheme.error),
          ),
      ],
    );
  }
}
