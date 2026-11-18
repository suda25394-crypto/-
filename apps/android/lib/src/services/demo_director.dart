import '../data/catalog.dart';

class DemoPlan {
  const DemoPlan(this.summary, this.modules, {this.budget});

  final String summary;
  final List<ModuleId> modules;
  final String? budget;
}

// A local director for preview only. It never calls the deployed backend.
class DemoDirector {
  const DemoDirector();

  DemoPlan? suggest(String value) {
    final input = value.trim();
    if (input.isEmpty) return null;
    if (RegExp('小宇宙|星球|故事').hasMatch(input)) {
      return const DemoPlan('从一段共同经历开始，为小宇宙写下一章。', [
        ModuleId.universe,
        ModuleId.memory,
        ModuleId.wish,
      ]);
    }
    if (RegExp('生日|惊喜|礼物').hasMatch(input)) {
      return const DemoPlan('先整理想表达的心意，再选合适的时机。', [
        ModuleId.surprise,
        ModuleId.gift,
        ModuleId.calendar,
      ]);
    }
    if (RegExp('吃|美食|餐厅|晚饭').hasMatch(input)) {
      return const DemoPlan('先决定一起吃什么，再留一段不赶时间的安排。', [
        ModuleId.food,
        ModuleId.calendar,
        ModuleId.date,
      ]);
    }
    final budget = RegExp(r'(?:预算|不超过|最多)[为在约 ]*(\d{1,5})')
        .firstMatch(input)
        ?.group(1);
    return DemoPlan('把约会、相处时间和想做的事拆成三项。', [
      ModuleId.date,
      ModuleId.calendar,
      ModuleId.wish,
    ], budget: budget);
  }
}
