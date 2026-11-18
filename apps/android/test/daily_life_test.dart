import 'dart:convert';

import 'package:couple_app/src/services/cloud_session.dart';
import 'package:couple_app/src/ui/daily_life.dart';
import 'package:couple_app/src/ui/dp_module_chat.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';

const _png =
    'iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAYAAAAfFcSJAAAADUlEQVR4nGMQcFj1HwADWAH6o4IrbAAAAABJRU5ErkJggg==';

class _Session extends CloudSession {
  final wish = <String, dynamic>{
    'id': 'wish-one',
    'module': 'wish',
    'title': '想一起去海边',
    'body': '看看日落',
    'version': 1,
  };
  final plan = <String, dynamic>{
    'id': 'plan-one',
    'module': 'calendar',
    'title': '海边看日落',
    'body': '共同出行',
    'version': 2,
  };
  final links = <String, dynamic>{
    'wish': 'wish-one',
    'plan': 'plan-one',
    'memory': null,
    'stage': 'planned',
    'day': '2026-11-18',
    'clock': '16:20',
    'place': '东门',
    'address': '海州市临海公园',
  };
  final change = <String, dynamic>{
    'id': 41,
    'module_id': 'plan-one',
    'author': 'Alice',
    'action': 'meeting',
    'title': '海边看日落',
    'seen': false,
    'fields': ['place'],
    'previous': <String, dynamic>{'place': '南门'},
    'current': <String, dynamic>{'place': '东门'},
    'version': 2,
    'current_version': 2,
  };
  final writes = <String>[], proposals = <Json>[];
  bool failOnce = false;
  _Session(bool planned) {
    state = {
      'user': <String, dynamic>{'id': 'bob'},
      'modules': [wish, if (planned) plan],
      'journeys': [if (planned) links],
      'memory_photos': <Json>[],
      'joint_changes': [if (planned) change],
      'today_plans': [
        if (planned)
          <String, dynamic>{
            ...links,
            'title': plan['title'],
            'agreed_current': false,
          },
      ],
    };
  }
  @override
  Future<dynamic> mutate(String method, String path, [Json? body]) async {
    writes.add(path);
    if (path.endsWith('/read')) {
      change['seen'] = true;
      notifyListeners();
      return {'ok': true};
    }
    proposals.add({...body!});
    if (failOnce) {
      failOnce = false;
      throw const CloudError('暂时离线，可重试。', 503);
    }
    late String id;
    if (path.endsWith('/meeting')) {
      links.addAll({
        'clock': body['clock'],
        'day': body['day'],
        'place': body['place'],
        'address': body['address'],
        'stage': 'planned',
      });
      if (state['journeys'].isEmpty) {
        state['journeys'] = [links];
        state['modules'] = [wish, plan];
      }
      id = 'plan-one';
    } else if (path.endsWith('/return')) {
      links['stage'] = 'wish';
      id = 'wish-one';
    } else if (path.endsWith('/remember')) {
      id = 'memory-one';
      links.addAll({'memory': id, 'stage': 'remembered'});
      state['modules'] = [
        wish,
        plan,
        <String, dynamic>{
          'id': id,
          'module': 'memory',
          'title': '海边看日落',
          'body': body['note'],
          'version': 1,
        },
      ];
      if (body['photo'] != null) {
        state['memory_photos'] = [
          <String, dynamic>{'memory': id, 'owner': 'bob'},
        ];
      }
    } else {
      throw StateError(path);
    }
    notifyListeners();
    return {'module_id': id};
  }
}

Future<void> _tap(WidgetTester t, String title) async {
  final f = find.text(title).last;
  await t.ensureVisible(f);
  await t.tap(f);
  await t.pumpAndSettle();
}

