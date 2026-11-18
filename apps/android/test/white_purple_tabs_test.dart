import 'dart:convert';

import 'package:couple_app/src/data/catalog.dart';
import 'package:couple_app/src/services/cloud_session.dart';
import 'package:couple_app/src/services/personal_wallpaper.dart';
import 'package:couple_app/src/ui/wallpaper_editor.dart';
import 'package:couple_app/src/ui/white_purple_tabs.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';

void main() {
  testWidgets(
    '12 module paths stay reachable on a narrow screen with enlarged text',
    (t) async {
      final session = CloudSession();
      addTearDown(session.dispose);
      t.view.devicePixelRatio = 1;
      t.view.physicalSize = const Size(320, 710);
      addTearDown(t.view.resetPhysicalSize);
      addTearDown(t.view.resetDevicePixelRatio);
      final opened = <ModuleId>[];
      await t.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: Builder(
              builder: (context) => MediaQuery(
                data: MediaQuery.of(context)
                    .copyWith(textScaler: TextScaler.linear(1.65)),
                child: FeaturesTab(
                  session: session,
                  openModule: opened.add,
                  openPrivateChat: () {},
                ),
              ),
            ),
          ),
        ),
      );
      expect(find.text('还没有约好的计划'), findsOneWidget);
      for (final id in ModuleId.values) {
        final button = find.byKey(Key('module-${id.name}'));
        await t.ensureVisible(button);
        await t.tap(button);
        await t.pumpAndSettle();
      }
      expect(opened.toSet(), ModuleId.values.toSet());
      expect(find.text('演示'), findsOneWidget);
      expect(find.text('待开放'), findsNWidgets(4));
      expect(t.takeException(), isNull);
    },
  );

  testWidgets(
    'daily surfaces use server records and skip returned or past plans',
    (t) async {
      t.view.devicePixelRatio = 1;
      t.view.physicalSize = const Size(390, 844);
      addTearDown(t.view.resetPhysicalSize);
      addTearDown(t.view.resetDevicePixelRatio);
      final session = CloudSession();
      addTearDown(session.dispose);
      session.state = {
        'journeys': <Json>[
          {
            'plan': 'a',
            'stage': 'planned',
            'day': '2000-01-01',
            'title': '已过期',
          },
          {'plan': 'b', 'stage': 'wish', 'day': '2098-01-01', 'title': '已放回心愿'},
          {
            'plan': 'c',
            'stage': 'planned',
            'day': '2099-01-01',
            'clock': '14:00',
            'place': '东门',
            'title': '未来的计划',
          },
        ],
        'modules': <Json>[
          {'id': 'm', 'module': 'memory', 'title': '真实回忆', 'body': '新记录'},
        ],
      };
      ModuleId? opened;
      await t.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: DailyTab(session: session, openModule: (id) => opened = id),
          ),
        ),
      );
      expect(find.text('未来的计划'), findsOneWidget);
      expect(find.textContaining('东门'), findsOneWidget);
      expect(find.text('已过期'), findsNothing);
      expect(find.text('已放回心愿'), findsNothing);
      await t.ensureVisible(find.text('共同心愿'));
      await t.tap(find.text('共同心愿'));
      expect(opened, ModuleId.wish);
      await t.scrollUntilVisible(find.text('真实回忆'), 100);
      expect(find.text('真实回忆'), findsOneWidget);
    },
  );

  testWidgets(
    'photo preview, cancel, apply, account isolation, restore default and relaunch',
    (t) async {
      t.view.devicePixelRatio = 1;
      t.view.physicalSize = const Size(390, 844);
      addTearDown(t.view.resetPhysicalSize);
      addTearDown(t.view.resetDevicePixelRatio);
      final files = <String, Uint8List>{};
      final messenger =
          TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
      messenger.setMockMethodCallHandler(PersonalWallpaper.channel, (
        call,
      ) async {
        final scope = call.arguments['scope'] as String;
        switch (call.method) {
          case 'read':
            return files[scope];
          case 'write':
            files[scope] = call.arguments['data'] as Uint8List;
            return null;
          case 'clear':
            files.remove(scope);
            return null;
          default:
            fail('unrecognized call');
        }
      });
      addTearDown(
        () =>
            messenger.setMockMethodCallHandler(PersonalWallpaper.channel, null),
      );
      PersonalWallpaper account(
        String id, [
        String endpoint = 'https://example.invalid/couple',
      ]) => PersonalWallpaper.forAccount(endpoint: endpoint, userId: id);
      final a = account('A'),
          b = account('B'),
          anotherEndpoint = account('A', 'https://other.invalid/couple');
      final png = base64Decode(
        'iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAYAAAAfFcSJAAAADUlEQVR4nGMQcFj1HwADWAH6o4IrbAAAAABJRU5ErkJggg==',
      );
      await t.pumpWidget(
        MaterialApp(
          home: Builder(
            builder: (context) => Scaffold(
              body: TextButton(
                child: const Text('设置'),
                onPressed: () => Navigator.push(
                  context,
                  MaterialPageRoute(
                    builder: (_) =>
                        WallpaperEditor(controller: a, pick: () async => png),
                  ),
                ),
              ),
            ),
          ),
        ),
      );
      Future<void> tap(String label) async {
        final finder = find.text(label);
        await t.ensureVisible(finder);
        await t.pumpAndSettle();
        await t.tap(finder);
        await t.pumpAndSettle();
      }

      await tap('设置');
      await tap('从相册选择');
      expect(find.byKey(const Key('background-preview')), findsOneWidget);
      expect(files, isEmpty);
      await tap('取消');
      expect(files, isEmpty);
      expect(a.photo, isNull);
      await tap('设置');
      await tap('从相册选择');
      await tap('应用背景');
      expect(a.photo, png);
      final relaunched = account('A');
      await relaunched.load();
      await b.load();
      await anotherEndpoint.load();
      expect(relaunched.photo, png);
      expect(b.photo, isNull);
      expect(anotherEndpoint.photo, isNull);
      await tap('设置');
      await tap('恢复默认背景');
      await tap('取消');
      expect(a.photo, png);
      await tap('设置');
      await tap('恢复默认背景');
      await tap('应用背景');
      await relaunched.load();
      expect(a.photo, isNull);
      expect(relaunched.photo, isNull);
      for (final c in [a, b, anotherEndpoint, relaunched]) {
        c.dispose();
      }
    },
  );
}
