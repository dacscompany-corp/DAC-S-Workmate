import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:workmate/ui/theme.dart';
import 'package:workmate/workplan/data/wp_hint_store.dart';
import 'package:workmate/workplan/domain/wp_rules.dart';
import 'package:workmate/workplan/ui/task_card.dart';
import 'package:workmate/workplan/ui/task_sheet.dart';

import '../../attendance/fakes.dart' show useTallPhone;
import '../workplan_fakes.dart';

void main() {
  late bool open;
  late int taps;
  late List<TaskForm> reported;
  late List<bool> changes;
  late ValueNotifier<WpEntry> entry;

  setUp(() {
    open = false;
    taps = 0;
    reported = [];
    changes = [];
  });

  Future<void> show(WidgetTester tester, Map<String, dynamic> doc) async {
    useTallPhone(tester);
    entry = ValueNotifier(WpEntry(task: task0(doc)));
    await tester.pumpWidget(MaterialApp(
      theme: workMateTheme(),
      home: Scaffold(
        body: StatefulBuilder(
          builder: (context, setState) => ListenableBuilder(
            listenable: entry,
            builder: (context, _) => ListView(padding: const EdgeInsets.all(20), children: [
            TaskCard(
              key: const Key('task-t1'),
              entry: entry.value,
              today: '2026-10-14',
              open: open,
              onOpenChanged: (o) => setState(() {
                changes.add(o);
                open = o;
              }),
              onTap: () => taps++,
              onReport: reported.add,
            ),
            ]),
          ),
        ),
      ),
    ));
    await tester.pumpAndSettle();
  }

  final card = find.byKey(const Key('task-t1'));

  testWidgets('a responsible person in progress: a swipe past 64 px shows Progress and Problem', (tester) async {
    await show(tester, taskDoc(ackVersion: 1, status: 'in_progress'));
    await tester.timedDrag(card, const Offset(-120, 0), const Duration(milliseconds: 300));
    await tester.pumpAndSettle();
    expect(open, isTrue);
    await tester.tap(find.byKey(const Key('swipe-progress-t1')));
    await tester.pumpAndSettle();
    expect(reported, [TaskForm.progress]);
    expect(open, isFalse, reason: 'the card closes as the form opens');
  });

  testWidgets('a short swipe springs back', (tester) async {
    await show(tester, taskDoc(ackVersion: 1, status: 'in_progress'));
    await tester.timedDrag(card, const Offset(-40, 0), const Duration(milliseconds: 300));
    await tester.pumpAndSettle();
    expect(open, isFalse);
  });

  testWidgets('a helper sees only Problem', (tester) async {
    await show(tester, taskDoc(role: 'helper', ackVersion: 1, status: 'in_progress'));
    expect(find.byKey(const Key('swipe-progress-t1')), findsNothing);
    expect(find.byKey(const Key('swipe-problem-t1')), findsOneWidget);
    expect(canSwipe(WpEntry(task: task0(taskDoc(role: 'helper', ackVersion: 1, status: 'in_progress')))), isTrue);
  });

  testWidgets('a completed task does not move; a tap opens it', (tester) async {
    await show(tester, taskDoc(ackVersion: 1, status: 'completed'));
    expect(find.byKey(const Key('swipe-problem-t1')), findsNothing);
    await tester.timedDrag(card, const Offset(-120, 0), const Duration(milliseconds: 300));
    await tester.pumpAndSettle();
    expect(changes, isEmpty);
    await tester.tap(card);
    expect(taps, 1);
  });

  testWidgets('a task that can no longer be swiped mid-drag springs back', (tester) async {
    await show(tester, taskDoc(ackVersion: 1, status: 'in_progress'));
    final before = tester.getTopLeft(find.text('Wall prep'));
    final gesture = await tester.startGesture(tester.getCenter(card));
    for (var i = 0; i < 4; i++) {
      await gesture.moveBy(const Offset(-30, 0));
      await tester.pump();
    }
    entry.value = WpEntry(task: task0(taskDoc(ackVersion: 1, status: 'completed')));
    await tester.pump();
    await gesture.up();
    await tester.pumpAndSettle();
    expect(changes, isEmpty);
    expect(open, isFalse);
    expect(tester.getTopLeft(find.text('Wall prep')), before);
  });

  testWidgets('a tap on an open card closes it instead of opening the task', (tester) async {
    await show(tester, taskDoc(ackVersion: 1, status: 'in_progress'));
    await tester.timedDrag(card, const Offset(-120, 0), const Duration(milliseconds: 300));
    await tester.pumpAndSettle();
    await tester.tapAt(tester.getTopLeft(card) + const Offset(30, 30));
    await tester.pumpAndSettle();
    expect([open, taps], [false, 0]);
  });

  testWidgets('the 4-part bar and the Next line', (tester) async {
    await show(tester, taskDoc(ackVersion: 1, status: 'in_progress'));
    for (final k in ['bar-0-on', 'bar-1-on', 'bar-2-off', 'bar-3-off']) {
      expect(find.byKey(Key(k)), findsOneWidget, reason: k);
    }
    expect(find.text('Next: report done'), findsOneWidget);
    expect(find.text('Wall prep'), findsOneWidget);
  });

  test('the swipe hint is remembered on the phone', () async {
    SharedPreferences.setMockInitialValues({});
    final prefs = await SharedPreferences.getInstance();
    final a = PrefsWpHintStore(prefs);
    expect(a.swipeSeen, isFalse);
    await a.markSwipeSeen();
    expect(PrefsWpHintStore(prefs).swipeSeen, isTrue);
    final m = MemoryWpHintStore();
    await m.markSwipeSeen();
    expect(m.swipeSeen, isTrue);
  });
}
