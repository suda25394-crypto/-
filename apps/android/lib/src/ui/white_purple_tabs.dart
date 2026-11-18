import 'package:material_ui/material_ui.dart';

import '../data/catalog.dart';
import '../services/cloud_session.dart';
import '../data/pair_activity.dart';
import 'cloud_profiles.dart';
import 'daily_life.dart';
import 'dp_module_chat.dart';
import 'ginkgo_art.dart';
import 'pair_activities.dart';
import 'theme.dart' show pine, mist;

export 'wallpaper_editor.dart' show openWallpaperEditor;

const _ink = Color(0xff242328),
    _muted = Color(0xff64626b),
    _purple = pine,
    _pale = mist,
    _rule = Color(0xffe9e8ec);
const _icons = <ModuleId, IconData>{
  ModuleId.date: Icons.confirmation_number_outlined,
  ModuleId.wish: Icons.auto_awesome_outlined,
  ModuleId.calendar: Icons.calendar_month_outlined,
  ModuleId.memory: Icons.menu_book_outlined,
  ModuleId.universe: Icons.public_outlined,
  ModuleId.album: Icons.photo_library_outlined,
  ModuleId.game: Icons.sports_esports_outlined,
  ModuleId.talk: Icons.forum_outlined,
  ModuleId.food: Icons.restaurant_outlined,
  ModuleId.travel: Icons.explore_outlined,
  ModuleId.surprise: Icons.celebration_outlined,
  ModuleId.gift: Icons.card_giftcard_outlined,
};
String? _status(ModuleId id) => switch (id) {
  ModuleId.universe => '演示',
  ModuleId.food ||
  ModuleId.travel ||
  ModuleId.surprise ||
  ModuleId.gift => '待开放',
  _ => null,
};

void _details(BuildContext context, CloudSession session, String id) =>
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => CloudModuleDetail(session: session, moduleId: id),
      ),
    );
void _profiles(
  BuildContext context,
  CloudSession session,
  VoidCallback openPrivateChat,
) => Navigator.push(
  context,
  MaterialPageRoute(
    builder: (page) => Scaffold(
      appBar: AppBar(title: const Text('个人档案')),
      body: ListenableBuilder(
        listenable: session,
        builder: (_, _) => CloudProfilesScreen(
          session: session,
          openPrivateChat: () {
            Navigator.pop(page);
            openPrivateChat();
          },
        ),
      ),
    ),
  ),
);

class _Heading extends StatelessWidget {
  const _Heading(this.text, [this.note]);
  final String text;
  final String? note;
  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.fromLTRB(0, 22, 0, 9),
    child: Row(
      children: [
        Expanded(
          child: Text(
            text,
            style: const TextStyle(
              fontSize: 16,
              fontWeight: FontWeight.w700,
              color: _ink,
            ),
          ),
        ),
        if (note != null)
          Text(note!, style: const TextStyle(fontSize: 12, color: _muted)),
      ],
    ),
  );
}

class _RowLink extends StatelessWidget {
  const _RowLink(this.title, this.subtitle, this.icon, this.onTap);
  final String title, subtitle;
  final IconData icon;
  final VoidCallback onTap;
  @override
  Widget build(BuildContext context) => Material(
    color: Colors.white,
    child: InkWell(
      onTap: onTap,
      child: Container(
        constraints: const BoxConstraints(minHeight: 62),
        padding: const EdgeInsets.symmetric(vertical: 10, horizontal: 2),
        decoration: const BoxDecoration(
          border: Border(bottom: BorderSide(color: _rule)),
        ),
        child: Row(
          children: [
            Icon(icon, size: 22, color: _ink),
            const SizedBox(width: 14),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    title,
                    style: const TextStyle(
                      color: _ink,
                      fontSize: 15,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                  if (subtitle.isNotEmpty)
                    Text(
                      subtitle,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                        color: _muted,
                        fontSize: 12,
                        height: 1.45,
                      ),
                    ),
                ],
              ),
            ),
            const SizedBox(width: 8),
            const Icon(Icons.chevron_right, size: 18, color: _muted),
          ],
        ),
      ),
    ),
  );
}

