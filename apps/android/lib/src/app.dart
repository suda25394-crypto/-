import 'ui/daily_life.dart';

import 'package:material_ui/material_ui.dart';

import 'data/catalog.dart';
import 'services/cloud_session.dart';
import 'ui/cloud_chat.dart';
import 'ui/cloud_records.dart';
import 'ui/cloud_profiles.dart';
import 'services/demo_store.dart';
import 'ui/common_space.dart';
import 'ui/director.dart';
import 'ui/dp_game.dart';
import 'ui/home.dart';
import 'ui/modules.dart';
import 'ui/profiles.dart';
import 'ui/theme.dart';

class CoupleApp extends StatefulWidget {
  const CoupleApp({super.key});

  @override
  State<CoupleApp> createState() => _CoupleAppState();
}

class _CoupleAppState extends State<CoupleApp> {
  final store = DemoStore();

  @override
  void dispose() {
    store.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => MaterialApp(
    title: '两个人',
    theme: coupleTheme(),
    debugShowCheckedModeBanner: false,
    builder: (_, child) => DemoScope(store: store, child: child!),
    home: const AppShell(),
  );
}

class AppShell extends StatefulWidget {
  const AppShell({this.session, this.exitDemo, super.key});
  final CloudSession? session;
  final VoidCallback? exitDemo;

  @override
  State<AppShell> createState() => _AppShellState();
}

class _AppShellState extends State<AppShell> {
  int tab = 0;
  List<ModuleId> suggestions = initialSuggestions;

  void openRecords(bool shared) => Navigator.push(
    context,
    MaterialPageRoute(
      builder: (_) => CloudRecords(session: widget.session!, shared: shared),
    ),
  );
  void openCloudModule(ModuleId id) {
    final s = widget.session!;
    if (cloudModules.containsKey(id.name)) {
      Navigator.push(
        context,
        MaterialPageRoute(
          builder: (_) => CloudModuleScreen(session: s, id: id),
        ),
      );
    } else if (id == ModuleId.game) {
      Navigator.push(
        context,
        MaterialPageRoute(builder: (_) => DpGameScreen(session: s)),
      );
    } else if (id == ModuleId.universe) {
      Navigator.push(
        context,
        MaterialPageRoute(
          builder: (_) => const UniverseScreen(previewOnly: true),
        ),
      );
    } else {
      Navigator.push(
        context,
        MaterialPageRoute(
          builder: (_) => Scaffold(
            appBar: AppBar(title: Text(catalog[id]!.name)),
            body: const Padding(
              padding: EdgeInsets.all(22),
              child: Text('这个模块的联机功能尚未开放。可从登录页选择本机演示体验交互。'),
            ),
          ),
        ),
      );
    }
  }

  Future<void> account() async {
    final s = widget.session;
    if (s == null) {
      widget.exitDemo?.call();
      return;
    }
    final leave = await askCloud(
      context,
      '当前账号 ${s.user['name'] ?? ''}',
      s.paired ? '已配对 · 退出将清除这台设备上的会话。' : '请由 Muse 核对账号和共同频道成员。',
      '退出登录',
    );
    if (!leave || !mounted) return;
    try {
      await s.logout();
    } catch (e) {
      if (!mounted) return;
      if (await askCloud(
        context,
        '暂时无法在服务端退出',
        '仅清除此设备的会话？服务端会话仍会按有效期失效。',
        '清除本机登录',
      )) {
        await s.forgetDevice();
      }
    }
  }

