import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:workmate/attendance/attendance_services.dart';
import 'package:workmate/attendance/sync/queue_settled.dart';
import 'package:workmate/auth/worker_profile.dart';
import 'package:workmate/profile/account_services.dart';
import 'package:workmate/requests/compose/compose_screen.dart';
import 'package:workmate/requests/data/requests_api.dart';
import 'package:workmate/requests/detail/request_sheet.dart';
import 'package:workmate/requests/domain/remote_request.dart';
import 'package:workmate/requests/domain/request_draft.dart';
import 'package:workmate/requests/domain/request_status.dart';
import 'package:workmate/requests/requests_services.dart';
import 'package:workmate/tools/data/tools_saved_copy.dart';
import 'package:workmate/tools/domain/tool_submission.dart';
import 'package:workmate/tools/tools_services.dart';
import 'package:workmate/tools/ui/tools_screen.dart';
import 'package:workmate/ui/home_shell.dart';
import 'package:workmate/ui/theme.dart';
import 'package:workmate/workplan/data/workplan_api.dart';
import 'package:workmate/workplan/domain/wp_op.dart';
import 'package:workmate/workplan/domain/wp_rules.dart';
import 'package:workmate/workplan/ui/my_work_screen.dart';
import 'package:workmate/workplan/ui/proposals_screen.dart';
import 'package:workmate/workplan/ui/task_sheet.dart';
import 'package:workmate/workplan/workplan_services.dart';

import '../attendance/fakes.dart';
import '../requests/domain/request_models_test.dart' show requestDoc;
import '../requests/request_fakes.dart';
import '../tools/tool_fakes.dart';
import '../workplan/workplan_fakes.dart';

/// Animations off (the phone's "remove animations" setting): a waiting
/// badge's blinking dot then never holds pumpAndSettle open.
Widget still(Widget w) => MaterialApp(
      theme: workMateTheme(),
      builder: (context, child) => MediaQuery(data: MediaQuery.of(context).copyWith(disableAnimations: true), child: child!),
      home: w,
    );

const juan = WorkerProfile(id: 'u1', displayName: 'Juan dela Cruz', position: 'Mason', workerNo: 42, role: 'worker');
const ramon = WorkerProfile(id: 'u5', displayName: 'Ramon Santos', position: 'Mason', workerNo: 5, role: 'teamLeader');

FakeRequestsApi requestsWith({List<RequestEntry> entries = const [], List<RequestDraft> drafts = const []}) {
  final api = FakeRequestsApi()..view = RequestsView(entries: entries);
  for (final d in drafts) {
    api.savedDrafts[d.id] = d;
  }
  return api;
}

RequestEntry toFix() => RequestEntry(state: SyncState.needsResolution, remote: RemoteRequest.fromJson(requestDoc()));
RequestDraft aDraft() => RequestDraft(id: 'd1', createdAt: DateTime.utc(2026, 11, 11), destination: site, lines: [DraftLine.fromCatalog('l1', pipe)]);

/// A My Work action on task t1: refused by the office, or still waiting for signal.
WpOp _op(WpOpKind kind, {bool refused = true}) => WpOp(
      opId: 'op1',
      workerId: 'u1',
      kind: kind,
      createdAt: DateTime.utc(2026, 11, 11),
      taskId: 't1',
      lastError: refused ? 'NOT_ALLOWED' : null,
      failedPermanently: refused,
    );

