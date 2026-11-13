import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:workmate/requests/data/requests_api.dart';
import 'package:workmate/requests/domain/remote_request.dart';
import 'package:workmate/requests/domain/request_status.dart';
import 'package:workmate/ui/theme.dart';
import 'package:workmate/ui/wm_sheet.dart';
import 'package:workmate/workplan/data/workplan_api.dart';
import 'package:workmate/workplan/data/wp_hint_store.dart';
import 'package:workmate/workplan/domain/wp_op.dart';
import 'package:workmate/workplan/domain/wp_rules.dart';
import 'package:workmate/workplan/domain/wp_task.dart';
import 'package:workmate/workplan/ui/my_work_controller.dart';
import 'package:workmate/workplan/ui/my_work_screen.dart';
import 'package:workmate/workplan/ui/proposals_screen.dart';
import 'package:workmate/workplan/ui/task_openers.dart';
import 'package:workmate/workplan/ui/task_sheet.dart';
import 'package:workmate/workplan/workplan_services.dart';

import '../../attendance/fakes.dart';
import '../../requests/domain/request_models_test.dart' show requestDoc;
import '../../requests/request_fakes.dart';
import '../workplan_fakes.dart';

Widget wrap(Widget w) => MaterialApp(theme: workMateTheme(), home: Scaffold(body: w));

WorkPlanView viewOf(List<Map<String, dynamic>> docs, {List<WpOp> pending = const [], List<WpOp> failed = const []}) => WorkPlanView(
      entries: [
        for (final d in docs)
          WpEntry(
            task: task0(d),
            pendingOps: pending.where((o) => o.taskId == d['id']).toList(),
            failedOps: failed.where((o) => o.taskId == d['id']).toList(),
          ),
      ],
      notes: [WpNote.fromJson(noteDoc())],
    );

WpOp anOp(WpOpKind kind, {String task = 't1', String? error}) => WpOp(
      opId: 'op-${kind.name}',
      workerId: 'u1',
      kind: kind,
      createdAt: DateTime.utc(2026, 10, 14),
      taskId: task,
      lastError: error,
      failedPermanently: error != null,
    );

