// SPDX-License-Identifier: AGPL-3.0-only
// R2 returns the authorized chronological transcript of the selected record
// and visibility scope. DSH Go folds it into the same chat items as its host.
import 'package:dsh_client/dsh_client.dart';

class CoupleLine {
  const CoupleLine(
    this.id,
    this.text,
    this.authorLabel,
    this.isMine,
    this.isDp,
  );
  final String id, text, authorLabel;
  final bool isMine, isDp;
}

List<CoupleLine> projectTranscript(
  List<Map<String, dynamic>> messages,
  String myId,
) {
  final transcript = ChatTranscript();
  final owners = <int, ({String id, bool mine})>{};
  final seen = <String>{};
  for (final row in messages) {
    final id = row['id'];
    final role = row['role'];
    final text = row['text'];
    if (id is! String ||
        text is! String ||
        (role != 'user' && role != 'assistant') ||
        !seen.add(id))
      continue;
    final seq = owners.length + 1;
    final dp = role == 'assistant';
    owners[seq] = (id: id, mine: !dp && row['owner'] == myId);
    final time = DateTime.fromMillisecondsSinceEpoch(
      ((row['created_at'] as num?)?.toInt() ?? 0) * 1000,
      isUtc: true,
    );
    final message = Message(
      id: id,
      role: dp ? MessageRole.assistant : MessageRole.user,
      parts: [TextPart(text)],
      source: MessageSource(dp ? 'assistant' : 'user', {
        'rpcId': row['request_id'] ?? id,
      }),
    );
    transcript.apply(
      dp
          ? AssistantMessageEvent(
              seq,
              time,
              const {},
              turn: seq,
              step: 1,
              message: message,
            )
          : UserMessageEvent(seq, time, const {}, message: message),
    );
  }
  final lines = <CoupleLine>[];
  for (final item in transcript.items) {
    if (item is UserChatItem) {
      final owner = owners[item.seq]!;
      lines.add(
        CoupleLine(
          owner.id,
          item.text,
          owner.mine ? '我' : '伴侣',
          owner.mine,
          false,
        ),
      );
    } else if (item is AssistantChatItem) {
      lines.add(CoupleLine(owners[item.seq]!.id, item.text, 'DP', false, true));
    }
  }
  return lines;
}
