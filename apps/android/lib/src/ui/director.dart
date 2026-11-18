import 'package:material_ui/material_ui.dart';

import '../data/catalog.dart';
import '../services/demo_director.dart';
import '../services/demo_store.dart';
import 'module_mark.dart';
import 'modules.dart';
import 'theme.dart';

class DirectorScreen extends StatefulWidget {
  const DirectorScreen({required this.onPlan, super.key});
  final ValueChanged<DemoPlan> onPlan;

  @override
  State<DirectorScreen> createState() => _DirectorScreenState();
}

class _DirectorScreenState extends State<DirectorScreen> {
  final input = TextEditingController();
  final resultAnchor = GlobalKey();
  DemoPlan? plan;

  void submit() {
    final next = const DemoDirector().suggest(input.text);
    if (next == null) return;
    FocusManager.instance.primaryFocus?.unfocus();
    setState(() => plan = next);
    widget.onPlan(next);
    WidgetsBinding.instance.addPostFrameCallback((_) {
      final target = resultAnchor.currentContext;
      if (target != null) {
        Scrollable.ensureVisible(
          target,
          duration: MediaQuery.disableAnimationsOf(target)
              ? Duration.zero
              : const Duration(milliseconds: 280),
          curve: Curves.easeOutCubic,
        );
      }
    });
  }

  void usePrompt(String value) {
    input.value = TextEditingValue(
      text: value,
      selection: TextSelection.collapsed(offset: value.length),
    );
  }

  @override
  void dispose() {
    input.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final result = plan;
    return Scaffold(
      appBar: AppBar(title: const Text('和 AI 聊聊')),
      body: SafeArea(
        top: false,
        child: Align(
          alignment: Alignment.topCenter,
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 600),
            child: SingleChildScrollView(
              keyboardDismissBehavior: ScrollViewKeyboardDismissBehavior.onDrag,
              padding: const EdgeInsets.fromLTRB(22, 16, 22, 32),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Row(
                    children: [
                      const SizedBox(
                        width: 28,
                        child: Divider(color: amber, thickness: 2),
                      ),
                      const SizedBox(width: 9),
                      const Flexible(
                        child: Text(
                          '本地规则演示',
                          style: TextStyle(color: quiet, fontSize: 13),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 12),
                  Semantics(
                    header: true,
                    child: const Text(
                      '你的想法',
                      style: TextStyle(
                        fontSize: 36,
                        height: 1.2,
                        fontFamily: 'serif',
                        fontWeight: FontWeight.w700,
                        color: ink,
                      ),
                    ),
                  ),
                  const SizedBox(height: 18),
                  Material(
                    color: warmSurface,
                    shape: const Border(
                      top: BorderSide(color: pine, width: 2),
                      bottom: BorderSide(color: edge),
                    ),
                    child: Padding(
                      padding: const EdgeInsets.fromLTRB(16, 14, 16, 10),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        children: [
                          TextField(
                            key: const Key('director-input'),
                            controller: input,
                            minLines: 3,
                            maxLines: 5,
                            maxLength: 200,
                            style: const TextStyle(
                              color: ink,
                              fontSize: 18,
                              height: 1.6,
                            ),
                            decoration: const InputDecoration(
                              hintText: '想和对方一起做什么？',
                              filled: false,
                              border: InputBorder.none,
                              enabledBorder: InputBorder.none,
                              focusedBorder: UnderlineInputBorder(
                                borderSide: BorderSide(color: pine),
                              ),
                              contentPadding: EdgeInsets.zero,
                            ),
                          ),
                          const Divider(height: 1, color: edge),
                          Padding(
                            padding: const EdgeInsets.only(top: 6),
                            child: Wrap(
                              spacing: 12,
                              children: [
                                TextButton(
                                  onPressed: () =>
                                      usePrompt('周末想一起出去，预算 200 元'),
                                  child: const Text('周末出去走走'),
                                ),
                                TextButton(
                                  onPressed: () => usePrompt('今晚想找餐厅吃饭'),
                                  child: const Text('安排晚餐'),
                                ),
                              ],
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                  const SizedBox(height: 12),
                  Align(
                    alignment: Alignment.centerRight,
                    child: ValueListenableBuilder<TextEditingValue>(
                      valueListenable: input,
                      builder: (_, value, _) => FilledButton.icon(
                        onPressed: value.text.trim().isEmpty ? null : submit,
                        style: FilledButton.styleFrom(
                          minimumSize: const Size(132, 48),
                          shape: const RoundedRectangleBorder(
                            borderRadius: BorderRadius.all(Radius.circular(4)),
                          ),
                        ),
                        label: const Text('查看建议'),
                        icon: const Icon(Icons.arrow_forward, size: 17),
                        iconAlignment: IconAlignment.end,
                      ),
                    ),
                  ),
                  if (result != null) ...[
                    const SizedBox(height: 28),
                    Container(
                      key: resultAnchor,
                      decoration: const BoxDecoration(
                        border: Border(top: BorderSide(color: ink, width: 1.4)),
                      ),
                      padding: const EdgeInsets.only(top: 14),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        children: [
                          Semantics(
                            liveRegion: true,
                            header: true,
                            child: Text(
                              result.summary,
                              style: const TextStyle(
                                fontFamily: 'serif',
                                fontSize: 23,
                                fontWeight: FontWeight.w600,
                                height: 1.45,
                              ),
                            ),
                          ),
                          if (result.budget case final budget?)
                            Padding(
                              padding: const EdgeInsets.only(top: 8),
                              child: Text(
                                '预算上限 $budget 元 · 请核对实际花费',
                                style: const TextStyle(
                                  color: amber,
                                  fontWeight: FontWeight.w600,
                                ),
                              ),
                            ),
                          const SizedBox(height: 16),
                          for (final id in result.modules) _PlanLine(id),
                        ],
                      ),
                    ),
                  ],
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _PlanLine extends StatelessWidget {
  const _PlanLine(this.id);
  final ModuleId id;

  @override
  Widget build(BuildContext context) {
    final module = DemoScope.of(context).module(id);
    return Column(
      children: [
        const Divider(color: edge, height: 1),
        ListTile(
          contentPadding: const EdgeInsets.symmetric(vertical: 4),
          leading: Icon(moduleIcon(id), color: pine, size: 23),
          title: Text(
            module.name,
            style: const TextStyle(fontWeight: FontWeight.w700),
          ),
          subtitle: Text(module.summary, style: const TextStyle(color: quiet)),
          trailing: const Icon(Icons.arrow_outward, size: 18, color: pine),
          onTap: () => showModule(context, id),
        ),
      ],
    );
  }
}
