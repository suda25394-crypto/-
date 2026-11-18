part of 'cloud_chat.dart';

class LoginScreen extends StatefulWidget {
  const LoginScreen({required this.session, required this.onDemo, super.key});
  final CloudSession session;
  final VoidCallback onDemo;
  @override
  State<LoginScreen> createState() => _LoginScreenState();
}

class _LoginScreenState extends State<LoginScreen> {
  late final _base = TextEditingController(text: widget.session.endpoint);
  final _email = TextEditingController();
  final _password = TextEditingController();
  final _form = GlobalKey<FormState>();
  bool _busy = false;
  String? _error;
  Future<void> _submit() async {
    if (_busy || !_form.currentState!.validate()) return;
    FocusManager.instance.primaryFocus?.unfocus();
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      await widget.session.login(_base.text, _email.text, _password.text);
    } catch (e) {
      if (mounted) setState(() => _error = e.toString());
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  void dispose() {
    _base.dispose();
    _email.dispose();
    _password.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => Scaffold(
    backgroundColor: Colors.white,
    appBar: AppBar(title: const Text('双生宇宙')),
    body: SafeArea(
      child: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 540),
          child: ListView(
            shrinkWrap: true,
            padding: const EdgeInsets.fromLTRB(24, 22, 24, 20),
            children: [
              const Text(
                '登录私人空间',
                style: TextStyle(
                  fontSize: 28,
                  fontWeight: FontWeight.w600,
                  color: _chatInk,
                ),
              ),
              const Padding(
                padding: EdgeInsets.symmetric(vertical: 14),
                child: Text('用你自己的账号进入「我们仨」。双方分别登录，各自拥有独立私聊。'),
              ),
              Form(
                key: _form,
                child: Column(
                  children: [
                    TextFormField(
                      key: const Key('service-url'),
                      controller: _base,
                      autocorrect: false,
                      keyboardType: TextInputType.url,
                      enabled: !_busy,
                      decoration: const InputDecoration(
                        labelText: 'Muse 提供的产品服务地址',
                        hintText: 'https://…/couple',
                      ),
                      validator: (v) {
                        try {
                          serviceUri(v ?? '');
                          return null;
                        } catch (e) {
                          return e.toString();
                        }
                      },
                    ),
                    const SizedBox(height: 12),
                    TextFormField(
                      key: const Key('account-email'),
                      controller: _email,
                      autocorrect: false,
                      keyboardType: TextInputType.emailAddress,
                      enabled: !_busy,
                      autofillHints: const [AutofillHints.username],
                      decoration: const InputDecoration(labelText: '账号邮箱'),
                      validator: (v) =>
                          (v ?? '').trim().isEmpty ? '请输入邮箱' : null,
                    ),
                    const SizedBox(height: 12),
                    TextFormField(
                      key: const Key('account-password'),
                      controller: _password,
                      obscureText: true,
                      enableSuggestions: false,
                      autocorrect: false,
                      enabled: !_busy,
                      autofillHints: const [AutofillHints.password],
                      onFieldSubmitted: (_) => _submit(),
                      decoration: const InputDecoration(labelText: '密码'),
                      validator: (v) => (v ?? '').isEmpty ? '请输入密码' : null,
                    ),
                  ],
                ),
              ),
              if (_error != null)
                Padding(
                  padding: const EdgeInsets.only(top: 12),
                  child: Semantics(
                    liveRegion: true,
                    child: Text(
                      _error!,
                      style: TextStyle(
                        color: Theme.of(context).colorScheme.error,
                      ),
                    ),
                  ),
                ),
              const SizedBox(height: 16),
              FilledButton(
                onPressed: _busy ? null : _submit,
                child: Text(_busy ? '正在连接…' : '登录'),
              ),
              TextButton(
                onPressed: _busy ? null : widget.onDemo,
                child: const Text('体验本机演示'),
              ),
            ],
          ),
        ),
      ),
    ),
  );
}
