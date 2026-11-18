import 'package:material_ui/material_ui.dart';

import '../data/catalog.dart';
import '../services/cloud_session.dart';
import '../services/personal_wallpaper.dart';
import 'cloud_chat.dart';
import 'cloud_records.dart';
import 'dp_game.dart';
import 'dp_module_chat.dart';
import 'modules.dart';
import 'reflections.dart';
import 'theme.dart';
import 'white_purple_tabs.dart';

class PairedShell extends StatefulWidget {
  const PairedShell({required this.session, super.key});
  final CloudSession session;

  @override
  State<PairedShell> createState() => _PairedShellState();
}

class _PairedShellState extends State<PairedShell> {
  CloudSession get session => widget.session;
  late final wallpaper = PersonalWallpaper.forAccount(
    endpoint: session.endpoint,
    userId: session.user['id'].toString(),
  )..load();
  int tab = 0;
  final visitedTabs = <int>{0};
  static const tabs = [
    ('聊天', Icons.chat_bubble_outline, Icons.chat_bubble),
    ('功能', Icons.grid_view_outlined, Icons.grid_view_rounded),
    ('日常', Icons.calendar_today_outlined, Icons.event),
    ('我的', Icons.person_outline, Icons.person),
  ];

  @override
  void dispose() {
    wallpaper.dispose();
    super.dispose();
  }

  void push(Widget page) {
    FocusManager.instance.primaryFocus?.unfocus();
    Navigator.of(context).push<void>(MaterialPageRoute(builder: (_) => page));
  }

  void editBackground() => openWallpaperEditor(context, wallpaper);

  Widget chat(String scope) => ListenableBuilder(
    listenable: wallpaper,
    builder: (_, _) {
      final photo = wallpaper.photo;
      return Stack(
        fit: StackFit.expand,
        children: [
          if (photo != null)
            Image.memory(photo, fit: BoxFit.cover, excludeFromSemantics: true),
          if (photo == null) const ColoredBox(color: purplePaper),
          CloudChat(
            session: session,
            scope: scope,
            hasBackground: photo != null,
            openRecords: () =>
                push(CloudRecords(session: session, shared: scope == 'shared')),
            openPlan: scope == 'shared'
                ? (id) =>
                      push(CloudModuleDetail(session: session, moduleId: id))
                : null,
          ),
        ],
      );
    },
  );

  void privateChat() => push(
    Scaffold(
      appBar: AppBar(centerTitle: true, title: const Text('我和 DP')),
      body: SafeArea(top: false, child: chat('private')),
    ),
  );

  void module(ModuleId id) {
    if (cloudModules.containsKey(id.name)) {
      push(CloudModuleScreen(session: session, id: id));
      return;
    }
    final page = switch (id) {
      ModuleId.game => DpGameScreen(session: session),
      ModuleId.album => CloudAlbumScreen(session: session),
      ModuleId.talk => Reflections(session: session),
      ModuleId.universe => const UniverseScreen(previewOnly: true),
      _ => Scaffold(
        appBar: AppBar(title: Text(catalog[id]!.name)),
        body: const Center(child: Text('待开放')),
      ),
    };
    push(page);
  }

  Future<void> account() async {
    final leave = await askCloud(
      context,
      '当前账号 ${session.user['name'] ?? ''}',
      '已配对。退出后，此设备需要重新登录。',
      '退出登录',
    );
    if (!leave || !mounted) return;
    try {
      await session.logout();
    } catch (_) {
      if (!mounted) return;
      if (await askCloud(
        context,
        '暂时无法在服务端退出',
        '仅清除此设备的会话？服务端会话仍会按有效期失效。',
        '清除本机登录',
      )) {
        await session.forgetDevice();
      }
    }
  }

  void select(int value) {
    FocusManager.instance.primaryFocus?.unfocus();
    if (tab == value) return;
    setState(() {
      tab = value;
      visitedTabs.add(value);
    });
  }

