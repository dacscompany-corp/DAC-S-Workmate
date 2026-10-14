import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:workmate/requests/data/requests_api.dart';
import 'package:workmate/requests/domain/remote_request.dart';
import 'package:workmate/requests/domain/request_status.dart';
import 'package:workmate/ui/theme.dart';
import 'package:workmate/workplan/data/workplan_api.dart';
import 'package:workmate/workplan/domain/wp_op.dart';
import 'package:workmate/workplan/domain/wp_rules.dart';
import 'package:workmate/workplan/domain/wp_task.dart';
import 'package:workmate/workplan/ui/my_work_controller.dart';
import 'package:workmate/workplan/ui/my_work_screen.dart';
import 'package:workmate/workplan/ui/proposals_screen.dart';
import 'package:workmate/workplan/ui/task_screen.dart';
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

  testWidgets('My Work: sections, what needs the worker first, notes; no proposals for a worker', (tester) async {
    api.view = viewOf([
      taskDoc(id: 't1', title: 'Skim coat', ackVersion: null),
      taskDoc(id: 't2', title: 'Cabinets', ackVersion: 1, start: '2026-10-20', end: '2026-10-21'),
      taskDoc(id: 't3', title: 'Garage', ackVersion: 1, blocked: true),
    ]);
    await open(tester, MyWorkScreen(controller: controller, services: services, isLeader: false));
    expect(find.text('TODAY · 1'), findsOneWidget);
    expect(find.text('UPCOMING · 1'), findsOneWidget);
    expect(find.text('WAITING · 1'), findsOneWidget);
    expect(find.text('New'), findsOneWidget);
    expect(find.text('Meeting notes (1)'), findsOneWidget);
    expect(find.byKey(const Key('open-proposals')), findsNothing);
    await tester.tap(find.byKey(const Key('open-notes')));
    await tester.pumpAndSettle();
    expect(find.text('Skim coat first, then cabinets.'), findsOneWidget);
  });

  testWidgets('a changed task says what changed; "I\'ve read this" is the first thing to do', (tester) async {
    api.view = viewOf([
      taskDoc(version: 2, ackVersion: 1, history: [
        {'id': 5, 'kind': 'revised', 'note': 'Changed: planned dates', 'by': 'Office', 'at': '2026-10-14T01:00:00+00:00'},
      ]),
    ]);
    await open(tester, TaskScreen(controller: controller, services: services, taskId: 't1'));
    expect(find.text('Changed'), findsOneWidget);
    expect(find.text('The office changed this task. Read it again.'), findsOneWidget);
    expect(find.text('Changed: planned dates'), findsWidgets);
    expect(tester.widget<FilledButton>(find.byKey(const Key('start'))).onPressed, isNull);
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
    await open(tester, TaskScreen(controller: controller, services: services, taskId: 't1'));
    expect(tester.widget<FilledButton>(find.byKey(const Key('start'))).onPressed, isNull);
    expect(find.textContaining('must be cleared by the office first'), findsOneWidget);
    expect(find.text('Materials: No cement'), findsOneWidget);
    expect(find.text('Earlier task: Wall prep'), findsOneWidget);
    expect(find.byKey(const Key('problem')), findsOneWidget, reason: 'problems can still be reported');
  });

  testWidgets('Start, then progress with a photo, then report done', (tester) async {
    api.view = viewOf([taskDoc(ackVersion: 1)]);
    await open(tester, TaskScreen(controller: controller, services: services, taskId: 't1'));
    await tester.tap(find.byKey(const Key('start')));
    await tester.pumpAndSettle();
    expect(api.calls, ['start:t1']);

    await tester.tap(find.byKey(const Key('progress')));
    await tester.pumpAndSettle();
    expect(tester.widget<FilledButton>(find.byKey(const Key('note-submit'))).onPressed, isNull, reason: 'a note is required');
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

  testWidgets('backing out of a form deletes the photo taken there', (tester) async {
    api.view = viewOf([taskDoc(ackVersion: 1, status: 'in_progress')]);
    await open(tester, TaskScreen(controller: controller, services: services, taskId: 't1'));
    await tester.tap(find.byKey(const Key('progress')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('add-photo')));
    await tester.pumpAndSettle();
    await tester.pageBack();
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
    await open(tester, TaskScreen(controller: controller, services: services, taskId: 't1', onMakeRequest: () => madeRequest++));
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

  testWidgets('a leader checks reported work; the office still approves', (tester) async {
    api.view = viewOf([taskDoc(role: 'leader', status: 'reported_done', canCheck: true)]);
    await open(tester, TaskScreen(controller: controller, services: services, taskId: 't1'));
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
    await open(tester, TaskScreen(controller: controller, services: services, taskId: 't1'));
    expect(find.text('Problem report · Pending sync'), findsOneWidget);
    expect(find.text('Start work: This was not accepted.'), findsOneWidget);
    expect(find.textContaining('The office changed this task. Read the new version'), findsOneWidget);
    await tester.tap(find.text('Dismiss · Isara'));
    await tester.pumpAndSettle();
    expect(api.calls, ['dismiss:op-start']);
  });

  testWidgets('a leader proposes a task; nothing is live until the office publishes it', (tester) async {
    api.view = WorkPlanView(proposals: [
      WpProposal.fromJson(proposalDoc(id: 'p1', status: 'declined', reason: 'Already planned')),
    ]);
    await open(tester, ProposalsScreen(controller: controller));
    expect(find.text('Declined'), findsOneWidget);
    expect(find.text('Office: Already planned'), findsOneWidget);
    await tester.tap(find.byKey(const Key('propose')));
    await tester.pumpAndSettle();
    expect(tester.widget<FilledButton>(find.byKey(const Key('propose-send'))).onPressed, isNull);
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

  testWidgets('a worker who leads no team is told, not shown an empty form', (tester) async {
    api.choicesResult = const WpChoices(teams: [], destinations: [barlin]);
    await open(tester, ProposalsScreen(controller: controller));
    await tester.tap(find.byKey(const Key('propose')));
    await tester.pumpAndSettle();
    expect(find.text('You are not leading a team right now, so you cannot propose tasks.'), findsOneWidget);
  });
}
