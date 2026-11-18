import 'package:material_ui/material_ui.dart';

import '../data/catalog.dart';
import 'theme.dart';

IconData moduleIcon(ModuleId id) => switch (id) {
  ModuleId.date => Icons.wb_sunny_outlined,
  ModuleId.surprise => Icons.auto_awesome_outlined,
  ModuleId.memory => Icons.history_edu_outlined,
  ModuleId.wish => Icons.diamond_outlined,
  ModuleId.universe => Icons.public_outlined,
  ModuleId.food => Icons.restaurant_outlined,
  ModuleId.calendar => Icons.calendar_today_outlined,
  ModuleId.talk => Icons.chat_bubble_outline,
  ModuleId.album => Icons.photo_library_outlined,
  ModuleId.game => Icons.extension_outlined,
  ModuleId.gift => Icons.card_giftcard_outlined,
  ModuleId.travel => Icons.explore_outlined,
};

class ModuleMark extends StatelessWidget {
  const ModuleMark(this.id, {this.size = 42, super.key});

  final ModuleId id;
  final double size;

  @override
  Widget build(BuildContext context) {
    final color = switch (id) {
      ModuleId.date ||
      ModuleId.surprise ||
      ModuleId.gift ||
      ModuleId.food => amber,
      _ => pine,
    };
    return SizedBox.square(
      dimension: size,
      child: Icon(moduleIcon(id), color: color, size: size * 0.61),
    );
  }
}
