import 'package:dsh_app/couple_proto/couple_controller.dart';
import 'package:dsh_app/couple_proto/main.dart';
import 'package:dsh_app/ui/chat/widgets/chat_card.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

class _UiSession extends CoupleController {
  _UiSession() {
    userId = 'test-alice';
    userName = 'Alice';
    meetings = [_initial];
  }

  static const _initial = Meeting(
    id: 'same-plan',
    title: '湖畔散步',
    version: 4,
    day: '2026-11-19',
    clock: '17:30',
    place: '东门',
    address: '',
  );

  int submissions = 0;
  int confirmations = 0;
  DelayProposal? pending;

  @override
  bool get signedIn => true;
  @override
  Meeting get selected => meetings.single;
  @override
  DelayProposal? get proposal => pending;
  @override
  Future<void> restore() async {
    loading = false;
  }

  @override
  void setForeground(bool value) {}

  @override
  Future<void> selectMeeting(String id) async {
    await setScope('private');
  }

  @override
  Future<void> setScope(String value) async {
    scope = value;
    messages = [
      {
        'id': 'line-$scope',
        'role': 'assistant',
        'owner': userId,
        'text': scope == 'private' ? '只在 Alice 的私聊中' : '双方授权的共同对话',
      },
    ];
    notifyListeners();
  }

  @override
  Future<void> send(String text) async {
    submissions++;
    messages = [
      ...messages,
      {
        'id': 'request-$submissions',
        'role': 'user',
        'owner': userId,
        'text': text,
      },
    ];
    pending = DelayProposal(selected, selected.day, '18:00');
    notifyListeners();
  }

  @override
  Future<void> cancel() async {
    pending = null;
    notifyListeners();
  }

  @override
  Future<void> confirm() async {
    if (pending == null) throw StateError('Duplicate write');
    confirmations++;
    pending = null;
    updateMeetingTime('18:00');
  }

  void updateMeetingTime(String time) {
    final old = selected;
    meetings = [
      Meeting(
        id: old.id,
        title: old.title,
        day: old.day,
        clock: time,
        place: old.place,
        address: old.address,
        version: old.version + 1,
      ),
    ];
    notifyListeners();
  }
}

Future<void> _open(WidgetTester tester, _UiSession session) async {
  tester.view.devicePixelRatio = 1;
  tester.view.physicalSize = const Size(390, 844);
  addTearDown(tester.view.resetDevicePixelRatio);
  addTearDown(tester.view.resetPhysicalSize);
  await tester.pumpWidget(CouplePrototype(controller: session));
  await tester.pumpAndSettle();
  await tester.tap(find.text('湖畔散步'));
  await tester.pumpAndSettle();
  expect(find.text('已确认时间 17:30'), findsOneWidget);
}

void main() {
  testWidgets(
    'a real dsh chat card previews a delay; only confirmation writes the original ID',
    (tester) async {
      final session = _UiSession();
      addTearDown(session.dispose);
      await _open(tester, session);
      Future<void> propose() async {
        await tester.tap(find.widgetWithText(ActionChip, '把约会推迟半小时'));
        await tester.pump();
        await tester.tap(find.byKey(const Key('dp-send')));
        await tester.pumpAndSettle();
        await tester.ensureVisible(find.byKey(const Key('confirm-delay')));
        expect(
          tester.widget<ChatCard>(find.byKey(const Key('proposal-card'))).title,
          'DP 的改期建议',
        );
        expect(find.text('原时间 2026-11-19 17:30'), findsOneWidget);
        expect(find.text('改为 2026-11-19 18:00'), findsOneWidget);
        expect(find.text('已确认时间 17:30'), findsOneWidget);
      }

      await propose();
      await tester.tap(find.byKey(const Key('cancel-delay')));
      await tester.pumpAndSettle();
      expect(session.confirmations, 0);
      await propose();
      await tester.tap(find.byKey(const Key('confirm-delay')));
      await tester.pumpAndSettle();
      expect(session.confirmations, 1);
      expect(session.selected.id, 'same-plan');
      expect(find.text('已确认时间 18:00'), findsOneWidget);
    },
  );

  testWidgets(
    'partner changes repaint the visible original time and private input is scoped',
    (tester) async {
      final session = _UiSession();
      addTearDown(session.dispose);
      await _open(tester, session);
      expect(find.text('只在 Alice 的私聊中'), findsOneWidget);
      await tester.enterText(find.byKey(const Key('dp-input')), '我的私人想法');
      await tester.tap(find.text('两人共同聊'));
      await tester.pumpAndSettle();
      expect(find.text('双方授权的共同对话'), findsOneWidget);
      expect(find.text('只在 Alice 的私聊中'), findsNothing);
      expect(find.text('我的私人想法'), findsNothing);
      session.updateMeetingTime('18:00');
      await tester.pumpAndSettle();
      expect(find.text('已确认时间 18:00'), findsOneWidget);
      await tester.tap(find.text('私下问 DP'));
      await tester.pumpAndSettle();
      expect(find.text('我的私人想法'), findsOneWidget);
      expect(find.text('双方授权的共同对话'), findsNothing);
    },
  );
}
