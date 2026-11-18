import 'package:flutter/widgets.dart';

import '../data/catalog.dart';
import 'demo_director.dart';

class SpaceMessage {
  const SpaceMessage(this.author, this.text, [this.modules = const []]);

  final String author;
  final String text;
  final List<ModuleId> modules;
}

class DemoStore extends ChangeNotifier {
  final _edits = <ModuleId, CoupleModule>{};
  final _messages = <SpaceMessage>[];
  List<SpaceMessage> get messages => List.unmodifiable(_messages);

  CoupleModule module(ModuleId id) => _edits[id] ?? catalog[id]!;

  void save(CoupleModule module) {
    _edits[module.id] = module;
    notifyListeners();
  }

  void post(int actor, String value) {
    final text = value.trim();
    if (text.isEmpty) return;
    _messages.add(SpaceMessage(demoProfiles[actor].name, text));
    if (text.toLowerCase().contains('@ai')) {
      final request = text
          .replaceAll(RegExp('@AI', caseSensitive: false), '')
          .trim();
      final plan = const DemoDirector().suggest(request);
      if (plan != null) {
        _messages.add(SpaceMessage('AI · 本地规则', plan.summary, plan.modules));
      }
    }
    notifyListeners();
  }
}

class DemoScope extends InheritedNotifier<DemoStore> {
  const DemoScope({required DemoStore store, required super.child, super.key})
    : super(notifier: store);

  static DemoStore of(BuildContext context) =>
      context.dependOnInheritedWidgetOfExactType<DemoScope>()!.notifier!;
}