void main() {
  late FakeAttendance attendance;
  late QueueSettled settled;

  setUp(() {
    attendance = FakeAttendance();
    settled = QueueSettled();
  });

  Future<void> showShell(WidgetTester tester,
      {WorkerProfile who = juan, FakeWorkPlanApi? work, FakeRequestsApi? requests, ToolsServices? tools, bool requestsFailed = false, bool workPlanFailed = false}) async {
    useTallPhone(tester);
    await tester.pumpWidget(still(HomeShell(
      worker: who,
      versionName: '0.12.0',
      onSignOut: () async {},
      services: AttendanceServices(
        attendance: attendance,
        device: FakeDevice(),
        scheduler: FakeScheduler(),
        trustedNow: () async => null,
        photoUrl: (_) async => null,
        openSettings: (_) async {},
        cameraStep: (context, args) => const Text('camera'),
        queueSettled: settled,
      ),
      account: AccountServices(changePassword: (_) async {}, termsAcceptedAt: () async => null),
      workPlan: work == null ? null : WorkPlanServices(api: work, takePhoto: (_) async => null),
      requests: requests == null ? null : RequestsServices(api: requests, takePhoto: (_) async => null),
      tools: tools,
      requestsFailedToStart: requestsFailed,
      workPlanFailedToStart: workPlanFailed,
    )));
    await tester.pumpAndSettle();
  }

  Future<void> showThree(WidgetTester tester) => showShell(tester,
      work: FakeWorkPlanApi()..view = viewWithUnread(), requests: requestsWith(entries: [toFix()], drafts: [aDraft()]));

  testWidgets('a new task, a request to fix and a draft: three rows, each with its own button, and red numbers', (tester) async {
    await showThree(tester);
    expect(find.descendant(of: find.byKey(const Key('needs-count')), matching: find.text('3')), findsOneWidget);
    expect(find.byKey(const Key('needs-read-t1')), findsOneWidget);
    expect(find.byKey(const Key('needs-fixRequest-r1')), findsOneWidget);
    expect(find.byKey(const Key('needs-finishDraft-d1')), findsOneWidget);
    expect(find.descendant(of: find.byKey(const Key('my-work-badge')), matching: find.text('1')), findsOneWidget);
    expect(find.descendant(of: find.byKey(const Key('requests-badge')), matching: find.text('1')), findsOneWidget);
  });

  testWidgets('Read opens that task', (tester) async {
    await showThree(tester);
    await tester.tap(find.byKey(const Key('needs-read-t1')));
    await tester.pumpAndSettle();
    expect(find.byType(TaskSheet), findsOneWidget);
  });

  testWidgets('Fix opens that request', (tester) async {
    await showThree(tester);
    await tester.tap(find.byKey(const Key('needs-fixRequest-r1')));
    await tester.pumpAndSettle();
    expect(find.byType(RequestSheet), findsOneWidget);
  });

  testWidgets('Finish opens the draft', (tester) async {
    await showThree(tester);
    await tester.tap(find.byKey(const Key('needs-finishDraft-d1')));
    await tester.pumpAndSettle();
    expect(find.byType(ComposeScreen), findsOneWidget);
  });

  testWidgets('a worker: New request is a shortcut, and opens a new request', (tester) async {
    await showShell(tester, work: FakeWorkPlanApi(), requests: requestsWith());
    expect(find.byKey(const Key('shortcut-proposals')), findsNothing);
    await tester.tap(find.byKey(const Key('shortcut-new-request')));
    await tester.pumpAndSettle();
    expect(find.byType(ComposeScreen), findsOneWidget);
  });

  testWidgets('a team leader: a Check row, and My proposals instead of New request', (tester) async {
    final work = FakeWorkPlanApi()
      ..view = WorkPlanView(entries: [WpEntry(task: task0(taskDoc(id: 't3', title: 'Tiles', status: 'reported_done', canCheck: true, ackVersion: 1)))]);
    await showShell(tester, who: ramon, work: work, requests: requestsWith());
    expect(find.byKey(const Key('needs-check-t3')), findsOneWidget);
    expect(find.byKey(const Key('shortcut-new-request')), findsNothing);
    await tester.tap(find.byKey(const Key('shortcut-proposals')));
    await tester.pumpAndSettle();
    expect(find.byType(ProposalsScreen), findsOneWidget);
  });

  testWidgets('a Time In still on the phone: "1 not sent yet", never "All sent"', (tester) async {
    attendance.waiting = 1;
    await showShell(tester, work: FakeWorkPlanApi(), requests: requestsWith());
    expect(find.text('1 not sent yet'), findsOneWidget);
    expect(find.text('All sent'), findsNothing);
    attendance.waiting = 0;
    settled.fire();
    await tester.pumpAndSettle();
    expect(find.text('All sent'), findsOneWidget);
  });

  testWidgets('nothing waiting and every source read: All sent, and all caught up', (tester) async {
    await showShell(tester, work: FakeWorkPlanApi(), requests: requestsWith());
    expect(find.text('All sent'), findsOneWidget);
    expect(find.text('You are all caught up'), findsOneWidget);
  });

  testWidgets('no signal and no saved copy for My Work: never caught up, no badge — and Time In works', (tester) async {
    await showShell(tester, work: FakeWorkPlanApi()..view = WorkPlanView(error: Exception('no signal')), requests: requestsWith());
    expect(find.text('You are all caught up'), findsNothing);
    expect(find.text('NEEDS YOU'), findsNothing);
    expect(find.text('All sent'), findsNothing);
    expect(find.byKey(const Key('hero-time-in')), findsOneWidget);
  });

  testWidgets('Meeting notes open from Home as a sheet', (tester) async {
    await showShell(tester, work: FakeWorkPlanApi(), requests: requestsWith());
    await tester.tap(find.byKey(const Key('shortcut-notes')));
    await tester.pumpAndSettle();
    expect(find.text('Skim coat first, then cabinets.'), findsOneWidget);
    await tester.binding.handlePopRoute();
    await tester.pumpAndSettle();
    expect(find.text('Skim coat first, then cabinets.'), findsNothing);
  });

  Future<ToolsServices> toolsWith(List<ToolSubmission> stored) async {
    SharedPreferences.resetStatic();
    SharedPreferences.setMockInitialValues({});
    final store = MemoryToolPendingStore();
    await store.save(stored);
    return ToolsServices(remote: FakeToolsRemote(), store: store, saved: ToolsSavedCopy(await SharedPreferences.getInstance()));
  }

  ToolSubmission unresolvedTool() => ToolSubmission.create(
        opId: 'op7',
        userId: 'u1',
        write: ToolWrite.giveBack,
        params: {'p_op': 'op7'},
        summary: 'Return TOOL-0001 · Grinder',
        now: DateTime.utc(2026, 11, 11),
      );

  testWidgets('the See row (a refused My Work action) opens the My Work tab', (tester) async {
    final work = FakeWorkPlanApi()
      ..view = WorkPlanView(entries: [
        WpEntry(task: task0(taskDoc(id: 't1', title: 'Skim coat')), failedOps: [_op(WpOpKind.start)]),
      ]);
    await showShell(tester, work: work, requests: requestsWith());
    expect(find.byKey(const Key('needs-notAccepted-op1')), findsOneWidget);
    await tester.tap(find.byKey(const Key('needs-notAccepted-op1')));
    await tester.pumpAndSettle();
    expect(find.byType(MyWorkScreen), findsOneWidget);
  });

  testWidgets('the leader\'s Check row opens that task', (tester) async {
    final work = FakeWorkPlanApi()
      ..view = WorkPlanView(entries: [WpEntry(task: task0(taskDoc(id: 't3', title: 'Tiles', status: 'reported_done', canCheck: true, ackVersion: 1)))]);
    await showShell(tester, who: ramon, work: work, requests: requestsWith());
    await tester.tap(find.byKey(const Key('needs-check-t3')));
    await tester.pumpAndSettle();
    expect(find.byType(TaskSheet), findsOneWidget);
  });

  testWidgets('an unresolved tool record: its Check row opens Tools, with no build-time notification', (tester) async {
    await showShell(tester, tools: await toolsWith([unresolvedTool()]));
    expect(find.text('1 not sent yet'), findsOneWidget);
    await tester.tap(find.byKey(const Key('needs-toolUnresolved-op7')));
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);
    expect(find.byType(ToolsScreen), findsOneWidget);
  });

  group('the badge counts what is still on the phone, each alone', () {
    testWidgets('a request in Pending sync', (tester) async {
      await showShell(tester,
          work: FakeWorkPlanApi(), requests: requestsWith(entries: [RequestEntry(state: SyncState.pending, remote: RemoteRequest.fromJson(requestDoc()))]));
      expect(find.text('1 not sent yet'), findsOneWidget);
      expect(find.text('All sent'), findsNothing);
    });

    testWidgets('a My Work action waiting', (tester) async {
      final work = FakeWorkPlanApi()
        ..view = WorkPlanView(entries: [
          WpEntry(task: task0(taskDoc(id: 't1', ackVersion: 1)), pendingOps: [_op(WpOpKind.progress, refused: false)]),
        ]);
      await showShell(tester, work: work, requests: requestsWith());
      expect(find.text('1 not sent yet'), findsOneWidget);
      expect(find.text('All sent'), findsNothing);
    });

    testWidgets('an unresolved tool record', (tester) async {
      await showShell(tester, tools: await toolsWith([unresolvedTool()]));
      expect(find.text('1 not sent yet'), findsOneWidget);
      expect(find.text('All sent'), findsNothing);
    });
  });

  testWidgets('"Show 1 more" stays open across a Home refresh where today() is slow', (tester) async {
    final work = FakeWorkPlanApi()
      ..view = WorkPlanView(
        entries: [for (var i = 1; i <= 6; i++) WpEntry(task: task0(taskDoc(id: 't$i', title: 'Task $i')))],
        fetchedAt: DateTime.utc(2026, 11, 11),
      );
    await showShell(tester, work: work, requests: requestsWith());
    expect(find.text('Task 6', skipOffstage: false), findsNothing);
    await tester.ensureVisible(find.byKey(const Key('needs-more')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('needs-more')));
    await tester.pumpAndSettle();
    expect(find.text('Task 6', skipOffstage: false), findsOneWidget);

    attendance.todayGate = Completer<void>();
    settled.fire();
    await tester.pump();
    attendance.todayGate!.complete();
    await tester.pumpAndSettle();
    expect(find.text('Task 6', skipOffstage: false), findsOneWidget, reason: 'the refresh must not fold the list back');
  });

  testWidgets('attendance, This week and the bar are where they were', (tester) async {
    await showThree(tester);
    expect(find.byKey(const Key('hero-time-in')), findsOneWidget);
    // Below the three rows and the shortcuts, so the list builds it only once scrolled to.
    await tester.scrollUntilVisible(find.text('THIS WEEK'), 300);
    expect(find.text('THIS WEEK'), findsOneWidget);
    expect(find.byKey(const Key('wm-nav-bar')), findsOneWidget);
    for (final tab in ['Home', 'My Work', 'Requests', 'History', 'Profile']) {
      expect(find.descendant(of: find.byType(NavigationBar), matching: find.text(tab)), findsOneWidget);
    }
  });
  testWidgets('Requests could not start on this phone: no badge, and never "caught up" — Time In still works', (tester) async {
    await showShell(tester, work: FakeWorkPlanApi(), requestsFailed: true);
    expect(find.text('All sent'), findsNothing);
    expect(find.textContaining('not sent yet'), findsNothing);
    expect(find.text('You are all caught up'), findsNothing);
    expect(find.byKey(const Key('hero-time-in')), findsOneWidget);
  });

  testWidgets('My Work could not start on this phone: no badge, and never "caught up"', (tester) async {
    await showShell(tester, requests: requestsWith(), workPlanFailed: true);
    expect(find.text('All sent'), findsNothing);
    expect(find.text('You are all caught up'), findsNothing);
    expect(find.byKey(const Key('hero-time-in')), findsOneWidget);
  });

  testWidgets('a module that is simply not set up (no failure) still counts as off', (tester) async {
    await showShell(tester, work: FakeWorkPlanApi());
    expect(find.text('All sent'), findsOneWidget);
    expect(find.text('You are all caught up'), findsOneWidget);
  });
}