void main() {
  late FakeWorkPlanApi api;
  late MyWorkController controller;
  late WorkPlanServices services;

  setUp(() {
    api = FakeWorkPlanApi();
    controller = MyWorkController(api: api, now: () => DateTime.utc(2026, 10, 14, 2));
    services = WorkPlanServices(api: api, takePhoto: (_) async => '/raw/shot.jpg');
  });

  Future<void> open(WidgetTester tester, Widget screen) async {
    useTallPhone(tester);
    await controller.refresh();
    await tester.pumpWidget(wrap(screen));
    await tester.pumpAndSettle();
  }

  /// My proposals opens as a sheet over a plain page (as from Home).
  Future<void> openProposals(WidgetTester tester) async {
    useTallPhone(tester);
    await tester.pumpWidget(wrap(Builder(
      builder: (context) => Center(
        child: TextButton(onPressed: () => showProposalsSheet(context, controller), child: const Text('open proposals')),
      ),
    )));
    await tester.tap(find.text('open proposals'));
    await tester.pumpAndSettle();
  }

  /// The task opens as a sheet over a plain page (as from My Work or Home).
  Future<void> openTaskSheet(WidgetTester tester, {VoidCallback? onMakeRequest}) async {
    useTallPhone(tester);
    await controller.refresh();
    await tester.pumpWidget(MaterialApp(
      theme: workMateTheme(),
      home: Scaffold(
        body: Builder(
          builder: (context) => Center(
            child: TextButton(
              onPressed: () => openTask(context, controller, services, 't1', onMakeRequest: onMakeRequest),
              child: const Text('open'),
            ),
          ),
        ),
      ),
    ));
    await tester.tap(find.text('open'));
    await tester.pumpAndSettle();
  }

  testWidgets('My Work: chips with counts, Today first, notes; no proposals for a worker', (tester) async {
    api.view = viewOf([
      taskDoc(id: 't1', title: 'Skim coat', ackVersion: null),
      taskDoc(id: 't2', title: 'Cabinets', ackVersion: 1, start: '2026-10-20', end: '2026-10-21'),
      taskDoc(id: 't3', title: 'Garage', ackVersion: 1, blocked: true),
    ]);
    await open(tester, MyWorkScreen(controller: controller, services: services, isLeader: false));
    for (final (chip, n) in [('chip-today', '1'), ('chip-upcoming', '1'), ('chip-waiting', '1'), ('chip-done', '0')]) {
      expect(find.descendant(of: find.byKey(Key(chip)), matching: find.text(n)), findsOneWidget, reason: chip);
    }
    expect(find.text('Skim coat'), findsOneWidget, reason: 'Today is selected when the tab opens');
    expect(find.text('Cabinets'), findsNothing);
    expect(find.text('New'), findsOneWidget);
    expect(find.text('Next: read the task'), findsOneWidget);
    await tester.tap(find.byKey(const Key('chip-upcoming')));
    await tester.pumpAndSettle();
    expect(find.text('Cabinets'), findsOneWidget);
    expect(find.text('Skim coat'), findsNothing);
    await tester.ensureVisible(find.byKey(const Key('chip-done'))); // the chip row scrolls sideways
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('chip-done')));
    await tester.pumpAndSettle();
    expect(find.text('No tasks here right now.'), findsOneWidget);
    expect(find.text('Meeting notes (1)'), findsOneWidget);
    expect(find.byKey(const Key('open-proposals')), findsNothing);
    await tester.tap(find.byKey(const Key('open-notes')));
    await tester.pumpAndSettle();
    expect(find.text('Skim coat first, then cabinets.'), findsOneWidget);
  });

  testWidgets('a swipe opens the task on that form and sends nothing; the hint goes and stays gone', (tester) async {
    final hints = MemoryWpHintStore();
    services = WorkPlanServices(api: api, takePhoto: (_) async => '/raw/shot.jpg', hints: hints);
    api.view = viewOf([taskDoc(ackVersion: 1, status: 'in_progress')]);
    await open(tester, MyWorkScreen(controller: controller, services: services, isLeader: false));
    expect(find.byKey(const Key('swipe-hint')), findsOneWidget);
    await tester.timedDrag(find.byKey(const Key('task-t1')), const Offset(-120, 0), const Duration(milliseconds: 300));
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('swipe-hint')), findsNothing);
    expect(hints.swipeSeen, isTrue);
    await tester.tap(find.byKey(const Key('swipe-problem-t1')));
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('problem-field')), findsOneWidget, reason: 'the sheet opened on Report a problem');
    expect(api.calls, isEmpty, reason: 'nothing is sent by a swipe');
    await tester.binding.handlePopRoute(); // form → task
    await tester.pumpAndSettle();
    await tester.binding.handlePopRoute(); // task → closed
    await tester.pumpAndSettle();
    // A fresh screen (new state), as when the tab is opened again: only the store remembers.
    await tester.pumpWidget(const SizedBox());
    await tester.pumpWidget(wrap(MyWorkScreen(controller: controller, services: services, isLeader: false)));
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('swipe-hint')), findsNothing, reason: 'remembered');
  });

  group('one open card at a time', () {
    Future<void> openTwo(WidgetTester tester) async {
      api.view = viewOf([
        taskDoc(id: 't1', title: 'Skim coat', ackVersion: 1, status: 'in_progress'),
        taskDoc(id: 't2', title: 'Cabinets', ackVersion: 1, status: 'in_progress'),
      ]);
      await open(tester, MyWorkScreen(controller: controller, services: services, isLeader: false));
    }

    Future<void> swipe(WidgetTester tester, String id) async {
      await tester.timedDrag(find.byKey(Key('task-$id')), const Offset(-120, 0), const Duration(milliseconds: 300));
      await tester.pumpAndSettle();
    }

    double titleX(WidgetTester tester, String t) => tester.getTopLeft(find.text(t)).dx;

    testWidgets('one card open at a time', (tester) async {
      await openTwo(tester);
      final x1 = titleX(tester, 'Skim coat');
      final x2 = titleX(tester, 'Cabinets');
      await swipe(tester, 't1');
      expect(titleX(tester, 'Skim coat'), lessThan(x1));
      await swipe(tester, 't2');
      expect(titleX(tester, 'Skim coat'), x1);
      expect(titleX(tester, 'Cabinets'), lessThan(x2));
    });

    testWidgets('tapping another card closes the open one', (tester) async {
      await openTwo(tester);
      final x1 = titleX(tester, 'Skim coat');
      await swipe(tester, 't1');
      expect(titleX(tester, 'Skim coat'), lessThan(x1));
      await tester.tap(find.byKey(const Key('task-t2')));
      await tester.pumpAndSettle();
      expect(find.byKey(const Key('swipe-hint')), findsNothing);
      await tester.binding.handlePopRoute();
      await tester.pumpAndSettle();
      expect(titleX(tester, 'Skim coat'), x1);
    });

    testWidgets('switching chip closes the open card', (tester) async {
      await openTwo(tester);
      final x1 = titleX(tester, 'Skim coat');
      await swipe(tester, 't1');
      expect(titleX(tester, 'Skim coat'), lessThan(x1));
      for (final k in const ['chip-upcoming', 'chip-today']) {
        await tester.ensureVisible(find.byKey(Key(k)));
        await tester.pumpAndSettle();
        await tester.tap(find.byKey(Key(k)));
        await tester.pumpAndSettle();
      }
      expect(titleX(tester, 'Skim coat'), x1);
    });
  });

  testWidgets('a tap on a card opens the task sheet', (tester) async {
    api.view = viewOf([taskDoc(ackVersion: 1, status: 'in_progress')]);
    await open(tester, MyWorkScreen(controller: controller, services: services, isLeader: false));
    await tester.tap(find.byKey(const Key('task-t1')));
    await tester.pumpAndSettle();
    expect(find.byType(TaskSheet), findsOneWidget);
  });

  testWidgets('a changed task says what changed; "I\'ve read this" is the first thing to do', (tester) async {
    api.view = viewOf([
      taskDoc(version: 2, ackVersion: 1, history: [
        {'id': 5, 'kind': 'revised', 'note': 'Changed: planned dates', 'by': 'Office', 'at': '2026-10-14T01:00:00+00:00'},
      ]),
    ]);
    await openTaskSheet(tester);
    expect(find.text('Changed'), findsOneWidget);
    expect(find.text('The office changed this task. Read it again.'), findsOneWidget);
    expect(find.text('Changed: planned dates'), findsWidgets);
    expect(find.byKey(const Key('start')), findsNothing, reason: "I've read this comes first: Start is not offered yet");
    expect(find.text('Read the task first: tap "I\'ve read this".'), findsOneWidget);
    await tester.tap(find.byKey(const Key('ack')));
    await tester.pumpAndSettle();
    expect(api.calls, ['ack:t1:2']);
  });

  testWidgets('blocked: Start is locked and the problems are listed; only the office clears them', (tester) async {
    api.view = viewOf([
      taskDoc(ackVersion: 1, blocked: true, blockers: [
        {'id': 'b1', 'kind': 'materials', 'description': 'No cement', 'request_id': null, 'reported_at': '2026-10-14T03:00:00+00:00', 'reported_by': 'Danilo'},
      ], waitingFor: [
        {'task_id': 't0', 'title': 'Wall prep', 'status': 'in_progress'},
      ]),
    ]);
    await openTaskSheet(tester);
    expect(tester.widget<WmSheetButton>(find.byKey(const Key('start'))).onPressed, isNull);
    expect(find.textContaining('must be cleared by the office first'), findsOneWidget);
    expect(find.text('Materials: No cement'), findsOneWidget);
    expect(find.text('Earlier task: Wall prep'), findsOneWidget);
    expect(find.byKey(const Key('problem')), findsOneWidget, reason: 'problems can still be reported');
  });

  testWidgets('Start, then progress with a photo, then report done', (tester) async {
    api.view = viewOf([taskDoc(ackVersion: 1)]);
    await openTaskSheet(tester);
    await tester.tap(find.byKey(const Key('start')));
    await tester.pumpAndSettle();
    expect(api.calls, ['start:t1']);

    await tester.tap(find.byKey(const Key('progress')));
    await tester.pumpAndSettle();
    expect(tester.widget<WmSheetButton>(find.byKey(const Key('note-submit'))).onPressed, isNull, reason: 'a note is required');
    await tester.enterText(find.byKey(const Key('note-field')), 'Half done');
    await tester.tap(find.byKey(const Key('add-photo')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('note-submit')));
    await tester.pumpAndSettle();
    expect(api.calls.last, 'progress:t1:Half done:/kept/1.jpg');

    api.view = viewOf([taskDoc(ackVersion: 1, status: 'in_progress')]);
    await controller.refresh();
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('done')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('note-submit')));
    await tester.pumpAndSettle();
    expect(api.calls.last, 'done:t1:');
  });

  testWidgets('a form left and reopened keeps its note and photo; closing the sheet deletes the unsent photo', (tester) async {
    api.view = viewOf([taskDoc(ackVersion: 1, status: 'in_progress')]);
    await openTaskSheet(tester);
    await tester.tap(find.byKey(const Key('progress')));
    await tester.pumpAndSettle();
    await tester.enterText(find.byKey(const Key('note-field')), 'Half done');
    await tester.tap(find.byKey(const Key('add-photo')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('wm-sheet-back')));
    await tester.pumpAndSettle();
    expect(api.discarded, isEmpty, reason: 'the draft is kept while the sheet is open');
    await tester.tap(find.byKey(const Key('progress')));
    await tester.pumpAndSettle();
    expect(find.text('Half done'), findsOneWidget);
    expect(find.byKey(const Key('remove-photo')), findsOneWidget);
    await tester.tap(find.byKey(const Key('wm-sheet-back')));
    await tester.pumpAndSettle();
    await tester.binding.handlePopRoute(); // the task view closes the sheet
    await tester.pumpAndSettle();
    expect(api.discarded, ['/kept/1.jpg']);
    expect(api.calls, isEmpty);
  });

  testWidgets('a materials problem links one of the worker\'s own requests for this project, or opens Requests', (tester) async {
    final requests = FakeRequestsApi()
      ..view = RequestsView(entries: [
        RequestEntry(state: SyncState.received, remote: RemoteRequest.fromJson(requestDoc(id: 'r1'))),
        RequestEntry(state: SyncState.received, remote: RemoteRequest.fromJson(requestDoc(id: 'r2', mine: false))),
        RequestEntry(state: SyncState.received, remote: RemoteRequest.fromJson({...requestDoc(id: 'r3'), 'project_id': 'f9'})),
      ]);
    services = WorkPlanServices(api: api, takePhoto: (_) async => null, requests: requests);
    var madeRequest = 0;
    api.view = viewOf([taskDoc(role: 'helper', ackVersion: 1)]);
    await openTaskSheet(tester, onMakeRequest: () => madeRequest++);
    await tester.tap(find.byKey(const Key('problem')));
    await tester.pumpAndSettle();
    await tester.enterText(find.byKey(const Key('problem-field')), 'No cement');
    await tester.tap(find.byKey(const Key('problem-request')));
    await tester.pumpAndSettle();
    expect(find.textContaining('Santos Townhouse · Main Contract'), findsWidgets);
    final options = tester.widgetList<DropdownMenuItem<String?>>(find.byType(DropdownMenuItem<String?>)).map((i) => i.value).toSet();
    expect(options, {null, 'r1'}, reason: 'not a team member\'s request, not another project\'s');
    await tester.tap(find.textContaining('1 item').last);
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('problem-submit')));
    await tester.pumpAndSettle();
    expect(api.calls.single, 'problem:t1:materials:No cement:r1:null');

    await tester.tap(find.byKey(const Key('problem')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('make-request')));
    await tester.pumpAndSettle();
    expect(madeRequest, 1);
    expect(api.calls, hasLength(1), reason: 'nothing is reported or ordered by the shortcut');
  });

  testWidgets('a kept request link that is no longer listed is not sent', (tester) async {
    final requests = FakeRequestsApi()
      ..view = RequestsView(entries: [
        RequestEntry(state: SyncState.received, remote: RemoteRequest.fromJson(requestDoc(id: 'r1'))),
      ]);
    services = WorkPlanServices(api: api, takePhoto: (_) async => null, requests: requests);
    api.view = viewOf([taskDoc(role: 'helper', ackVersion: 1)]);
    await openTaskSheet(tester);
    await tester.tap(find.byKey(const Key('problem')));
    await tester.pumpAndSettle();
    await tester.enterText(find.byKey(const Key('problem-field')), 'No cement');
    await tester.tap(find.byKey(const Key('problem-request')));
    await tester.pumpAndSettle();
    await tester.tap(find.textContaining('1 item').last);
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('wm-sheet-back')));
    await tester.pumpAndSettle();
    requests.view = RequestsView(entries: [
      RequestEntry(state: SyncState.received, remote: RemoteRequest.fromJson(requestDoc(id: 'r2', mine: false))),
    ]);
    await tester.tap(find.byKey(const Key('problem')));
    await tester.pumpAndSettle();
    expect(find.text('No cement'), findsOneWidget);
    await tester.tap(find.byKey(const Key('problem-submit')));
    await tester.pumpAndSettle();
    expect(api.calls.single, 'problem:t1:materials:No cement:null:null');
  });

  testWidgets('a leader checks reported work; the office still approves', (tester) async {
    api.view = viewOf([taskDoc(role: 'leader', status: 'reported_done', canCheck: true)]);
    await openTaskSheet(tester);
    expect(find.text('To check'), findsOneWidget);
    expect(find.byKey(const Key('ack')), findsNothing, reason: 'a leader not on the task does not acknowledge');
    await tester.tap(find.byKey(const Key('check')));
    await tester.pumpAndSettle();
    expect(find.text('Your check is recorded. The office still gives the final approval.'), findsOneWidget);
    await tester.tap(find.byKey(const Key('note-submit')));
    await tester.pumpAndSettle();
    expect(api.calls.single, 'check:t1:');
  });

  testWidgets('pending and refused actions are shown on the task, never as sent', (tester) async {
    api.view = viewOf([taskDoc(ackVersion: 1)],
        pending: [anOp(WpOpKind.blocker)], failed: [anOp(WpOpKind.start, error: 'notAcknowledged')]);
    await openTaskSheet(tester);
    // The sheet's body is a lazy list: scroll the line into view first.
    await tester.scrollUntilVisible(find.text('Problem report · Pending sync'), 100, scrollable: find.byType(Scrollable).first);
    expect(find.text('Problem report · Pending sync'), findsOneWidget);
    expect(find.text('Start work: This was not accepted.'), findsOneWidget);
    expect(find.textContaining('The office changed this task. Read the new version'), findsOneWidget);
    await tester.ensureVisible(find.text('Dismiss · Isara'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Dismiss · Isara'));
    await tester.pumpAndSettle();
    expect(api.calls, ['dismiss:op-start']);
  });

  testWidgets('a leader proposes a task; nothing is live until the office publishes it', (tester) async {
    api.view = WorkPlanView(proposals: [
      WpProposal.fromJson(proposalDoc(id: 'p1', status: 'declined', reason: 'Already planned')),
    ]);
    await openProposals(tester);
    expect(find.text('Declined'), findsOneWidget);
    expect(find.text('Office: Already planned'), findsOneWidget);
    await tester.tap(find.byKey(const Key('propose')));
    await tester.pumpAndSettle();
    expect(tester.widget<WmSheetButton>(find.byKey(const Key('propose-send'))).onPressed, isNull);
    await tester.tap(find.byKey(const Key('propose-destination')));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Barlin Residence · Main Contract').last);
    await tester.pumpAndSettle();
    await tester.enterText(find.byKey(const Key('propose-title')), 'Fix the gate');
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('propose-send')));
    await tester.pumpAndSettle();
    expect(api.calls.single, 'propose:tm1:f1:Fix the gate:');
    expect(find.byKey(const Key('propose')), findsOneWidget, reason: 'back on the list');
  });

  testWidgets('Propose a task is a page: round back button, Send to the office pinned in the footer', (tester) async {
    await openProposals(tester);
    await tester.tap(find.byKey(const Key('propose')));
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('wm-page-back')), findsOneWidget);
    final screen = tester.view.physicalSize / tester.view.devicePixelRatio;
    final send = tester.getRect(find.byKey(const Key('propose-send')));
    expect(send.bottom, greaterThan(screen.height - 140), reason: 'Send sits in the pinned footer');
    expect(find.text('Send to the office'), findsOneWidget);
  });

  testWidgets('a worker who leads no team is told, not shown an empty form', (tester) async {
    api.choicesResult = const WpChoices(teams: [], destinations: [barlin]);
    await openProposals(tester);
    await tester.tap(find.byKey(const Key('propose')));
    await tester.pumpAndSettle();
    expect(find.text('You are not leading a team right now, so you cannot propose tasks.'), findsOneWidget);
  });

  testWidgets('My proposals is a sheet: key, title, Propose a task full width, green, with a plus', (tester) async {
    await openProposals(tester);
    expect(find.byKey(const Key('proposals-sheet')), findsOneWidget);
    expect(find.text('My proposals'), findsOneWidget);
    final button = find.byKey(const Key('propose'));
    expect(tester.widget(button), isA<WmSheetButton>());
    expect(find.descendant(of: button, matching: find.byIcon(Icons.add)), findsOneWidget);
    expect(find.descendant(of: button, matching: find.text('Propose a task')), findsOneWidget);
    final sheet = tester.getRect(find.byKey(const Key('proposals-sheet')));
    expect(tester.getSize(button).width, closeTo(sheet.width - 40, 1), reason: 'full width inside the sheet padding');
    expect(find.text('The office reviews each proposal. Nothing reaches the team until the office publishes it.'), findsOneWidget);
    await tester.tap(find.byKey(const Key('wm-sheet-close')));
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('proposals-sheet')), findsNothing);
  });

  testWidgets('a leader opens My proposals from the pill on My Work', (tester) async {
    await open(tester, MyWorkScreen(controller: controller, services: services, isLeader: true));
    await tester.ensureVisible(find.byKey(const Key('open-proposals')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('open-proposals')));
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('proposals-sheet')), findsOneWidget);
  });

  testWidgets('a sent proposal shows in the sheet, with its state, when the form closes', (tester) async {
    api.view = WorkPlanView(proposals: [
      WpProposal.fromJson(proposalDoc(id: 'p2', status: 'published')),
    ]);
    await openProposals(tester);
    expect(find.byKey(const Key('proposal-p2')), findsOneWidget);
    expect(find.text('If you are on it, it is in My Work.'), findsOneWidget);
  });
}
