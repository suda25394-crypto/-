import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_localizations/flutter_localizations.dart';

import '../ui/theme/accent.dart';
import '../ui/theme/app_theme.dart';
import 'couple_controller.dart';
import '../ui/chat/widgets/chat_card.dart';
import 'couple_transcript.dart';

part 'meeting_pages.dart';

const grape = Color(0xff8038a0);
const ink = Color(0xff2c2130);
const muted = Color(0xff675c69);

void main() {
  WidgetsFlutterBinding.ensureInitialized();
  runApp(const CouplePrototype());
}

class CouplePrototype extends StatefulWidget {
  const CouplePrototype({super.key, this.controller});
  final CoupleController? controller;

  @override
  State<CouplePrototype> createState() => _CouplePrototypeState();
}

class _CouplePrototypeState extends State<CouplePrototype>
    with WidgetsBindingObserver {
  late final controller = widget.controller ?? CoupleController();
  late final ThemeData theme;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    final dshTheme = buildLightTheme(
      accent: AppAccent.derive(grape, label: '葡萄紫'),
      glassBlur: false,
      glyphLocale: const Locale('zh', 'CN'),
    );
    theme = dshTheme.copyWith(
      scaffoldBackgroundColor: Colors.white,
      colorScheme: dshTheme.colorScheme.copyWith(
        primary: grape,
        onPrimary: Colors.white,
        surface: Colors.white,
        onSurface: ink,
      ),
      appBarTheme: dshTheme.appBarTheme.copyWith(
        backgroundColor: Colors.white,
        foregroundColor: ink,
        surfaceTintColor: Colors.transparent,
        centerTitle: false,
      ),
    );
    controller.restore();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    controller.setForeground(state == AppLifecycleState.resumed);
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    if (widget.controller == null) controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => MaterialApp(
    title: '双生宇宙 · 约会原型',
    debugShowCheckedModeBanner: false,
    theme: theme,
    locale: const Locale('zh', 'CN'),
    localizationsDelegates: GlobalMaterialLocalizations.delegates,
    supportedLocales: const [Locale('zh', 'CN')],
    home: ListenableBuilder(
      listenable: controller,
      builder: (context, _) {
        if (controller.loading) {
          return const Scaffold(
            body: Center(
              child: CircularProgressIndicator(semanticsLabel: '正在恢复账号'),
            ),
          );
        }
        if (!controller.signedIn) return _Login(controller: controller);
        return MeetingListPage(
          key: ValueKey((controller.endpoint, controller.userId)),
          controller: controller,
        );
      },
    ),
  );
}

const _sourcePage =
    'https://github.com/suda25394-crypto/-/releases/tag/dsh-couple-date-v0.1.0-test.1';

Future<void> showSourceInformation(BuildContext context) => showDialog<void>(
  context: context,
  builder: (dialog) => AlertDialog(
    scrollable: true,
    title: const Text('本版源码与许可'),
    content: const Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: [
        Text(
          '双生宇宙 · 约会原型基于 dsh-Go v1.2.0 开发，依 GNU AGPL-3.0 发布。下列发布页提供本版对应源码、许可文本与第三方声明。',
        ),
        SizedBox(height: 12),
        SelectableText(_sourcePage),
      ],
    ),
    actions: [
      TextButton(
        onPressed: () async {
          await Clipboard.setData(const ClipboardData(text: _sourcePage));
          if (dialog.mounted) Navigator.pop(dialog);
          if (context.mounted)
            ScaffoldMessenger.of(context)
                .showSnackBar(const SnackBar(content: Text('已复制源码与许可链接')));
        },
        child: const Text('复制链接'),
      ),
      TextButton(
        onPressed: () => Navigator.pop(dialog),
        child: const Text('关闭'),
      ),
    ],
  ),
);

class _Login extends StatefulWidget {
  const _Login({required this.controller});
  final CoupleController controller;
  @override
  State<_Login> createState() => _LoginState();
}