  void openDirector() {
    if (widget.session case final s?) {
      Navigator.push(
        context,
        MaterialPageRoute(
          builder: (_) => Scaffold(
            appBar: AppBar(title: const Text('私人对话')),
            body: CloudChat(
              session: s,
              scope: 'private',
              openRecords: () => openRecords(false),
            ),
          ),
        ),
      );
      return;
    }
    Navigator.of(context).push<void>(
      MaterialPageRoute(
        settings: const RouteSettings(name: '/ai'),
        builder: (_) => DirectorScreen(
          onPlan: (plan) {
            setState(() => suggestions = plan.modules);
          },
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final s = widget.session;
    final onlineTitles = <ModuleId, String>{};
    if (s != null) {
      for (final m in s.rows('modules')) {
        final id = ModuleId.values
            .where((e) => e.name == m['module'])
            .firstOrNull;
        if (id != null) {
          onlineTitles.putIfAbsent(id, () => m['title'].toString());
        }
      }
    }
    return Scaffold(
      appBar: AppBar(
        toolbarHeight: 62,
        titleSpacing: 20,
        title: const Row(
          children: [
            SizedBox(
              width: 26,
              height: 29,
              child: CustomPaint(painter: _PrintMarkPainter()),
            ),
            SizedBox(width: 10),
            Text(
              '两个人',
              style: TextStyle(
                fontFamily: 'serif',
                fontSize: 29,
                color: ink,
                height: 1,
                fontWeight: FontWeight.w700,
                letterSpacing: -1.2,
              ),
            ),
          ],
        ),
        actions: [
          if (s == null && widget.exitDemo == null)
            const Padding(
              padding: EdgeInsets.only(right: 20),
              child: Text('本地演示', style: editionMeta),
            )
          else
            ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 160),
              child: TextButton.icon(
                onPressed: account,
                icon: Icon(
                  s == null ? Icons.logout : Icons.account_circle_outlined,
                  size: 17,
                ),
                label: Text(
                  s == null
                      ? '退出本机演示'
                      : (s.state['mode'] == 'fixture'
                            ? '合成联调 · ${s.user['name']}'
                            : '配对空间 · ${s.user['name'] ?? '账号'}'),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
              ),
            ),
        ],
        bottom: const PreferredSize(
          preferredSize: Size.fromHeight(1),
          child: Padding(
            padding: EdgeInsets.symmetric(horizontal: 20),
            child: Divider(color: ink, height: 1, thickness: 1),
          ),
        ),
      ),
      body: Column(
        children: [
          if (s?.connectionError != null)
            CloudFeedback(
              message: '同步暂时中断：${s!.connectionError}',
              onRetry: () async {
                try {
                  await s.refresh();
                } catch (_) {}
              },
            ),
          Expanded(
            child: IndexedStack(
              index: tab,
              children: [
                HomeScreen(
                  today: s == null ? null : DailyLifeHome(session: s),
                  suggestions: s == null
                      ? suggestions
                      : onlineTitles.keys.take(3).toList(),
                  summaries: s == null ? null : onlineTitles,
                  openModule: s == null
                      ? (id) => showModule(context, id)
                      : openCloudModule,
                  openDirector: openDirector,
                ),
                s == null
                    ? const CatalogScreen()
                    : CatalogScreen(
                        openModule: openCloudModule,
                        moduleFor: (id) {
                          final count = s
                              .rows('modules')
                              .where((m) => m['module'] == id.name)
                              .length;
                          return CoupleModule(
                            id,
                            catalog[id]!.name,
                            cloudModules.containsKey(id.name)
                                ? '双方可见 · $count 条共同记录'
                                : id == ModuleId.universe
                                ? '场景预览'
                                : id == ModuleId.game
                                ? '从共同回忆出题，轮流猜一猜'
                                : '联机功能待开放',
                            const [],
                          );
                        },
                      ),
                s == null
                    ? const CommonSpaceScreen()
                    : CloudChat(
                        session: s,
                        scope: 'shared',
                        openRecords: () => openRecords(true),
                      ),
                s == null
                    ? const ProfilesScreen()
                    : CloudProfilesScreen(
                        session: s,
                        openPrivateChat: openDirector,
                      ),
              ],
            ),
          ),
        ],
      ),
      bottomNavigationBar: DecoratedBox(
        decoration: const BoxDecoration(
          color: warmSurface,
          border: Border(top: BorderSide(color: edge)),
        ),
        child: SafeArea(
          top: false,
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 8),
            child: Row(
              children: [
                for (final (index, entry) in const [
                  ('首页', Icons.view_day_outlined, Icons.view_day),
                  ('功能', Icons.sort, Icons.sort),
                  ('共同', Icons.forum_outlined, Icons.forum),
                  ('档案', Icons.book_outlined, Icons.book),
                ].indexed)
                  Expanded(
                    child: Semantics(
                      selected: tab == index,
                      button: true,
                      child: InkWell(
                        onTap: () => setState(() => tab = index),
                        child: Padding(
                          padding: const EdgeInsets.symmetric(vertical: 6),
                          child: Column(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Icon(
                                tab == index ? entry.$3 : entry.$2,
                                color: tab == index ? pine : quiet,
                                size: 20,
                              ),
                              const SizedBox(height: 3),
                              Text(
                                entry.$1,
                                style: TextStyle(
                                  fontSize: 12,
                                  color: tab == index ? ink : quiet,
                                  fontWeight: tab == index
                                      ? FontWeight.w700
                                      : FontWeight.w400,
                                ),
                              ),
                              const SizedBox(height: 3),
                              Container(
                                width: 17,
                                height: 2,
                                color: tab == index
                                    ? amber
                                    : Colors.transparent,
                              ),
                            ],
                          ),
                        ),
                      ),
                    ),
                  ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

// Two leaves share a spine; the open edge also reads at toolbar size.
class _PrintMarkPainter extends CustomPainter {
  const _PrintMarkPainter();
  @override
  void paint(Canvas canvas, Size size) {
    canvas.scale(size.width / 26, size.height / 29);
    canvas.drawPath(
      Path()
        ..moveTo(0, 8)
        ..lineTo(10, 2)
        ..lineTo(10, 22)
        ..lineTo(0, 28)
        ..close(),
      Paint()..color = pine,
    );
    canvas.drawPath(
      Path()
        ..moveTo(13, 3)
        ..lineTo(26, 0)
        ..lineTo(22, 20)
        ..lineTo(13, 23)
        ..close(),
      Paint()..color = amber,
    );
  }

  @override
  bool shouldRepaint(_PrintMarkPainter oldDelegate) => false;
}
