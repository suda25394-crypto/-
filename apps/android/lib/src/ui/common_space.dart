import 'package:material_ui/material_ui.dart';

import '../data/catalog.dart';
import '../services/demo_store.dart';
import 'modules.dart';
import 'theme.dart';

class CommonSpaceScreen extends StatefulWidget {
  const CommonSpaceScreen({super.key});

  @override
  State<CommonSpaceScreen> createState() => _CommonSpaceScreenState();
}

class _CommonSpaceScreenState extends State<CommonSpaceScreen> {
  final input = TextEditingController();
  final composerFocus = FocusNode();
  final scroll = ScrollController();
  int actor = 0;

  void mentionAi() {
    if (!input.text.toLowerCase().contains('@ai')) {
      final text = '@AI ${input.text.characters.take(196)}';
      input.value = TextEditingValue(
        text: text,
        selection: TextSelection.collapsed(offset: text.length),
      );
    }
    composerFocus.requestFocus();
  }

  void send(DemoStore store) {
    if (input.text.trim().isEmpty) return;
    store.post(actor, input.text);
    input.clear();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted || !scroll.hasClients) return;
      final end = scroll.position.maxScrollExtent;
      if (MediaQuery.disableAnimationsOf(context)) {
        scroll.jumpTo(end);
      } else {
        scroll.animateTo(
          end,
          duration: const Duration(milliseconds: 220),
          curve: Curves.easeOut,
        );
      }
    });
  }

  @override
  void dispose() {
    input.dispose();
    composerFocus.dispose();
    scroll.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final store = DemoScope.of(context);
    final messages = store.messages;
    return SafeArea(
      top: false,
      child: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 620),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Expanded(
                child: CustomScrollView(
                  controller: scroll,
                  keyboardDismissBehavior:
                      ScrollViewKeyboardDismissBehavior.onDrag,
                  slivers: [
                    SliverPadding(
                      padding: const EdgeInsets.fromLTRB(22, 14, 22, 12),
                      sliver: SliverToBoxAdapter(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.stretch,
                          children: [
                            const Divider(color: pine, thickness: 2, height: 2),
                            const SizedBox(height: 12),
                            Semantics(
                              header: true,
                              child: const Text(
                                '共同空间',
                                style: TextStyle(
                                  fontFamily: 'serif',
                                  color: ink,
                                  fontWeight: FontWeight.w700,
                                  fontSize: 33,
                                  height: 1.25,
                                ),
                              ),
                            ),
                            const SizedBox(height: 5),
                            const Text(
                              '两人可见 · 消息留在当前演示会话',
                              style: TextStyle(color: quiet, fontSize: 13),
                            ),
                            const SizedBox(height: 10),
                            Wrap(
                              crossAxisAlignment: WrapCrossAlignment.center,
                              spacing: 8,
                              children: [
                                const Text(
                                  '发言身份',
                                  style: TextStyle(color: quiet, fontSize: 13),
                                ),
                                for (
                                  var index = 0;
                                  index < demoProfiles.length;
                                  index++
                                )
                                  ChoiceChip(
                                    label: Text(demoProfiles[index].name),
                                    shape: const RoundedRectangleBorder(
                                      borderRadius: BorderRadius.all(
                                        Radius.circular(4),
                                      ),
                                    ),
                                    showCheckmark: true,
                                    selected: actor == index,
                                    onSelected: (_) =>
                                        setState(() => actor = index),
                                  ),
                              ],
                            ),
                          ],
                        ),
                      ),
                    ),
                    if (messages.isEmpty)
                      SliverFillRemaining(
                        hasScrollBody: false,
                        child: Padding(
                          padding: const EdgeInsets.fromLTRB(28, 2, 28, 22),
                          child: Column(
                            mainAxisAlignment: MainAxisAlignment.center,
                            children: [
                              const ExcludeSemantics(
                                child: SizedBox(
                                  width: 222,
                                  height: 128,
                                  child: CustomPaint(painter: _LetterPainter()),
                                ),
                              ),
                              const SizedBox(height: 12),
                              Text(
                                '可以先给对方留一句话，\n或用 @AI 讨论一个计划。',
                                textAlign: TextAlign.center,
                                style: Theme.of(context).textTheme.bodyMedium
                                    ?.copyWith(color: quiet, height: 1.6),
                              ),
                            ],
                          ),
                        ),
                      )
                    else
                      SliverPadding(
                        padding: const EdgeInsets.fromLTRB(22, 2, 22, 8),
                        sliver: SliverList.builder(
                          itemCount: messages.length,
                          itemBuilder: (_, index) => _LetterEntry(
                            message: messages[index],
                            mine:
                                messages[index].author ==
                                demoProfiles[actor].name,
                          ),
                        ),
                      ),
                  ],
                ),
              ),
              DecoratedBox(
                decoration: const BoxDecoration(
                  color: warmSurface,
                  border: Border(top: BorderSide(color: pine)),
                ),
                child: Padding(
                  padding: const EdgeInsets.fromLTRB(10, 5, 8, 5),
                  child: Row(
                    crossAxisAlignment: CrossAxisAlignment.center,
                    children: [
                      TextButton(
                        onPressed: mentionAi,
                        style: TextButton.styleFrom(
                          foregroundColor: amber,
                          minimumSize: const Size(48, 48),
                          padding: const EdgeInsets.symmetric(horizontal: 7),
                        ),
                        child: const Text(
                          '@AI',
                          style: TextStyle(fontWeight: FontWeight.w700),
                        ),
                      ),
                      const SizedBox(width: 5),
                      Expanded(
                        child: TextField(
                          key: const Key('shared-message-input'),
                          controller: input,
                          focusNode: composerFocus,
                          decoration: const InputDecoration(
                            hintText: '写一条共同消息',
                            isDense: true,
                            filled: false,
                            contentPadding: EdgeInsets.symmetric(vertical: 14),
                            border: InputBorder.none,
                            enabledBorder: InputBorder.none,
                            focusedBorder: UnderlineInputBorder(
                              borderSide: BorderSide(color: pine),
                            ),
                          ),
                          maxLength: 200,
                          maxLines: 2,
                          minLines: 1,
                          buildCounter: (
                            _, {
                            required currentLength,
                            required isFocused,
                            maxLength,
                          }) => null,
                          textInputAction: TextInputAction.send,
                          onSubmitted: (_) => send(store),
                        ),
                      ),
                      const SizedBox(width: 5),
                      ValueListenableBuilder<TextEditingValue>(
                        valueListenable: input,
                        builder: (_, value, _) => FilledButton(
                          onPressed: value.text.trim().isEmpty
                              ? null
                              : () => send(store),
                          style: FilledButton.styleFrom(
                            minimumSize: const Size(48, 48),
                            shape: const RoundedRectangleBorder(
                              borderRadius: BorderRadius.all(
                                Radius.circular(5),
                              ),
                            ),
                          ),
                          child: const Text('发送'),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _LetterEntry extends StatelessWidget {
  const _LetterEntry({required this.message, required this.mine});

  final SpaceMessage message;
  final bool mine;

  @override
  Widget build(BuildContext context) {
    final store = DemoScope.of(context);
    final ai = message.modules.isNotEmpty;
    final accent = ai ? amber : pine;
    return Padding(
      padding: EdgeInsets.only(
        left: mine ? 32 : 0,
        right: mine ? 0 : 22,
        bottom: 13,
      ),
      child: Container(
        padding: const EdgeInsets.fromLTRB(12, 8, 12, 10),
        decoration: BoxDecoration(
          color: mine ? mist : warmSurface,
          border: Border(
            left: BorderSide(color: accent, width: ai ? 3 : 1),
          ),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              message.author,
              style: TextStyle(
                color: accent,
                fontSize: 12,
                fontWeight: FontWeight.w700,
              ),
            ),
            const SizedBox(height: 4),
            SelectableText(
              message.text,
              style: const TextStyle(color: ink, fontSize: 16, height: 1.55),
            ),
            if (message.modules.isNotEmpty)
              Wrap(
                spacing: 4,
                children: [
                  for (final id in message.modules)
                    TextButton.icon(
                      onPressed: () => showModule(context, id),
                      icon: const Icon(Icons.arrow_outward, size: 14),
                      label: Text(store.module(id).name),
                    ),
                ],
              ),
          ],
        ),
      ),
    );
  }
}

/// A half-open envelope, a letter, and the two overlapping postmarks.
class _LetterPainter extends CustomPainter {
  const _LetterPainter();

  @override
  void paint(Canvas canvas, Size size) {
    canvas.save();
    canvas.scale(size.width / 222, size.height / 128);
    canvas.translate(109, 70);
    canvas.rotate(-0.09);
    final thin = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1.15
      ..color = pine;
    final flap = Path()
      ..moveTo(-76, -21)
      ..lineTo(-15, -58)
      ..quadraticBezierTo(-11, -61, -6, -57)
      ..lineTo(66, -21)
      ..close();
    canvas.drawPath(flap, Paint()..color = mist);
    canvas.drawPath(flap, thin);
    final letter = Rect.fromLTWH(-46, -49, 96, 75);
    canvas.drawRect(letter, Paint()..color = warmSurface);
    canvas.drawRect(letter, thin);
    for (var index = 0; index < 3; index++) {
      final y = -34.0 + 7 * index;
      canvas.drawLine(
        Offset(-34, y),
        Offset(index == 2 ? 2 : 25, y),
        Paint()
          ..color = edge
          ..strokeWidth = 1.4,
      );
    }
    final body = Path()
      ..moveTo(-76, -21)
      ..lineTo(-9, 12)
      ..lineTo(66, -21)
      ..lineTo(66, 42)
      ..lineTo(-76, 42)
      ..close();
    canvas.drawPath(body, Paint()..color = paper);
    canvas.drawPath(body, thin);
    canvas.drawLine(const Offset(-76, 42), const Offset(-27, 4), thin);
    canvas.drawLine(const Offset(66, 42), const Offset(12, 3), thin);
    final seal = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1.4
      ..color = amber;
    canvas.drawCircle(const Offset(49, 16), 10, seal);
    canvas.drawCircle(const Offset(52, 14), 8, seal);
    for (var i = 0; i < 3; i++) {
      final y = 10.0 + i * 4;
      canvas.drawPath(
        Path()
          ..moveTo(58, y)
          ..cubicTo(67, y - 4, 71, y + 4, 79, y)
          ..quadraticBezierTo(84, y - 3, 90, y),
        seal..strokeWidth = .85,
      );
    }
    canvas.restore();
  }

  @override
  bool shouldRepaint(_LetterPainter oldDelegate) => false;
}