void main() {
  testWidgets(
    '360px: today card and partner change lead to current plan; reading casts no vote',
    (t) async {
      t.view.devicePixelRatio = 1;
      t.view.physicalSize = const Size(360, 800);
      addTearDown(t.view.resetDevicePixelRatio);
      addTearDown(t.view.resetPhysicalSize);
      final s = _Session(true);
      addTearDown(s.dispose);
      await t.pumpWidget(
        MaterialApp(
          home: Scaffold(body: DailyLifeHome(session: s)),
        ),
      );
      expect(find.textContaining('16:20 · 东门'), findsOneWidget);
      expect(find.textContaining('变更待表态'), findsOneWidget);
      expect(find.byTooltip('地图导航'), findsOneWidget);
      await _tap(t, '伴侣的更新 · 1 条未读');
      expect(find.textContaining('集合点：南门 → 东门'), findsOneWidget);
      await t.tap(find.byTooltip('标为已读'));
      await t.pumpAndSettle();
      await _tap(t, 'Alice更新了集合安排');
      expect(find.text('海边看日落'), findsOneWidget);
      expect(find.text('16:20 · 东门'), findsOneWidget);
      expect(s.writes, ['/v1/life/changes/41/read']);
      expect(t.takeException(), isNull);
    },
  );

  testWidgets(
    '390px: schedule retry, return, restore and publish a travel memory',
    (t) async {
      t.view.devicePixelRatio = 1;
      t.view.physicalSize = const Size(390, 844);
      addTearDown(t.view.resetDevicePixelRatio);
      addTearDown(t.view.resetPhysicalSize);
      final s = _Session(false)..failOnce = true;
      addTearDown(s.dispose);
      await t.pumpWidget(
        MaterialApp(
          home: CloudModuleDetail(session: s, moduleId: 'wish-one'),
        ),
      );
      await _tap(t, '排进共同日程');
      await t.enterText(find.byType(TextField).at(1), '16:20');
      await t.enterText(find.byType(TextField).at(2), '东门');
      await _tap(t, '保存到共同计划');
      expect(find.textContaining('暂时离线'), findsOneWidget);
      await _tap(t, '保存到共同计划');
      expect(s.proposals[0]['request_id'], s.proposals[1]['request_id']);
      await _tap(t, '放回原心愿');
      await _tap(t, '确认放回心愿');
      await _tap(t, '排进共同日程');
      await _tap(t, '保存到共同计划');
      await _tap(t, '留下这次出行的回忆');
      await _tap(t, '我已成行，发布共同回忆');
      expect(find.text('请留下一句话或选择照片。'), findsOneWidget);
      await t.enterText(find.byType(TextField), '海风吹得很舒服');
      await _tap(t, '我已成行，发布共同回忆');
      expect(find.text('海风吹得很舒服'), findsOneWidget);
      expect(find.text('最初的心愿'), findsOneWidget);
      expect(find.text('关联计划'), findsOneWidget);
      expect(s.proposals.last['occurred'], true);
      expect(t.takeException(), isNull);
    },
  );

  testWidgets(
    'photo picker returns a metadata-free thumbnail for the confirmed shared memory',
    (t) async {
      const chan = MethodChannel('couple/device_media');
      final messenger =
          TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
      messenger.setMockMethodCallHandler(chan, (call) async {
        expect(call.method, 'pick');
        expect(call.arguments['imageOnly'], true);
        return {
          'name': 'trip.png',
          'mime': 'image/png',
          'data': base64Decode(_png),
        };
      });
      addTearDown(() => messenger.setMockMethodCallHandler(chan, null));
      final s = _Session(true);
      addTearDown(s.dispose);
      await t.pumpWidget(
        MaterialApp(
          home: CloudModuleDetail(session: s, moduleId: 'plan-one'),
        ),
      );
      await _tap(t, '留下这次出行的回忆');
      // The codec uses the engine's image worker in real time.
      await t.tap(find.text('添加照片'));
      await t.pump();
      for (var i = 0; i < 40 && find.text('移除照片').evaluate().isEmpty; i++) {
        await t.runAsync(
          () => Future<void>.delayed(const Duration(milliseconds: 15)),
        );
        await t.pump();
      }
      expect(find.text('移除照片'), findsOneWidget);
      await _tap(t, '我已成行，发布共同回忆');
      expect(base64Decode(s.proposals.last['photo'] as String).take(4), [
        0x89,
        0x50,
        0x4e,
        0x47,
      ]);
      expect(find.text('查看出行照片'), findsOneWidget);
    },
  );
}
