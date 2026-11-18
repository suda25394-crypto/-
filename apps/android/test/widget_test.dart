import 'package:couple_app/src/app.dart';
import 'package:couple_app/src/data/catalog.dart';
import 'package:couple_app/src/services/demo_director.dart';
import 'package:couple_app/src/ui/modules.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';

void main() {
  test('director changes module groups and keeps a numeric budget', () {
    const director = DemoDirector();
    final weekend = director.suggest('周末想一起出去，预算 200 元')!;
    expect(weekend.modules, [ModuleId.date, ModuleId.calendar, ModuleId.wish]);
    expect(weekend.budget, '200');
    expect(director.suggest('今晚吃什么')!.modules.first, ModuleId.food);
    expect(director.suggest('   '), isNull);
  });

  testWidgets('all modules navigate and the universe changes scene', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(360, 800);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    await tester.pumpWidget(const CoupleApp());
    await tester.pumpAndSettle();
    await tester.tap(find.text('功能'));
    await tester.pumpAndSettle();

    final inDirectoryOrder = [
      ModuleId.universe,
      for (final section in CatalogScreen.sections) ...section.$2,
    ];
    expect(inDirectoryOrder, unorderedEquals(ModuleId.values));
    for (final id in inDirectoryOrder) {
      final tile = find.byKey(Key('module-${id.name}'));
      await tester.scrollUntilVisible(tile, 105);
      await tester.tap(tile);
      await tester.pumpAndSettle();
      expect(find.widgetWithText(AppBar, catalog[id]!.name), findsOneWidget);
      if (id == ModuleId.universe) {
        await tester.tap(find.widgetWithText(ChoiceChip, '湖畔观察站'));
        await tester.pumpAndSettle();
        expect(
          tester.widget<Text>(find.byKey(const Key('scene-title'))).data,
          '湖畔观察站',
        );
      } else {
        expect(find.byKey(const Key('module-details')), findsOneWidget);
      }
      expect(tester.takeException(), isNull);
      await tester.pageBack();
      await tester.pumpAndSettle();
    }
  });

  testWidgets('director results update the orbit, profiles switch', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(390, 844);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    await tester.pumpWidget(const CoupleApp());
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('open-director')));
    await tester.pumpAndSettle();
    await tester.enterText(find.byKey(const Key('director-input')), '今晚想找餐厅吃饭');
    await tester.pump();
    await tester.ensureVisible(find.text('查看建议'));
    await tester.tap(find.text('查看建议'));
    await tester.pumpAndSettle();
    expect(find.text('美食'), findsOneWidget);
    await tester.pageBack();
    await tester.pumpAndSettle();
    expect(find.text('美食'), findsOneWidget);
    await tester.tap(find.text('档案'));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('profile-1')));
    await tester.pumpAndSettle();
    expect(find.text('绿地、手作和偶尔看展。'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });
}