class _LoginState extends State<_Login> {
  final form = GlobalKey<FormState>();
  late final endpoint = TextEditingController(text: widget.controller.endpoint);
  final email = TextEditingController();
  final password = TextEditingController();
  bool obscure = true;

  @override
  void dispose() {
    endpoint.dispose();
    email.dispose();
    password.dispose();
    super.dispose();
  }

  Future<void> submit() async {
    if (widget.controller.busy || !(form.currentState?.validate() ?? false))
      return;
    FocusManager.instance.primaryFocus?.unfocus();
    await widget.controller.login(
      endpoint.text.trim(),
      email.text.trim(),
      password.text,
    );
  }

  @override
  Widget build(BuildContext context) {
    final controller = widget.controller;
    final textTheme = Theme.of(context).textTheme;
    return Scaffold(
      body: SafeArea(
        child: Center(
          child: SingleChildScrollView(
            padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 32),
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 430),
              child: Form(
                key: form,
                child: AutofillGroup(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Align(
                        alignment: Alignment.centerLeft,
                        child: Icon(
                          Icons.calendar_month_rounded,
                          size: 38,
                          color: grape,
                        ),
                      ),
                      const SizedBox(height: 16),
                      Text(
                        '双生宇宙',
                        style: textTheme.headlineMedium?.copyWith(
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                      const SizedBox(height: 8),
                      Text(
                        '登录现有账号，和 DP 一起调整共同日程。',
                        style: textTheme.bodyLarge?.copyWith(color: muted),
                      ),
                      const SizedBox(height: 28),
                      TextFormField(
                        key: const Key('login-server'),
                        controller: endpoint,
                        keyboardType: TextInputType.url,
                        textInputAction: TextInputAction.next,
                        autocorrect: false,
                        decoration: const InputDecoration(
                          labelText: '服务地址',
                          hintText: 'https://…',
                        ),
                        validator: (v) {
                          final base = Uri.tryParse((v ?? '').trim());
                          if (base == null ||
                              !base.hasAuthority ||
                              base.scheme != 'https') {
                            return '请输入现版使用的 HTTPS 产品服务地址';
                          }
                          return null;
                        },
                      ),
                      const SizedBox(height: 14),
                      TextFormField(
                        key: const Key('login-email'),
                        controller: email,
                        keyboardType: TextInputType.emailAddress,
                        textInputAction: TextInputAction.next,
                        autofillHints: const [AutofillHints.username],
                        autocorrect: false,
                        decoration: const InputDecoration(labelText: '账号邮箱'),
                        validator: (v) =>
                            (v ?? '').trim().isEmpty ? '请输入账号邮箱' : null,
                      ),
                      const SizedBox(height: 14),
                      TextFormField(
                        key: const Key('login-password'),
                        controller: password,
                        obscureText: obscure,
                        autocorrect: false,
                        enableSuggestions: false,
                        autofillHints: const [AutofillHints.password],
                        onFieldSubmitted: (_) => submit(),
                        decoration: InputDecoration(
                          labelText: '密码',
                          suffixIcon: IconButton(
                            tooltip: obscure ? '显示密码' : '隐藏密码',
                            onPressed: () => setState(() => obscure = !obscure),
                            icon: Icon(
                              obscure
                                  ? Icons.visibility_outlined
                                  : Icons.visibility_off_outlined,
                            ),
                          ),
                        ),
                        validator: (v) => (v ?? '').isEmpty ? '请输入密码' : null,
                      ),
                      if (controller.error case final error?) ...[
                        const SizedBox(height: 14),
                        ErrorMessage(error),
                      ],
                      const SizedBox(height: 22),
                      FilledButton(
                        key: const Key('login-submit'),
                        onPressed: controller.busy ? null : submit,
                        child: Text(controller.busy ? '正在登录…' : '登录'),
                      ),
                      TextButton(
                        onPressed: () => showSourceInformation(context),
                        child: const Text('本版源码与许可'),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}
