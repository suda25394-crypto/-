import 'package:material_ui/material_ui.dart';

import 'app.dart';
import 'services/cloud_session.dart';
import 'services/demo_store.dart';
import 'ui/cloud_chat.dart';
import 'ui/theme.dart';

class CoupleClient extends StatefulWidget {
  const CoupleClient({this.session, super.key});
  final CloudSession? session;
  @override
  State<CoupleClient> createState() => _CoupleClientState();
}

class _CoupleClientState extends State<CoupleClient>
    with WidgetsBindingObserver {
  late final session = widget.session ?? CloudSession();
  DemoStore? demo;
  bool loading = true;
  String? initError;
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    restore();
  }

  Future<void> restore() async {
    if (mounted) {
      setState(() {
        loading = true;
        initError = null;
      });
    }
    try {
      await session.restore();
    } catch (e) {
      initError = e.toString();
    } finally {
      if (mounted) setState(() => loading = false);
    }
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    final active = state == AppLifecycleState.resumed && demo == null;
    session.setPolling(active);
    if (active && session.signedIn) {
      session.refresh().catchError((_) {});
    }
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    if (widget.session == null) session.dispose();
    demo?.dispose();
    super.dispose();
  }

  void startDemo() {
    if (session.signedIn) return;
    setState(() => demo = DemoStore());
  }

  void endDemo() {
    final old = demo;
    setState(() => demo = null);
    WidgetsBinding.instance.addPostFrameCallback((_) {
      old?.dispose();
    });
  }

  @override
  Widget build(BuildContext context) => ListenableBuilder(
    listenable: session,
    builder: (c, _) {
      final online = session.signedIn && session.state.isNotEmpty;
      final routeMode = demo != null
          ? 'demo'
          : online
          ? 'account-${session.endpoint}-${session.user['id']}'
          : 'login';
      Widget page;
      if (loading) {
        page = const Scaffold(body: Center(child: CircularProgressIndicator()));
      } else if (demo != null) {
        page = AppShell(exitDemo: endDemo);
      } else if (online && session.paired) {
        page = AppShell(session: session);
      } else if (session.signedIn || initError != null) {
        page = Scaffold(
          appBar: AppBar(title: const Text('连接私人空间')),
          body: Padding(
            padding: const EdgeInsets.all(20),
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Text(
                  session.connectionError ??
                      initError ??
                      '账号尚未完成配对，请由 Muse 核对账号与共同频道。',
                ),
                FilledButton(onPressed: restore, child: const Text('重试连接')),
                TextButton(
                  onPressed: () async {
                    try {
                      await session.logout();
                    } catch (_) {
                      await session.forgetDevice();
                    }
                    if (mounted) setState(() => initError = null);
                  },
                  child: const Text('返回登录'),
                ),
              ],
            ),
          ),
        );
      } else {
        page = LoginScreen(session: session, onDemo: startDemo);
      }
      return MaterialApp(
        key: ValueKey(routeMode),
        title: '双生宇宙',
        theme: coupleTheme(),
        debugShowCheckedModeBanner: false,
        builder: (_, child) =>
            demo != null ? DemoScope(store: demo!, child: child!) : child!,
        home: page,
      );
    },
  );
}
