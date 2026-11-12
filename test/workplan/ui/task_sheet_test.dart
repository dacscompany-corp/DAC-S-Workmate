import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:workmate/ui/theme.dart';
import 'package:workmate/ui/wm_sheet.dart';
import 'package:workmate/workplan/data/workplan_api.dart';
import 'package:workmate/workplan/domain/wp_rules.dart';
import 'package:workmate/workplan/ui/my_work_controller.dart';
import 'package:workmate/workplan/ui/task_openers.dart';
import 'package:workmate/workplan/ui/task_sheet.dart';
import 'package:workmate/workplan/workplan_services.dart';

import '../../attendance/fakes.dart' show useTallPhone;
import '../workplan_fakes.dart';

void main() {
  late FakeWorkPlanApi api;
  late MyWorkController controller;
  late WorkPlanServices services;

  setUp(() {
    api = FakeWorkPlanApi();
    controller = MyWorkController(api: api, now: () => DateTime.utc(2026, 10, 14, 2));
    services = WorkPlanServices(api: api, takePhoto: (_) async => '/raw/shot.jpg');
  });

  Future<void> openSheet(WidgetTester tester, {TaskForm? form}) async {
    useTallPhone(tester);
    await controller.refresh();
    await tester.pumpWidget(MaterialApp(
      theme: workMateTheme(),
      home: Scaffold(
        body: Builder(
          builder: (context) => Center(
            child: TextButton(onPressed: () => openTask(context, controller, services, 't1', form: form), child: const Text('open')),
          ),
        ),
      ),
    ));
    await tester.tap(find.text('open'));
    await tester.pumpAndSettle();
  }

  testWidgets('the task opens as a tall sheet with the step tracker', (tester) async {
    api.view = WorkPlanView(entries: [WpEntry(task: task0(taskDoc(ackVersion: 1, status: 'in_progress')))]);
    await openSheet(tester);
    expect(find.byType(TaskSheet), findsOneWidget);
    expect(find.text('Wall prep'), findsWidgets);
    expect(find.byKey(const Key('step-tracker')), findsOneWidget);
    expect(find.byKey(const Key('step-0-done')), findsOneWidget);
    expect(find.byKey(const Key('step-1-done')), findsOneWidget);
    expect(find.byKey(const Key('step-2-current')), findsOneWidget);
    expect(find.byKey(const Key('step-3-todo')), findsOneWidget);
    expect(find.byKey(const Key('done')), findsOneWidget, reason: 'REPORT DONE is the main button');
  });

  testWidgets('checked by the leader: a line under step 3; reported work says the office checks it', (tester) async {
    api.view = WorkPlanView(entries: [WpEntry(task: task0(taskDoc(ackVersion: 1, status: 'leader_checked')))]);
    await openSheet(tester);
    expect(find.byKey(const Key('leader-checked')), findsOneWidget);
    expect(find.text('Checked by the leader'), findsOneWidget);
    expect(find.text('The office checks the work before it counts as completed.'), findsOneWidget);
  });

  testWidgets('from a form, Back, dragging down and tapping outside return to the task — never close it', (tester) async {
    api.view = WorkPlanView(entries: [WpEntry(task: task0(taskDoc(ackVersion: 1, status: 'in_progress')))]);
    await openSheet(tester, form: TaskForm.progress);
    expect(find.byKey(const Key('note-field')), findsOneWidget, reason: 'opened straight on the form');

    await tester.binding.handlePopRoute();
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('note-field')), findsNothing);
    expect(find.byKey(const Key('step-tracker')), findsOneWidget, reason: 'Back → the task');

    await tester.tap(find.byKey(const Key('progress')));
    await tester.pumpAndSettle();
    await tester.timedDrag(find.byKey(const Key('wm-sheet-handle')), const Offset(0, 160), const Duration(milliseconds: 800));
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('step-tracker')), findsOneWidget, reason: 'drag → the task');

    await tester.tap(find.byKey(const Key('progress')));
    await tester.pumpAndSettle();
    await tester.tapAt(const Offset(20, 20));
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('step-tracker')), findsOneWidget, reason: 'outside tap → the task');

    await tester.binding.handlePopRoute();
    await tester.pumpAndSettle();
    expect(find.byType(TaskSheet), findsNothing, reason: 'from the task, Back closes the sheet');
    expect(api.calls, isEmpty);
  });

  testWidgets('a task that left the list says so', (tester) async {
    api.view = WorkPlanView(entries: [WpEntry(task: task0(taskDoc(ackVersion: 1)))]);
    await openSheet(tester);
    api.view = const WorkPlanView();
    await controller.refresh();
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('task-gone')), findsOneWidget);
    expect(find.text('This task is no longer on your list.'), findsOneWidget);
  });

  testWidgets('a completed task: no main button, "Completed." under the tracker', (tester) async {
    api.view = WorkPlanView(entries: [WpEntry(task: task0(taskDoc(ackVersion: 1, status: 'completed')))]);
    await openSheet(tester);
    expect(find.byType(WmSheetButton), findsNothing);
    expect(find.text('Completed.'), findsOneWidget);
  });

  testWidgets('sending clears the draft; the sent photo is not deleted', (tester) async {
    api.view = WorkPlanView(entries: [WpEntry(task: task0(taskDoc(ackVersion: 1, status: 'in_progress')))]);
    await openSheet(tester, form: TaskForm.progress);
    await tester.enterText(find.byKey(const Key('note-field')), 'Half done');
    await tester.tap(find.byKey(const Key('add-photo')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('note-submit')));
    await tester.pumpAndSettle();
    expect(api.calls.last, 'progress:t1:Half done:/kept/1.jpg');
    await tester.tap(find.byKey(const Key('progress')));
    await tester.pumpAndSettle();
    expect(tester.widget<TextField>(find.byKey(const Key('note-field'))).controller!.text, '');
    expect(find.byKey(const Key('remove-photo')), findsNothing);
    await tester.tap(find.byKey(const Key('wm-sheet-back')));
    await tester.pumpAndSettle();
    await tester.binding.handlePopRoute(); // close the sheet
    await tester.pumpAndSettle();
    expect(api.discarded, isEmpty);
  });

  testWidgets('each form keeps its own draft; a problem draft keeps its kind and words', (tester) async {
    api.view = WorkPlanView(entries: [WpEntry(task: task0(taskDoc(ackVersion: 1, status: 'in_progress')))]);
    await openSheet(tester, form: TaskForm.problem);
    await tester.tap(find.byKey(const Key('kind-tool')));
    await tester.pumpAndSettle();
    await tester.enterText(find.byKey(const Key('problem-field')), 'No grinder');
    await tester.tap(find.byKey(const Key('wm-sheet-back')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('progress')));
    await tester.pumpAndSettle();
    expect(tester.widget<TextField>(find.byKey(const Key('note-field'))).controller!.text, '');
    await tester.tap(find.byKey(const Key('wm-sheet-back')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('problem')));
    await tester.pumpAndSettle();
    expect(tester.widget<ChoiceChip>(find.byKey(const Key('kind-tool'))).selected, isTrue);
    expect(find.text('No grinder'), findsOneWidget);
    expect(api.calls, isEmpty);
  });
}
