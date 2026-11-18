import 'dart:convert';

import 'package:couple_app/src/services/cloud_session.dart';
import 'package:couple_app/src/ui/official_tools.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';

class ToolSession extends CloudSession {
  final calls = <Json>[];
  Json? file;
  bool fail = false;
  @override
  Future<dynamic> request(String method, String path, [Json? data]) async {
    if (path.startsWith('/v1/ai/attachments?')) {
      return {
        'attachments': [?file],
      };
    }
    if (path.startsWith('/v1/ai/tools?')) return {'results': []};
    if (method == 'POST' && path == '/v1/ai/attachments') {
      file = {
        'id': 's01',
        'name': data!['name'],
        'owner': 'a',
        'expires_at': 1900000000,
      };
      return file;
    }
    if (method == 'DELETE') {
      file = null;
      return {'deleted': true};
    }
    throw StateError(path);
  }

  @override
  Future<dynamic> mutate(String method, String path, [Json? data]) async {
    calls.add({...data!});
    if (fail) throw const CloudError('转写失败，请重试。', 503, 'rejected');
    return <String, dynamic>{
      'id': 'reply01',
      'kind': data['kind'],
      'text': '可修订的结果',
      'sources': [
        {'title': '可核对的来源', 'url': 'https://example.org/'},
      ],
      if (data['kind'] == 'tts') 'audio_b64': base64Encode([1]),
    };
  }
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  const media = MethodChannel('couple/device_media');
  Future<void> inspect(WidgetTester t, ToolSession session) async {
    await t.pumpWidget(
      MaterialApp(
        home: OfficialTools(session: session, scope: 'private'),
      ),
    );
    await t.pumpAndSettle();
  }

  Future<void> choose(WidgetTester t, String kind) async {
    await t.ensureVisible(find.byType(DropdownButton<String>));
    await t.tap(find.byType(DropdownButton<String>));
    await t.pumpAndSettle();
    final option = find.text(toolNames[kind]!);
    if (option.evaluate().isEmpty) {
      await t.scrollUntilVisible(
        option,
        120,
        scrollable: find.byType(Scrollable).last,
      );
    }
    final f = option.last;
    await Scrollable.ensureVisible(t.element(f), alignment: 0.5);
    await t.pumpAndSettle();
    await t.tap(f.hitTestable());
    await t.pumpAndSettle();
  }

  Future<void> click(WidgetTester t, String label) async {
    final f = find.text(label).last;
    await Scrollable.ensureVisible(t.element(f), alignment: 0.5);
    await t.pumpAndSettle();
    await t.tap(f.hitTestable());
    await t.pumpAndSettle();
  }

  testWidgets('手机按需调用所有工具、沿同一结果续问、停止朗读、附件恢复删除', (t) async {
    final s = ToolSession();
    s.state = {
      'user': {'id': 'a'},
    };
    t.view.devicePixelRatio = 1;
    t.view.physicalSize = const Size(390, 844);
    addTearDown(t.view.resetPhysicalSize);
    addTearDown(t.view.resetDevicePixelRatio);
    final native = <String>[];
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(media, (c) async {
          native.add(c.method);
          if (c.method == 'pick') {
            return {
              'name': 'poster.png',
              'mime': 'image/png',
              'data': Uint8List.fromList([1]),
            };
          }
          return null;
        });
    addTearDown(
      () => TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(media, null),
    );
    await inspect(t, s);
    for (final k in toolNames.keys) {
      await choose(t, k);
      await t.enterText(find.byType(TextField).first, '公开示例');
      if (k == 'vision') {
        await click(t, '选择文件（最多 4 MiB）');
      }
      await click(t, '运行${toolNames[k]}');
      expect(s.calls.last['kind'], k);
      expect(s.calls.last['scope'], 'private');
      if (k == 'web') {
        await click(t, '围绕同一来源追问');
        await t.enterText(find.byType(TextField).first, '上一个来源呢');
        await click(t, '运行网页搜索');
        expect(s.calls.last['previous_id'], 'reply01');
      }
      if (k == 'poster_draft') {
        expect(s.calls.last['attachment_id'], 's01');
      }
      if (k == 'tts') {
        await click(t, '播放');
        await click(t, '停止朗读');
        expect(native, containsAllInOrder(['play', 'stop']));
      }
    }
    await t.pumpWidget(const SizedBox());
    await t.pumpAndSettle();
    await inspect(t, s);
    await click(t, '本会话的临时附件');
    await click(t, 'poster.png');
    final del = find.byTooltip('删除附件');
    await t.ensureVisible(del);
    await t.tap(del);
    await t.pumpAndSettle();
    expect(s.file, isNull);
  });
  testWidgets('音频无法播放时显示失败，仍可返回结果', (t) async {
    final s = ToolSession();
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(media, (call) async {
          if (call.method == 'play') {
            throw PlatformException(code: 'media', message: '无法播放这段音频');
          }
          return null;
        });
    addTearDown(
      () => TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(media, null),
    );
    await inspect(t, s);
    await choose(t, 'tts');
    await t.enterText(find.byType(TextField).first, '活动安排');
    await click(t, '运行朗读文字');
    await click(t, '播放');
    expect(find.text('无法播放这段音频'), findsOneWidget);
    expect(s.calls, hasLength(1));
  });
  testWidgets('拒绝录音权限与转写失败均保留在工具页，未发送任何聊天', (t) async {
    final s = ToolSession();
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(media, (c) async {
          if (c.method == 'record') {
            throw PlatformException(code: 'denied', message: '未授权麦克风');
          }
          return null;
        });
    addTearDown(
      () => TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(media, null),
    );
    await inspect(t, s);
    await choose(t, 'asr');
    await click(t, '录一段语音');
    expect(find.text('未授权麦克风'), findsOneWidget);
    expect(s.calls, isEmpty);
    s.fail = true;
    await click(t, '运行语音转文字');
    expect(find.textContaining('转写失败'), findsOneWidget);
    expect(find.text('带回输入框，修订后发送'), findsNothing);
  });
}
