import 'package:flutter/foundation.dart' show listEquals;
import 'package:material_ui/material_ui.dart';

import '../data/catalog.dart';
import '../services/demo_store.dart';
import 'theme.dart';

/// A short, hand-paged edition. Each spread is backed by a real module.
class HomeScreen extends StatefulWidget {
  const HomeScreen({
    required this.suggestions,
    required this.openModule,
    required this.openDirector,
    this.summaries,
    super.key,
  });

  final List<ModuleId> suggestions;
  final ValueChanged<ModuleId> openModule;
  final VoidCallback openDirector;
  final Map<ModuleId, String>? summaries;

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> {
  final _pages = PageController();
  int _selected = 0;

  @override
  void didUpdateWidget(HomeScreen oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (!listEquals(oldWidget.suggestions, widget.suggestions)) {
      _selected = 0;
      if (_pages.hasClients) _pages.jumpToPage(0);
    }
  }

  @override
  void dispose() {
    _pages.dispose();
    super.dispose();
  }

  void _select(int index) {
    if (MediaQuery.disableAnimationsOf(context)) {
      _pages.jumpToPage(index);
    } else {
      _pages.animateToPage(
        index,
        duration: const Duration(milliseconds: 320),
        curve: Curves.easeOutCubic,
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final ids = widget.suggestions.take(3).toList();
    final store = widget.summaries == null ? DemoScope.of(context) : null;
    final reducedMotion = MediaQuery.disableAnimationsOf(context);
    final now = DateTime.now();
    const weekdays = ['一', '二', '三', '四', '五', '六', '日'];
    final date = '${now.month} 月 ${now.day} 日 · 星期${weekdays[now.weekday - 1]}';
    return LayoutBuilder(
      builder: (context, constraints) {
        final width = constraints.maxWidth.clamp(0.0, 540.0);
        final height = (constraints.maxHeight - 333).clamp(
          195.0,
          width * .91 + 35,
        );
        return Align(
          alignment: Alignment.topCenter,
          child: SizedBox(
            width: width,
            child: SingleChildScrollView(
              padding: const EdgeInsets.fromLTRB(20, 13, 20, 15),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Flexible(child: Text(date, style: editionMeta)),
                      if (ids.isNotEmpty)
                        Text(
                          '${(_selected + 1).toString().padLeft(2, '0')} / ${ids.length.toString().padLeft(2, '0')}',
                          style: editionFolio,
                        ),
                    ],
                  ),
                  if (ids.isEmpty) ...[
                    const SizedBox(height: 16),
                    const Text(
                      '今天想一起做什么？',
                      style: TextStyle(
                        fontSize: 29,
                        fontFamily: 'serif',
                        color: ink,
                      ),
                    ),
                    const SizedBox(height: 14),
                    AspectRatio(
                      aspectRatio: 1.5,
                      child: Image.asset(
                        'assets/covers/room.webp',
                        fit: BoxFit.cover,
                        excludeFromSemantics: true,
                      ),
                    ),
                    const Padding(
                      padding: EdgeInsets.symmetric(vertical: 15),
                      child: Text('在私聊中提出一个想法。确认后的计划会出现在共同模块里。'),
                    ),
                  ],
                  if (ids.isNotEmpty) ...[
                    const SizedBox(height: 10),
                    Align(
                      alignment: Alignment.centerLeft,
                      child: Semantics(
                        header: true,
                        child: Text(
                          widget.summaries?[ids[_selected]] ??
                              store!.module(ids[_selected]).summary,
                          maxLines: 2,
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(
                            color: ink,
                            fontFamily: 'serif',
                            fontWeight: FontWeight.w600,
                            height: 1.19,
                            fontSize: width < 380 ? 32 : 37,
                            letterSpacing: -1.4,
                          ),
                        ),
                      ),
                    ),
                    const SizedBox(height: 15),
                    SizedBox(
                      height: height,
                      child: PageView.builder(
                        key: const Key('edition-covers'),
                        controller: _pages,
                        itemCount: ids.length,
                        onPageChanged: (index) =>
                            setState(() => _selected = index),
                        itemBuilder: (context, index) {
                          final id = ids[index];
                          final name = catalog[id]!.name;
                          return Semantics(
                            button: true,
                            label: '打开$name',
                            child: Material(
                              color: mist,
                              child: InkWell(
                                key: ValueKey('cover-${id.name}'),
                                onTap: () => widget.openModule(id),
                                child: Stack(
                                  fit: StackFit.expand,
                                  children: [
                                    ExcludeSemantics(
                                      child: Image.asset(
                                        _asset(id),
                                        fit: BoxFit.cover,
                                      ),
                                    ),
                                    // A printed caption stays legible against every photograph.
                                    Positioned(
                                      right: 10,
                                      bottom: 10,
                                      child: ExcludeSemantics(
                                        child: DecoratedBox(
                                          decoration: const BoxDecoration(
                                            color: warmSurface,
                                          ),
                                          child: Padding(
                                            padding: const EdgeInsets.symmetric(
                                              horizontal: 11,
                                              vertical: 7,
                                            ),
                                            child: Row(
                                              mainAxisSize: MainAxisSize.min,
                                              children: [
                                                Text(
                                                  '打开$name',
                                                  style: const TextStyle(
                                                    color: ink,
                                                    fontSize: 13,
                                                    fontWeight: FontWeight.w600,
                                                  ),
                                                ),
                                                const SizedBox(width: 5),
                                                const Icon(
                                                  Icons.north_east,
                                                  size: 15,
                                                  color: ink,
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
                          );
                        },
                      ),
                    ),
                    Row(
                      children: [
                        const Padding(
                          padding: EdgeInsets.only(right: 10),
                          child: Text('AI 选页', style: editionMeta),
                        ),
                        for (var i = 0; i < ids.length; i++)
                          Expanded(
                            child: Semantics(
                              selected: i == _selected,
                              button: true,
                              child: InkWell(
                                onTap: () => _select(i),
                                child: ConstrainedBox(
                                  constraints: const BoxConstraints(
                                    minHeight: 52,
                                  ),
                                  child: Column(
                                    mainAxisSize: MainAxisSize.min,
                                    children: [
                                      AnimatedContainer(
                                        duration: Duration(
                                          milliseconds: reducedMotion ? 0 : 200,
                                        ),
                                        height: 3,
                                        color: i == _selected ? amber : edge,
                                      ),
                                      Padding(
                                        padding: const EdgeInsets.fromLTRB(
                                          2,
                                          11,
                                          2,
                                          8,
                                        ),
                                        child: Text(
                                          catalog[ids[i]]!.name,
                                          textAlign: TextAlign.center,
                                          style: TextStyle(
                                            fontSize: 13,
                                            fontWeight: i == _selected
                                                ? FontWeight.w700
                                                : FontWeight.w400,
                                            color: i == _selected ? ink : quiet,
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
                    ),
                    const SizedBox(height: 13),
                  ],
                  Material(
                    color: pine,
                    child: InkWell(
                      key: const Key('open-director'),
                      onTap: widget.openDirector,
                      child: const Padding(
                        padding: EdgeInsets.fromLTRB(16, 13, 16, 13),
                        child: Row(
                          children: [
                            Icon(
                              Icons.graphic_eq_rounded,
                              color: Color(0xFFFFC69E),
                              size: 28,
                            ),
                            SizedBox(width: 14),
                            Expanded(
                              child: Text(
                                '和 AI 聊聊',
                                style: TextStyle(
                                  color: warmSurface,
                                  fontSize: 20,
                                  fontWeight: FontWeight.w600,
                                ),
                              ),
                            ),
                            Icon(
                              Icons.arrow_forward,
                              color: warmSurface,
                              size: 24,
                            ),
                          ],
                        ),
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
        );
      },
    );
  }

  String _asset(ModuleId id) => switch (id) {
    ModuleId.memory ||
    ModuleId.album ||
    ModuleId.talk ||
    ModuleId.gift ||
    ModuleId.surprise => 'assets/covers/letter.webp',
    ModuleId.wish ||
    ModuleId.travel ||
    ModuleId.universe => 'assets/covers/coast.webp',
    _ => 'assets/covers/room.webp',
  };
}
