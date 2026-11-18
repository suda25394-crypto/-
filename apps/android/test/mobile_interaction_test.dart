import 'package:couple_app/src/app.dart';
import 'package:couple_app/src/data/catalog.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';

Future<void> _startPhone(
  WidgetTester tester,
  Size viewport, {
  double scale = 1,
}) async {
  tester.view.physicalSize = viewport;
  tester.view.devicePixelRatio = 1;
  final platform = tester.platformDispatcher;
  platform.textScaleFactorTestValue = scale;
  platform.accessibilityFeaturesTestValue = const FakeAccessibilityFeatures(
    disableAnimations: true,
  );
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);
  addTearDown(platform.clearTextScaleFactorTestValue);
  addTearDown(platform.clearAccessibilityFeaturesTestValue);
  await tester.pumpWidget(const CoupleApp());
  await tester.pumpAndSettle();
}

Future<void> _open(WidgetTester tester, Finder target) async {
  await tester.ensureVisible(target);
  expect(target.hitTestable(), findsOneWidget);
  await tester.tap(target);
  await tester.pumpAndSettle();
}

void main() {
  for (final size in [const Size(360, 800), const Size(390, 844)]) {
    testWidgets('AI remains reachable at ${size.width}px with large text', (
      tester,
    ) async {
      await _startPhone(tester, size, scale: 1.6);
      final entry = find.byKey(const Key('open-director'));
      await tester.ensureVisible(entry);
      final bounds = tester.getRect(entry);
      expect(bounds.left, greaterThanOrEqualTo(0));
      expect(bounds.right, lessThanOrEqualTo(size.width));
      expect(bounds.height, greaterThanOrEqualTo(48));
      await _open(tester, entry);
      expect(find.byKey(const Key('director-input')), findsOneWidget);
      await tester.pageBack();
      await tester.pumpAndSettle();
      expect(entry, findsOneWidget);
      expect(tester.takeException(), isNull);
    });
  }

  testWidgets('module edits stay staged until confirmed in the detail route', (
    tester,
  ) async {
    await _startPhone(tester, const Size(390, 844));
    final directoryTile = find.byKey(const Key('module-date'));
    final original = catalog[ModuleId.date]!.summary;
    const abandoned = '周五散步，等我再确认。';
    const accepted = '周六下午在公园见面。';
    final summaryField = find.byKey(const Key('module-summary-input'));

    await _open(tester, find.text('功能'));
    await _open(tester, directoryTile);
    await _open(tester, find.text('编辑'));
    await tester.enterText(summaryField, abandoned);
    await _open(tester, find.text('预览修改'));
    expect(
      find.descendant(
        of: find.byType(AlertDialog),
        matching: find.text(abandoned),
      ),
      findsOneWidget,
    );
    await _open(tester, find.text('继续编辑'));
    await tester.pageBack();
    await tester.pumpAndSettle();
    expect(find.text(original), findsOneWidget);
    expect(find.text(abandoned), findsNothing);

    await _open(tester, find.text('编辑'));
    await tester.enterText(summaryField, accepted);
    await _open(tester, find.text('预览修改'));
    await _open(tester, find.text('确认保存'));
    expect(find.text(accepted), findsOneWidget);
    await tester.pageBack();
    await tester.pumpAndSettle();
    expect(
      find.descendant(of: directoryTile, matching: find.text(accepted)),
      findsOneWidget,
    );
    await _open(tester, directoryTile);
    expect(find.text(accepted), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets(
    'shared composer stays above keyboard and AI links return to the conversation',
    (tester) async {
      const viewport = Size(360, 800);
      await _startPhone(tester, viewport);
      await _open(tester, find.text('共同'));
      final input = find.byKey(const Key('shared-message-input'));
      const keyboardHeight = 290.0;
      tester.view.viewInsets = const FakeViewPadding(bottom: keyboardHeight);
      addTearDown(tester.view.resetViewInsets);

      await tester.enterText(input, '晚饭一起吃');
      await tester.pumpAndSettle();
      final send = find.text('发送');
      expect(
        tester.getRect(send).bottom,
        lessThanOrEqualTo(viewport.height - keyboardHeight),
      );
      await _open(tester, send);
      expect(find.text('AI · 本地规则'), findsNothing);
      await _open(tester, find.text('@AI'));
      final composer = tester.widget<TextField>(input);
      expect(composer.controller!.text, contains('@AI'));
      await tester.enterText(input, '${composer.controller!.text}想找餐厅');
      await tester.testTextInput.receiveAction(TextInputAction.send);
      tester.view.resetViewInsets();
      await tester.pumpAndSettle();

      expect(find.text('AI · 本地规则'), findsOneWidget);
      await _open(tester, find.text(catalog[ModuleId.food]!.name));
      expect(
        find.widgetWithText(AppBar, catalog[ModuleId.food]!.name),
        findsOneWidget,
      );
      await tester.pageBack();
      await tester.pumpAndSettle();
      expect(find.byKey(const Key('shared-message-input')), findsOneWidget);
      expect(find.text('AI · 本地规则'), findsOneWidget);
      expect(tester.takeException(), isNull);
    },
  );
}