class _PlanTicket extends StatelessWidget {
  const _PlanTicket(this.session, this.openModule);
  final CloudSession session;
  final ValueChanged<ModuleId> openModule;
  @override
  Widget build(BuildContext context) {
    final records = session.rows('modules');
    final today = DateTime.now()
        .toUtc()
        .add(const Duration(hours: 8))
        .toIso8601String()
        .substring(0, 10);
    final journeys = session.rows('journeys');
    // R2 sorts journeys by date/time. Only upcoming planned records belong in the next outing.
    final upcoming = journeys
        .where(
          (j) =>
              j['stage'] == 'planned' &&
              (j['day'] as String? ?? '').compareTo(today) >= 0,
        )
        .firstOrNull;
    final unscheduled = records
        .where(
          (r) =>
              (r['module'] == 'date' || r['module'] == 'calendar') &&
              !journeys.any(
                (j) =>
                    j['plan'] == r['id'] &&
                    (j['stage'] != 'planned' ||
                        (j['day'] as String? ?? '').isNotEmpty),
              ),
        )
        .firstOrNull;
    final title = (upcoming?['title'] ?? unscheduled?['title']) as String?;
    final id = (upcoming?['plan'] ?? unscheduled?['id']) as String?;
    final when = [
      upcoming?['day'],
      upcoming?['clock'],
      upcoming?['place'],
    ].whereType<String>().where((s) => s.isNotEmpty).join(' · ');
    return Material(
      color: Colors.white,
      shape: RoundedRectangleBorder(
        side: const BorderSide(color: _rule),
        borderRadius: BorderRadius.circular(10),
      ),
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: () => id == null
            ? openModule(ModuleId.calendar)
            : _details(context, session, id),
        child: Column(
          children: [
            const SizedBox(
              height: 147,
              width: double.infinity,
              child: CustomPaint(painter: GinkgoArt()),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(14, 8, 14, 14),
              child: Row(
                children: [
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        const Text(
                          '共同日程',
                          style: TextStyle(
                            color: _purple,
                            fontSize: 12,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                        Text(
                          title ?? '还没有约好的计划',
                          maxLines: 2,
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(
                            color: _ink,
                            fontSize: 19,
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                        Text(
                          when.isNotEmpty
                              ? when
                              : id == null
                              ? '一起安排下一次见面'
                              : '时间地点待补充',
                          style: const TextStyle(color: _muted, fontSize: 13),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(width: 8),
                  const Icon(Icons.north_east, size: 20, color: _purple),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class FeaturesTab extends StatelessWidget {
  const FeaturesTab({
    super.key,
    required this.session,
    required this.openModule,
    required this.openPrivateChat,
  });
  final CloudSession session;
  final ValueChanged<ModuleId> openModule;
  final VoidCallback openPrivateChat;
  @override
  Widget build(BuildContext context) => ListenableBuilder(
    listenable: session,
    builder: (_, _) => ListView(
      key: const PageStorageKey('features-list'),
      padding: const EdgeInsets.fromLTRB(16, 8, 16, 24),
      children: [
        _PlanTicket(session, openModule),
        const _Heading('两人互动'),
        Wrap(
          spacing: 8,
          runSpacing: 4,
          children: [
            for (final kind in PairActivity.values)
              OutlinedButton.icon(
                icon: Icon(
                  kind == PairActivity.notebook
                      ? Icons.edit_note_outlined
                      : Icons.auto_awesome_outlined,
                ),
                label: Text(kind.label),
                onPressed: () => Navigator.push(
                  context,
                  MaterialPageRoute(
                    builder: (_) =>
                        PairActivitiesPage(session: session, kind: kind),
                  ),
                ),
              ),
          ],
        ),
        const _Heading('全部功能', '12 项'),
        LayoutBuilder(
          builder: (context, box) {
            final width = box.maxWidth / 4;
            return Wrap(
              children: [
                for (final e in _icons.entries)
                  SizedBox(
                    width: width,
                    child: Material(
                      color: Colors.white,
                      child: InkWell(
                        key: Key('module-${e.key.name}'),
                        onTap: () => openModule(e.key),
                        child: Padding(
                          padding: const EdgeInsets.fromLTRB(2, 9, 2, 8),
                          child: Column(
                            children: [
                              Icon(e.value, size: 23, color: _ink),
                              const SizedBox(height: 5),
                              Text(
                                catalog[e.key]!.name,
                                textAlign: TextAlign.center,
                                style: const TextStyle(
                                  fontSize: 13,
                                  color: _ink,
                                ),
                              ),
                              SizedBox(
                                height: MediaQuery.textScalerOf(context)
                                    .scale(14),
                                child: _status(e.key) == null
                                    ? null
                                    : Text(
                                        _status(e.key)!,
                                        style: const TextStyle(
                                          color: _muted,
                                          fontSize: 10,
                                        ),
                                      ),
                              ),
                            ],
                          ),
                        ),
                      ),
                    ),
                  ),
              ],
            );
          },
        ),
        const _Heading('档案'),
        _RowLink(
          '个人档案',
          '看看 DP 从聊天里记住了什么',
          Icons.person_outline,
          () => _profiles(context, session, openPrivateChat),
        ),
      ],
    ),
  );
}

class DailyTab extends StatelessWidget {
  const DailyTab({super.key, required this.session, required this.openModule});
  final CloudSession session;
  final ValueChanged<ModuleId> openModule;
  @override
  Widget build(BuildContext context) => ListenableBuilder(
    listenable: session,
    builder: (_, _) {
      final records = session.rows('modules');
      final memories = records.where((r) => r['module'] == 'memory').take(2);
      String count(String module) =>
          '${records.where((r) => r['module'] == module).length} 条共同记录';
      return ListView(
        key: const PageStorageKey('daily-list'),
        padding: const EdgeInsets.fromLTRB(16, 0, 16, 24),
        children: [
          const _Heading('下一次约会'),
          _PlanTicket(session, openModule),
          DailyLifeHome(session: session),
          const _Heading('一起安排'),
          _RowLink(
            '共同日程',
            count('calendar'),
            Icons.calendar_month_outlined,
            () => openModule(ModuleId.calendar),
          ),
          _RowLink(
            '共同心愿',
            count('wish'),
            Icons.auto_awesome_outlined,
            () => openModule(ModuleId.wish),
          ),
          const _Heading('最近的共同记忆'),
          if (memories.isEmpty)
            const Text('还没有共同回忆。', style: TextStyle(color: _muted)),
          for (final item in memories)
            _RowLink(
              item['title'] as String,
              item['body'] as String? ?? '',
              Icons.menu_book_outlined,
              () => _details(context, session, item['id'] as String),
            ),
          TextButton(
            onPressed: () => openModule(ModuleId.memory),
            child: const Text('查看全部回忆'),
          ),
        ],
      );
    },
  );
}

class MineTab extends StatelessWidget {
  const MineTab({
    super.key,
    required this.session,
    required this.openPrivateChat,
    required this.editBackground,
    required this.onAccount,
  });
  final CloudSession session;
  final VoidCallback openPrivateChat, editBackground, onAccount;
  @override
  Widget build(BuildContext context) => ListView(
    key: const PageStorageKey('mine-list'),
    padding: const EdgeInsets.fromLTRB(16, 15, 16, 24),
    children: [
      Row(
        children: [
          const CircleAvatar(
            radius: 23,
            backgroundColor: _pale,
            child: Icon(Icons.person_outline, color: _purple),
          ),
          const SizedBox(width: 14),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text(
                  '我的空间',
                  style: TextStyle(
                    fontSize: 22,
                    fontWeight: FontWeight.w700,
                    color: _ink,
                  ),
                ),
                Text(
                  '${session.user['name'] ?? '我'} · 个人档案与设置',
                  style: const TextStyle(color: _muted, fontSize: 13),
                ),
              ],
            ),
          ),
        ],
      ),
      const SizedBox(height: 18),
      _RowLink(
        '个人档案',
        '查看、修改偏好和可见范围',
        Icons.badge_outlined,
        () => _profiles(context, session, openPrivateChat),
      ),
      _RowLink(
        '让 DP 了解我',
        '在私聊中开启、暂停或结束了解',
        Icons.auto_awesome_outlined,
        openPrivateChat,
      ),
      const _Heading('外观'),
      _RowLink(
        '换背景',
        '从相册选择自己的图片',
        Icons.photo_library_outlined,
        editBackground,
      ),
      const _Heading('账号'),
      _RowLink(
        '登录账号',
        '查看配对状态或退出登录',
        Icons.manage_accounts_outlined,
        onAccount,
      ),
    ],
  );
}

class CloudAlbumScreen extends StatelessWidget {
  const CloudAlbumScreen({super.key, required this.session});
  final CloudSession session;
  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(title: const Text('情侣相册')),
    body: ListenableBuilder(
      listenable: session,
      builder: (_, _) {
        final photos = session
            .rows('memory_photos')
            .map((e) => e['memory'])
            .toSet();
        final memories = session
            .rows('modules')
            .where((r) => r['module'] == 'memory' && photos.contains(r['id']));
        return ListView(
          padding: const EdgeInsets.all(16),
          children: [
            const _Heading('共同回忆里的照片'),
            if (memories.isEmpty) const Text('还没有照片。可以在计划成行后，将照片加入共同回忆。'),
            for (final m in memories)
              _RowLink(
                m['title'] as String,
                '查看这段回忆与照片',
                Icons.photo_outlined,
                () => _details(context, session, m['id'] as String),
              ),
          ],
        );
      },
    ),
  );
}
