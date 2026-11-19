part of 'cloud_chat.dart';

class _ChatLabel extends StatelessWidget {
  const _ChatLabel(this.text, {required this.onPhoto});
  final String text;
  final bool onPhoto;
  @override
  Widget build(BuildContext context) => DecoratedBox(
    decoration: BoxDecoration(
      color: onPhoto ? Colors.white : Colors.transparent,
      borderRadius: BorderRadius.circular(6),
    ),
    child: Padding(
      padding: EdgeInsets.symmetric(horizontal: onPhoto ? 5 : 0, vertical: 1),
      child: Text(
        text,
        style: const TextStyle(fontSize: 12, color: quiet, height: 1.4),
      ),
    ),
  );
}

class _ChatMessage extends StatelessWidget {
  const _ChatMessage({
    super.key,
    required this.message,
    required this.own,
    required this.onPhoto,
    this.onActions,
  });
  final Json message;
  final bool own;
  final bool onPhoto;
  final VoidCallback? onActions;
  @override
  Widget build(BuildContext context) {
    final ai = message['role'] == 'assistant';
    final label = ai
        ? 'DP'
        : own
        ? '我'
        : '伴侣';
    final stamp = message['created_at'];
    final localTime = stamp is int && stamp > 0 && stamp < 253402300800
        ? DateTime.fromMillisecondsSinceEpoch(stamp * 1000).toLocal()
        : null;
    final author = localTime == null
        ? label
        : '$label · ${localTime.month}月${localTime.day}日 ${localTime.hour.toString().padLeft(2, '0')}:${localTime.minute.toString().padLeft(2, '0')}';
    final mark = Container(
      width: 34,
      height: 34,
      alignment: Alignment.center,
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(11),
        color: ai
            ? chatAccent
            : own
            ? chatTint
            : _chatSurface,
      ),
      child: ai
          ? const FittedBox(
              fit: BoxFit.scaleDown,
              child: Text(
                'DP',
                style: TextStyle(
                  color: Colors.white,
                  fontSize: 11,
                  fontWeight: FontWeight.w600,
                ),
              ),
            )
          : Icon(
              own ? Icons.dark_mode_outlined : Icons.star_border_rounded,
              size: 19,
              color: own ? chatAccent : ink,
            ),
    );
    return Padding(
      padding: const EdgeInsets.only(bottom: 15),
      child: Row(
        textDirection: own ? TextDirection.rtl : TextDirection.ltr,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          if (onActions == null)
            ExcludeSemantics(child: mark)
          else
            Tooltip(
              message: '共同消息操作',
              child: Semantics(
                button: true,
                child: InkWell(
                  onTap: onActions,
                  borderRadius: BorderRadius.circular(11),
                  child: mark,
                ),
              ),
            ),
          const SizedBox(width: 8),
          Flexible(
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 306),
              child: Column(
                crossAxisAlignment: own
                    ? CrossAxisAlignment.end
                    : CrossAxisAlignment.start,
                children: [
                  _ChatLabel(
                    message['_localDelivery'] == null
                        ? author
                        : '$author · ${message['_localDelivery']}',
                    onPhoto: onPhoto,
                  ),
                  const SizedBox(height: 3),
                  Container(
                    decoration: BoxDecoration(
                      color: own
                          ? chatAccent
                          : ai
                          ? _chatSurface
                          : paper,
                      border: own ? null : Border.all(color: chatBorder),
                      borderRadius: BorderRadius.only(
                        topLeft: Radius.circular(own ? 16 : 5),
                        topRight: Radius.circular(own ? 5 : 16),
                        bottomLeft: const Radius.circular(16),
                        bottomRight: const Radius.circular(16),
                      ),
                    ),
                    padding: const EdgeInsets.symmetric(
                      horizontal: 13,
                      vertical: 10,
                    ),
                    child: SelectableText(
                      message['text'] as String? ?? '',
                      style: TextStyle(
                        color: own ? Colors.white : ink,
                        fontSize: 15,
                        height: 1.6,
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}
