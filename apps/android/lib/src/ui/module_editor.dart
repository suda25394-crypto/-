import 'package:material_ui/material_ui.dart';

import '../data/catalog.dart';
import '../services/demo_store.dart';
import 'theme.dart';

void editModule(BuildContext context, CoupleModule module) {
  final store = DemoScope.of(context);
  Navigator.of(context).push<void>(
    MaterialPageRoute(
      builder: (_) => _ModuleEditor(module: module, store: store),
    ),
  );
}

class _ModuleEditor extends StatefulWidget {
  const _ModuleEditor({required this.module, required this.store});
  final CoupleModule module;
  final DemoStore store;

  @override
  State<_ModuleEditor> createState() => _ModuleEditorState();
}

class _ModuleEditorState extends State<_ModuleEditor> {
  final form = GlobalKey<FormState>();
  late final summary = TextEditingController(text: widget.module.summary);
  late final steps = TextEditingController(
    text: widget.module.steps.join('\n'),
  );

  @override
  void dispose() {
    summary.dispose();
    steps.dispose();
    super.dispose();
  }

  Future<void> confirm() async {
    if (!form.currentState!.validate()) return;
    FocusManager.instance.primaryFocus?.unfocus();
    final next = CoupleModule(
      widget.module.id,
      widget.module.name,
      summary.text.trim(),
      steps.text
          .split('\n')
          .map((line) => line.trim())
          .where((line) => line.isNotEmpty)
          .toList(),
    );
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        scrollable: true,
        backgroundColor: warmSurface,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(6)),
        title: const Text('确认保存到演示？'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Divider(color: ink, thickness: 1.5),
            Text(
              next.summary,
              style: const TextStyle(color: ink, fontSize: 18, height: 1.5),
            ),
            for (final (i, step) in next.steps.indexed)
              Padding(
                padding: const EdgeInsets.only(top: 9),
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text('${i + 1}.  ', style: const TextStyle(color: amber)),
                    Expanded(child: Text(step)),
                  ],
                ),
              ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('继续编辑'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text('确认保存'),
          ),
        ],
      ),
    );
    if (!mounted || confirmed != true) return;
    widget.store.save(next);
    Navigator.pop(context);
  }

  @override
  Widget build(BuildContext context) {
    const rule = UnderlineInputBorder(borderSide: BorderSide(color: edge));
    const focusRule = UnderlineInputBorder(
      borderSide: BorderSide(color: pine, width: 2),
    );
    return Scaffold(
      appBar: AppBar(title: Text('编辑 ${widget.module.name}')),
      body: SafeArea(
        top: false,
        child: Form(
          key: form,
          child: ListView(
            padding: const EdgeInsets.fromLTRB(23, 22, 23, 30),
            keyboardDismissBehavior: ScrollViewKeyboardDismissBehavior.onDrag,
            children: [
              const Text(
                '摘要',
                style: TextStyle(
                  color: quiet,
                  fontSize: 14,
                  letterSpacing: 1,
                  fontWeight: FontWeight.w600,
                ),
              ),
              TextFormField(
                key: const Key('module-summary-input'),
                controller: summary,
                maxLength: 120,
                minLines: 2,
                maxLines: 5,
                style: const TextStyle(
                  color: ink,
                  fontSize: 23,
                  height: 1.5,
                  fontWeight: FontWeight.w600,
                ),
                decoration: const InputDecoration(
                  hintText: '写一句摘要',
                  enabledBorder: rule,
                  focusedBorder: focusRule,
                  filled: false,
                  contentPadding: EdgeInsets.symmetric(vertical: 8),
                ),
                validator: (value) =>
                    value == null || value.trim().isEmpty ? '请输入一句摘要' : null,
              ),
              const SizedBox(height: 22),
              const Text(
                '步骤 · 每行一项',
                style: TextStyle(
                  color: quiet,
                  fontSize: 14,
                  letterSpacing: .5,
                  fontWeight: FontWeight.w600,
                ),
              ),
              TextFormField(
                controller: steps,
                minLines: 4,
                maxLines: 10,
                maxLength: 500,
                style: const TextStyle(color: ink, fontSize: 17, height: 1.7),
                decoration: const InputDecoration(
                  hintText: '写下第一项',
                  enabledBorder: rule,
                  focusedBorder: focusRule,
                  filled: false,
                  contentPadding: EdgeInsets.symmetric(vertical: 10),
                ),
              ),
              const SizedBox(height: 14),
              const Text(
                '确认后保存到本次本地演示。',
                style: TextStyle(color: quiet, fontSize: 13),
              ),
              const SizedBox(height: 12),
              FilledButton.icon(
                style: FilledButton.styleFrom(
                  minimumSize: const Size(0, 50),
                  shape: const RoundedRectangleBorder(),
                ),
                onPressed: confirm,
                iconAlignment: IconAlignment.end,
                icon: const Icon(Icons.arrow_forward, size: 19),
                label: const Text('预览修改'),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