  @override
  Widget build(BuildContext context) {
    final typing = MediaQuery.viewInsetsOf(context).bottom > 0;
    return PopScope(
      canPop: tab == 0,
      onPopInvokedWithResult: (didPop, _) {
        if (!didPop && tab != 0) select(0);
      },
      child: Scaffold(
        appBar: AppBar(
          centerTitle: true,
          toolbarHeight: 54,
          title: Text(tab == 0 ? '我们仨' : tabs[tab].$1),
          actions: tab == 0
              ? [
                  IconButton(
                    key: const Key('change-wallpaper'),
                    tooltip: '换背景',
                    onPressed: editBackground,
                    icon: const Icon(Icons.photo_library_outlined, size: 20),
                  ),
                  Padding(
                    padding: const EdgeInsets.only(right: 8),
                    child: TextButton.icon(
                      key: const Key('open-private'),
                      onPressed: privateChat,
                      icon: const Icon(Icons.lock_outline, size: 15),
                      label: const Text('私聊'),
                      style: TextButton.styleFrom(
                        visualDensity: VisualDensity.compact,
                        foregroundColor: pine,
                      ),
                    ),
                  ),
                ]
              : null,
          bottom: const PreferredSize(
            preferredSize: Size.fromHeight(1),
            child: Divider(height: 1, thickness: 1, color: edge),
          ),
        ),
        body: SafeArea(
          top: false,
          bottom: typing,
          child: Column(
            children: [
              if (session.connectionError case final error?)
                CloudFeedback(
                  message: '同步暂时中断：$error',
                  onRetry: () async {
                    try {
                      await session.refresh();
                    } catch (_) {
                      // refresh updates connectionError for the next retry.
                    }
                  },
                ),
              Expanded(
                child: IndexedStack(
                  index: tab,
                  children: [
                    chat('shared'),
                    if (visitedTabs.contains(1))
                      FeaturesTab(
                        session: session,
                        openModule: module,
                        openPrivateChat: privateChat,
                      )
                    else
                      const SizedBox.shrink(),
                    if (visitedTabs.contains(2))
                      DailyTab(session: session, openModule: module)
                    else
                      const SizedBox.shrink(),
                    if (visitedTabs.contains(3))
                      MineTab(
                        session: session,
                        openPrivateChat: privateChat,
                        editBackground: editBackground,
                        onAccount: account,
                      )
                    else
                      const SizedBox.shrink(),
                  ],
                ),
              ),
            ],
          ),
        ),
        bottomNavigationBar: typing
            ? null
            : DecoratedBox(
                decoration: const BoxDecoration(
                  color: paper,
                  border: Border(top: BorderSide(color: edge)),
                ),
                child: SafeArea(
                  top: false,
                  child: Row(
                    children: [
                      for (final (index, item) in tabs.indexed)
                        Expanded(
                          child: Semantics(
                            selected: index == tab,
                            button: true,
                            child: InkWell(
                              key: ValueKey('tab-$index'),
                              onTap: () => select(index),
                              child: ConstrainedBox(
                                constraints: const BoxConstraints(
                                  minHeight: 52,
                                ),
                                child: Padding(
                                  padding: const EdgeInsets.symmetric(
                                    vertical: 5,
                                  ),
                                  child: Column(
                                    mainAxisSize: MainAxisSize.min,
                                    mainAxisAlignment: MainAxisAlignment.center,
                                    children: [
                                      Icon(
                                        index == tab ? item.$3 : item.$2,
                                        size: 21,
                                        color: index == tab ? pine : quiet,
                                      ),
                                      const SizedBox(height: 2),
                                      Text(
                                        item.$1,
                                        style: TextStyle(
                                          fontSize: 11,
                                          color: index == tab ? pine : quiet,
                                          fontWeight: index == tab
                                              ? FontWeight.w700
                                              : FontWeight.w500,
                                        ),
                                      ),
                                    ],
                                  ),
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
