import 'package:material_ui/material_ui.dart';

import '../data/catalog.dart';
import '../services/demo_store.dart';
import 'module_editor.dart';
import 'module_mark.dart';
import 'theme.dart';

void showModule(BuildContext context, ModuleId id) {
  Navigator.of(context).push<void>(
    MaterialPageRoute(
      settings: RouteSettings(
        name: id == ModuleId.universe ? '/universe' : '/modules/${id.name}',
      ),
      builder: (_) => id == ModuleId.universe
          ? const UniverseScreen()
          : _ModuleScreen(id: id),
    ),
  );
}

class CatalogScreen extends StatelessWidget {
  const CatalogScreen({this.moduleFor, this.openModule, super.key});
  final CoupleModule Function(ModuleId)? moduleFor;
  final ValueChanged<ModuleId>? openModule;

  static const sections = [
    (
      '一起安排',
      [ModuleId.date, ModuleId.calendar, ModuleId.food, ModuleId.travel],
    ),
    ('留住日常', [ModuleId.memory, ModuleId.album, ModuleId.wish]),
    ('给彼此', [ModuleId.surprise, ModuleId.gift, ModuleId.talk, ModuleId.game]),
  ];

  @override
  Widget build(BuildContext context) {
    final lookup = moduleFor ?? DemoScope.of(context).module;
    void open(ModuleId type) {
      if (openModule != null) {
        openModule!(type);
      } else {
        showModule(context, type);
      }
    }

    final world = lookup(ModuleId.universe);
    return ListView(
      padding: const EdgeInsets.fromLTRB(22, 8, 22, 32),
      children: [
        Row(
          crossAxisAlignment: CrossAxisAlignment.end,
          children: [
            const Expanded(child: Text('功能目录', style: _title)),
            Text('${catalog.length} 项', style: _label),
          ],
        ),
        const SizedBox(height: 18),
        Material(
          color: pine,
          child: InkWell(
            key: const Key('module-universe'),
            onTap: () => open(ModuleId.universe),
            child: Row(
              children: [
                SizedBox(
                  width: 101,
                  height: 105,
                  child: Image.asset(
                    'assets/observatory.webp',
                    fit: BoxFit.cover,
                    alignment: const Alignment(-0.45, -0.3),
                    excludeFromSemantics: true,
                  ),
                ),
                const SizedBox(width: 14),
                Expanded(
                  child: Padding(
                    padding: const EdgeInsets.symmetric(vertical: 11),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          world.name,
                          style: const TextStyle(
                            color: warmSurface,
                            fontSize: 22,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                        const SizedBox(height: 5),
                        Text(
                          world.summary,
                          maxLines: 2,
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(
                            color: mist,
                            fontSize: 13,
                            height: 1.5,
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
                const Padding(
                  padding: EdgeInsets.symmetric(horizontal: 9),
                  child: Icon(Icons.north_east, color: warmSurface, size: 18),
                ),
              ],
            ),
          ),
        ),
        for (final (label, ids) in sections) ...[
          const SizedBox(height: 26),
          DecoratedBox(
            decoration: const BoxDecoration(
              border: Border(top: BorderSide(color: ink, width: 1.4)),
            ),
            child: Padding(
              padding: const EdgeInsets.only(top: 9, bottom: 9),
              child: Row(
                children: [
                  Expanded(
                    child: Text(
                      label,
                      style: const TextStyle(
                        fontWeight: FontWeight.w700,
                        fontSize: 19,
                        color: ink,
                        letterSpacing: .8,
                      ),
                    ),
                  ),
                  Text('${ids.length} 项', style: _label),
                ],
              ),
            ),
          ),
          for (final id in ids)
            _CatalogEntry(module: lookup(id), onOpen: () => open(id)),
        ],
      ],
    );
  }
}

const _title = TextStyle(
  fontSize: 34,
  fontWeight: FontWeight.w700,
  color: ink,
  letterSpacing: -1.3,
  height: 1.25,
);
const _label = TextStyle(
  color: quiet,
  fontSize: 13,
  letterSpacing: .7,
  height: 1.45,
);

class _CatalogEntry extends StatelessWidget {
  const _CatalogEntry({required this.module, required this.onOpen});
  final CoupleModule module;
  final VoidCallback onOpen;

  @override
  Widget build(BuildContext context) => Material(
    color: Colors.transparent,
    child: InkWell(
      key: Key('module-${module.id.name}'),
      onTap: onOpen,
      child: Container(
        constraints: const BoxConstraints(minHeight: 58),
        decoration: const BoxDecoration(
          border: Border(bottom: BorderSide(color: edge)),
        ),
        padding: const EdgeInsets.symmetric(vertical: 9),
        child: Row(
          children: [
            ModuleMark(module.id, size: 30),
            const SizedBox(width: 10),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    module.name,
                    style: const TextStyle(
                      color: ink,
                      fontSize: 16,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                  const SizedBox(height: 2),
                  Text(
                    module.summary,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(color: quiet, fontSize: 13),
                  ),
                ],
              ),
            ),
            const SizedBox(width: 10),
            const Icon(Icons.arrow_forward, color: quiet, size: 17),
          ],
        ),
      ),
    ),
  );
}

class _ModuleScreen extends StatelessWidget {
  const _ModuleScreen({required this.id});
  final ModuleId id;

  @override
  Widget build(BuildContext context) {
    final module = DemoScope.of(context).module(id);
    final timeline = [
      ModuleId.date,
      ModuleId.calendar,
      ModuleId.travel,
    ].contains(id);
    final section = CatalogScreen.sections
        .firstWhere((entry) => entry.$2.contains(id))
        .$1;
    return Scaffold(
      appBar: AppBar(
        title: Text(module.name),
        actions: [
          TextButton.icon(
            onPressed: () => editModule(context, module),
            icon: const Icon(Icons.edit_outlined, size: 16),
            label: const Text('编辑'),
          ),
        ],
      ),
      body: SafeArea(
        top: false,
        child: ListView(
          padding: const EdgeInsets.fromLTRB(23, 26, 23, 32),
          children: [
            Row(
              children: [
                SizedBox.square(
                  dimension: 34,
                  child: DecoratedBox(
                    decoration: BoxDecoration(border: Border.all(color: pine)),
                    child: ModuleMark(id, size: 30),
                  ),
                ),
                const SizedBox(width: 11),
                Text(section, style: _label),
              ],
            ),
            const SizedBox(height: 20),
            Text(
              module.summary,
              style: _title.copyWith(fontSize: 30, height: 1.42),
            ),
            const SizedBox(height: 27),
            const Divider(height: 1, thickness: 2, color: ink),
            Material(
              color: Colors.transparent,
              child: ExpansionTile(
                key: const Key('module-details'),
                tilePadding: EdgeInsets.zero,
                childrenPadding: EdgeInsets.zero,
                initiallyExpanded: true,
                shape: const Border(),
                collapsedShape: const Border(),
                title: Text(
                  timeline ? '安排' : '示例详情',
                  style: const TextStyle(
                    fontSize: 18,
                    color: ink,
                    fontWeight: FontWeight.w600,
                  ),
                ),
                children: [
                  if (module.steps.isEmpty)
                    const Align(
                      alignment: Alignment.centerLeft,
                      child: Padding(
                        padding: EdgeInsets.symmetric(vertical: 14),
                        child: Text('还没有步骤，可从右上角编辑。', style: _label),
                      ),
                    ),
                  for (final (i, item) in module.steps.indexed)
                    Container(
                      width: double.infinity,
                      padding: const EdgeInsets.symmetric(vertical: 17),
                      decoration: const BoxDecoration(
                        border: Border(top: BorderSide(color: edge)),
                      ),
                      child: Row(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          SizedBox(
                            width: 39,
                            child: Text(
                              '${i + 1}'.padLeft(2, '0'),
                              style: const TextStyle(
                                color: amber,
                                fontFamily: 'serif',
                                fontSize: 20,
                                height: 1.3,
                              ),
                            ),
                          ),
                          Expanded(
                            child: Text(
                              item,
                              style: const TextStyle(
                                color: ink,
                                fontSize: 16,
                                height: 1.6,
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class UniverseScreen extends StatefulWidget {
  const UniverseScreen({this.previewOnly = false, super.key});
  final bool previewOnly;
  @override
  State<UniverseScreen> createState() => _UniverseScreenState();
}

class _UniverseScreenState extends State<UniverseScreen> {
  int scene = 0;
  static const scenes = [
    ('相遇的草地', '沿微光小径走，为第一次相遇留下一句话。', Alignment(-.9, .72), 1.34),
    ('湖畔观察站', '点亮湖边的窗，为最近想一起完成的事留一盏灯。', Alignment(-.83, -.82), 1.32),
    ('回忆步道', '沿着水边走，选一段你们都想重新读的故事。', Alignment(.91, .45), 1.46),
  ];

  @override
  Widget build(BuildContext context) {
    final (name, note, anchor, zoom) = scenes[scene];
    final module = widget.previewOnly
        ? null
        : DemoScope.of(context).module(ModuleId.universe);
    final duration = MediaQuery.disableAnimationsOf(context)
        ? Duration.zero
        : const Duration(milliseconds: 360);
    return Scaffold(
      appBar: AppBar(
        title: const Text('小宇宙'),
        actions: [
          if (module != null)
            TextButton.icon(
              onPressed: () => editModule(context, module),
              icon: const Icon(Icons.edit_outlined, size: 16),
              label: const Text('编辑'),
            ),
        ],
      ),
      body: SafeArea(
        top: false,
        child: ListView(
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 4, 16, 0),
              child: ClipRect(
                child: GestureDetector(
                  onHorizontalDragEnd: (details) {
                    final speed = details.primaryVelocity ?? 0;
                    if (speed.abs() > 180) {
                      setState(
                        () => scene = (scene + (speed < 0 ? 1 : -1)).clamp(
                          0,
                          scenes.length - 1,
                        ),
                      );
                    }
                  },
                  child: AspectRatio(
                    aspectRatio: 1.20,
                    child: AnimatedContainer(
                      duration: duration,
                      curve: Curves.easeOutCubic,
                      transformAlignment: anchor,
                      transform: Matrix4.diagonal3Values(zoom, zoom, 1),
                      child: Image.asset(
                        'assets/observatory.webp',
                        fit: BoxFit.cover,
                        alignment: anchor,
                        semanticLabel: '小宇宙里的玻璃观察站与水边步道',
                      ),
                    ),
                  ),
                ),
              ),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(23, 19, 23, 32),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    crossAxisAlignment: CrossAxisAlignment.center,
                    children: [
                      Expanded(
                        child: Text(
                          name,
                          key: const Key('scene-title'),
                          style: _title.copyWith(fontSize: 28),
                        ),
                      ),
                      Text('${scene + 1} / ${scenes.length}', style: _label),
                    ],
                  ),
                  const SizedBox(height: 9),
                  Text(
                    note,
                    style: const TextStyle(
                      color: ink,
                      fontSize: 15,
                      height: 1.65,
                    ),
                  ),
                  const SizedBox(height: 16),
                  Wrap(
                    spacing: 6,
                    children: [
                      for (var i = 0; i < scenes.length; i++)
                        ChoiceChip(
                          label: Text(scenes[i].$1),
                          selected: scene == i,
                          showCheckmark: false,
                          onSelected: (_) => setState(() => scene = i),
                          shape: const RoundedRectangleBorder(),
                          selectedColor: pine,
                          backgroundColor: paper,
                          side: BorderSide(color: scene == i ? pine : edge),
                          labelStyle: TextStyle(
                            color: scene == i ? warmSurface : ink,
                            fontSize: 13,
                          ),
                          labelPadding: EdgeInsets.zero,
                        ),
                    ],
                  ),
                  const SizedBox(height: 18),
                  const Divider(color: ink, thickness: 1.5),
                  Text(
                    module?.summary ?? '场景预览 · 尚未开放云端互动',
                    style: const TextStyle(
                      color: ink,
                      fontSize: 18,
                      height: 1.6,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                  for (final step in (module?.steps ?? const <String>[]))
                    Padding(
                      padding: const EdgeInsets.only(top: 7),
                      child: Text(step, style: _label),
                    ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}
