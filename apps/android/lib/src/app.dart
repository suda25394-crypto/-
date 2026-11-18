import 'package:material_ui/material_ui.dart';

import 'data/catalog.dart';
import 'services/cloud_session.dart';
import 'ui/paired_shell.dart';
import 'services/demo_store.dart';
import 'ui/common_space.dart';
import 'ui/director.dart';
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
    title: '双生宇宙',
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

  void openDirector() {
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
    if (s != null) return PairedShell(session: s);
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
          if (widget.exitDemo == null)
            const Padding(
              padding: EdgeInsets.only(right: 20),
              child: Text('本地演示', style: editionMeta),
            )
          else
            ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 160),
              child: TextButton.icon(
                onPressed: widget.exitDemo,
                icon: const Icon(Icons.logout, size: 17),
                label: const Text(
                  '退出本机演示',
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
      body: IndexedStack(
        index: tab,
        children: [
          HomeScreen(
            suggestions: suggestions,
            openModule: (id) => showModule(context, id),
            openDirector: openDirector,
          ),
          const CatalogScreen(),
          const CommonSpaceScreen(),
          const ProfilesScreen(),
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
