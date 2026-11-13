import 'dart:async';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:workmate/tools/data/tool_submitter.dart';
import 'package:workmate/tools/data/tools_remote.dart';
import 'package:workmate/tools/data/tools_saved_copy.dart';
import 'package:workmate/tools/domain/tool_models.dart';
import 'package:workmate/tools/ui/tools_controller.dart';
import 'package:workmate/tools/ui/tools_screen.dart';
import 'package:workmate/ui/theme.dart';

import '../attendance/fakes.dart' show useTallPhone;
import 'server_answers.dart';
import 'tool_fakes.dart';

Widget wrap(Widget w) => MaterialApp(theme: workMateTheme(), home: w);

final amy = TeamChoices.fromJson(answerDoc(choicesJson)).members[0];
final ben = TeamChoices.fromJson(answerDoc(choicesJson)).members[1];
final house = TeamChoices.fromJson(answerDoc(choicesJson)).projects.single;
final found = FoundTool.fromJson(answerDoc(findJson));
final line = answerRows(requestLinesJson).map(ToolRequestLine.fromJson).single;

/// Every write the phone sent carries exactly 0111's parameters.
void sameParams((String, Map<String, dynamic>, String) w) =>
    expect(w.$2.keys.toSet(), SupabaseToolsRemote.calls[w.$1]!.toSet(), reason: w.$1);

void main() {
  late FakeToolsRemote remote;
  late MemoryToolPendingStore store;
  late ToolsController controller;
  late ToolSubmitter submitter;

  setUp(() {
    remote = FakeToolsRemote();
    store = MemoryToolPendingStore();
  });

  Future<void> showTools(WidgetTester tester, {bool leader = false, ToolsSavedCopy? saved, String user = 'u1'}) async {
    useTallPhone(tester);
    controller = ToolsController(remote: remote, userId: user, isLeader: leader, saved: saved);
    submitter = ToolSubmitter(remote: remote, store: store);
    await submitter.load(user);
    await controller.refresh();
    await tester.pumpWidget(const SizedBox()); // a fresh app: any earlier sheet is gone
    await tester.pumpWidget(wrap(Builder(
      builder: (context) => Center(
        child: ElevatedButton(
          key: const Key('open-tools'),
          onPressed: () => showToolsSheet(context, controller, submitter),
          child: const Text('Open tools'),
        ),
      ),
    )));
    await tester.tap(find.byKey(const Key('open-tools')));
    await tester.pumpAndSettle();
  }

  Future<void> tapKey(WidgetTester tester, String key) async {
    await tester.ensureVisible(find.byKey(Key(key)));
    await tester.pumpAndSettle(); // laid out where it scrolled to, before the tap
    await tester.tap(find.byKey(Key(key)));
    await tester.pumpAndSettle();
  }

  Future<void> choose(WidgetTester tester, String dropdown, String item) async {
    await tapKey(tester, dropdown);
    await tester.tap(find.text(item).last);
    await tester.pumpAndSettle();
  }

  Future<void> team(WidgetTester tester) async {
    await tester.tap(find.text('Team (4)'));
    await tester.pumpAndSettle();
  }

  Future<void> openTeamTool(WidgetTester tester, PhoneTool t) async {
    await team(tester);
    await tapKey(tester, 'tool-${t.id}');
  }

  // ── Mine (every worker) ─────────────────────────────────────────

  testWidgets('Mine: each tool with its number, project and days; lost ones say so; one opens its history', (tester) async {
    await showTools(tester);
    expect(find.text('TOOL-0001 · Grinder'), findsOneWidget);
    expect(find.text('Blue handle'), findsOneWidget);
    expect(find.text('House · since today'), findsWidgets);
    expect(find.text("You reported: It's broken"), findsOneWidget);
    expect(find.text('Reported lost — waiting for the owner.'), findsOneWidget);
    expect(find.byKey(const Key('tools-parts')), findsNothing, reason: 'Team is a leader\'s');
    await tapKey(tester, 'tool-${remote.mineAnswer.first.id}');
    expect(find.text('With Amy (W-0001)'), findsOneWidget);
    expect(find.text('Issued'), findsOneWidget, reason: 'its history while they had it');
    expect(find.byKey(const Key('tool-report')), findsOneWidget);
    expect(find.byKey(const Key('tool-handover')), findsNothing, reason: 'a worker hands nothing over');
  });

  testWidgets('Report a problem: choose and send — recorded once, with exactly 0111\'s parameters', (tester) async {
    await showTools(tester);
    final t = remote.mineAnswer.first;
    await tapKey(tester, 'tool-${t.id}');
    await tapKey(tester, 'tool-report');
    await tapKey(tester, 'tool-send');
    expect(find.text("Choose what's wrong."), findsOneWidget, reason: 'checked on the phone first');
    expect(remote.attempts, isEmpty);
    await tapKey(tester, 'report-dont_have');
    await tester.enterText(find.byKey(const Key('tool-note')), 'Left at the old site');
    await tapKey(tester, 'tool-send');
    final w = remote.writes.single;
    expect([w.$1, w.$2['p_tool'], w.$2['p_kind'], w.$2['p_note']], ['tl_report_problem', t.id, 'dont_have', 'Left at the old site']);
    sameParams(w);
    expect(find.byKey(const Key('tool-recorded')), findsOneWidget);
    expect(find.text('Recorded. · Naitala na.'), findsOneWidget, reason: 'visible while the sheet is open');
    expect(find.byKey(const Key('tools-sheet')), findsOneWidget, reason: 'back on the Tools sheet');
  });

  testWidgets('Report a problem twice: the server\'s "Already reported" is shown, nothing changes', (tester) async {
    await showTools(tester);
    await tapKey(tester, 'tool-${remote.mineAnswer.first.id}');
    await tapKey(tester, 'tool-report');
    await tapKey(tester, 'report-broken');
    remote.failNextWrite = refusal('ALREADY_REPORTED');
    await tapKey(tester, 'tool-send');
    expect(find.text('Already reported — the office will check it.'), findsOneWidget);
    expect(submitter.unresolved, isEmpty, reason: 'a clear "no" settles it');
  });

  testWidgets('Report, the answer lost: the form locks; Send again records it once', (tester) async {
    await showTools(tester);
    await tapKey(tester, 'tool-${remote.mineAnswer.first.id}');
    await tapKey(tester, 'tool-report');
    await tapKey(tester, 'report-broken');
    remote.loseNextAnswer = TimeoutException('lost after commit');
    await tapKey(tester, 'tool-send');
    expect(find.byKey(const Key('unsure-send-again')), findsOneWidget);
    expect(find.byKey(const Key('tool-send')), findsNothing, reason: 'locked: only Send again, Check or Cancel');
    expect(tester.widget<TextField>(find.byKey(const Key('tool-note'))).enabled, isFalse);
    await tapKey(tester, 'unsure-send-again');
    expect(remote.writes, hasLength(1), reason: 'recorded once');
    expect(remote.attempts.map((a) => a.$2).toSet(), hasLength(1), reason: 'sent again byte for byte');
    expect(find.byKey(const Key('tool-recorded')), findsOneWidget);
  });

  // ── Team (a leader) ─────────────────────────────────────────────

  testWidgets('Issue: found by number and confirmed; a person, a project and a request line — recorded with 0111\'s parameters',
      (tester) async {
    await showTools(tester, leader: true);
    await team(tester);
    await tapKey(tester, 'tools-issue');
    await tapKey(tester, 'tool-send');
    expect(find.text("Type the tool's number and press Find."), findsWidgets);
    await tester.enterText(find.byKey(const Key('issue-number')), 'tool-0003');
    await tapKey(tester, 'issue-find');
    expect(remote.finds, ['tool-0003']);
    expect(find.text('TOOL-0003 · Grinder'), findsOneWidget);
    expect(find.text('Spare'), findsOneWidget);
    await choose(tester, 'issue-person', ben.name);
    await choose(tester, 'issue-project', house.name);
    await tapKey(tester, 'tool-send');
    expect(find.text('Check the tool in your hand, then tick the box to confirm it.'), findsOneWidget, reason: 'the identity is confirmed first');
    expect(remote.attempts, isEmpty);
    await tapKey(tester, 'issue-confirm');
    await choose(tester, 'issue-request', 'Grinder — Amy · 1 pc still to fill');
    await tapKey(tester, 'tool-send');
    final w = remote.writes.single;
    expect(w.$1, 'tl_team_issue');
    expect(w.$2['p_body'],
        {'tool_id': found.id, 'holder_id': ben.id, 'folder_id': house.folderId, 'request_line_id': line.lineId, 'note': ''});
    sameParams(w);
    expect(find.byKey(const Key('tool-recorded')), findsOneWidget);
  });

  testWidgets('Issue: a number that is not available gets one answer, and nothing about who has it', (tester) async {
    await showTools(tester, leader: true);
    await team(tester);
    await tapKey(tester, 'tools-issue');
    remote.foundAnswer = null;
    await tester.enterText(find.byKey(const Key('issue-number')), '2');
    await tapKey(tester, 'issue-find');
    expect(find.text('Not available to issue — check the number, or ask the office.'), findsOneWidget);
    expect(find.text('Ben (W-0002)'), findsNothing);
  });

  testWidgets('Issue, the answer lost: Check finds it recorded — the form closes, and it was issued once', (tester) async {
    await showTools(tester, leader: true);
    await team(tester);
    await tapKey(tester, 'tools-issue');
    await tester.enterText(find.byKey(const Key('issue-number')), '3');
    await tapKey(tester, 'issue-find');
    await tapKey(tester, 'issue-confirm');
    await choose(tester, 'issue-person', ben.name);
    await choose(tester, 'issue-project', house.name);
    remote.loseNextAnswer = const SocketException('lost after commit');
    await tapKey(tester, 'tool-send');
    expect(find.byKey(const Key('unsure-check')), findsOneWidget);
    expect(tester.widget<TextField>(find.byKey(const Key('issue-number'))).enabled, isFalse, reason: 'locked');
    await tapKey(tester, 'unsure-check');
    expect(remote.attempts, hasLength(1), reason: 'a check never sends');
    expect(remote.writes, hasLength(1));
    expect(find.byKey(const Key('tool-recorded')), findsOneWidget);
  });

  testWidgets('Hand over: the holder is not offered; the answer lost → Cancel it and change → cancelled for good, then a new Send',
      (tester) async {
    await showTools(tester, leader: true);
    final ben2 = remote.teamAnswer[1];
    await openTeamTool(tester, ben2);
    await tapKey(tester, 'tool-handover');
    await tapKey(tester, 'handover-person');
    expect(find.text(ben.name), findsNothing, reason: 'not to the person who has it');
    await tester.tap(find.text(amy.name).last);
    await tester.pumpAndSettle();
    remote.failNextWrite = TimeoutException('lost on the way');
    await tapKey(tester, 'tool-send');
    await tapKey(tester, 'unsure-cancel');
    expect(remote.cancelled, hasLength(1), reason: 'the server cancelled that id for good');
    expect(find.text('This record was cancelled — nothing was recorded. Change it if needed and send it as a new one.'), findsOneWidget);
    expect(find.byKey(const Key('tool-send')), findsOneWidget, reason: 'the fields are open again');
    await tapKey(tester, 'tool-send');
    final w = remote.writes.single;
    expect([w.$1, w.$2['p_body']['tool_id'], w.$2['p_body']['holder_id'], w.$2['p_body']['folder_id']],
        ['tl_team_handover', ben2.id, amy.id, ben2.folderId]);
    sameParams(w);
    expect(remote.attempts.map((a) => a.$1).toSet(), hasLength(2), reason: 'the new Send is a new operation');
  });

  testWidgets('A tool that needs repair is not handed over; Return is offered', (tester) async {
    // TOOL-0005: the server answers its page with the same row (no captured history).
    final raw = {...remote.teamAnswer[3].raw, 'condition': 'needs_repair'};
    remote.teamAnswer = [...remote.teamAnswer.take(3), PhoneTool.fromJson(raw)];
    await showTools(tester, leader: true);
    await openTeamTool(tester, remote.teamAnswer[3]);
    expect(find.text('Needs repair'), findsOneWidget);
    expect(find.byKey(const Key('tool-handover')), findsNothing);
    expect(find.byKey(const Key('tool-return')), findsOneWidget);
  });

  testWidgets('Return damaged beyond repair: the owner decides; recorded with its condition', (tester) async {
    await showTools(tester, leader: true);
    final t = remote.teamAnswer.first;
    await openTeamTool(tester, t);
    await tapKey(tester, 'tool-return');
    await tapKey(tester, 'tool-send');
    expect(find.text("Choose the tool's condition."), findsOneWidget);
    await tapKey(tester, 'return-damaged');
    expect(find.textContaining('the owner decides whether to retire it'), findsOneWidget);
    await tapKey(tester, 'tool-send');
    final w = remote.writes.single;
    expect([w.$1, w.$2['p_body']], ['tl_team_return', {'tool_id': t.id, 'condition': 'damaged', 'note': ''}]);
    sameParams(w);
  });

  testWidgets('Return, the answer lost and the form left: it waits at the top of Tools, nothing new starts; Send again there', (tester) async {
    await showTools(tester, leader: true);
    final t = remote.teamAnswer.first;
    await openTeamTool(tester, t);
    await tapKey(tester, 'tool-return');
    await tapKey(tester, 'return-good');
    remote.failNextWrite = TimeoutException('lost on the way');
    await tapKey(tester, 'tool-send');
    await tapKey(tester, 'unsure-check');
    expect(find.text('Not recorded yet — it may still arrive. Send it again, or cancel it.'), findsOneWidget);
    // Leave the form: back on the Tools sheet.
    await tester.pageBack();
    await tester.pumpAndSettle();
    expect(find.text('Returned TOOL-0001 Grinder from Amy (W-0001) — Good'), findsOneWidget, reason: 'it waits at the top');
    expect(find.byKey(const Key('tools-finish-first')), findsOneWidget);
    expect(tester.widget<FilledButton>(find.byKey(const Key('tools-issue'))).onPressed, isNull, reason: 'no new tool record meanwhile');
    await tapKey(tester, 'unsure-send-again');
    expect(remote.writes, hasLength(1));
    expect(find.byKey(const Key('tool-recorded')), findsOneWidget);
    expect(submitter.unresolved, isEmpty);
  });

  testWidgets('Undo: only where the server allows it; a reason is required; recorded', (tester) async {
    await showTools(tester, leader: true);
    await tester.tap(find.text('My records'));
    await tester.pumpAndSettle();
    final cannot = remote.recordsAnswer.firstWhere((r) => !r.canReverse);
    final can = remote.recordsAnswer.firstWhere((r) => r.canReverse);
    expect(find.byKey(Key('undo-${cannot.id}')), findsNothing);
    await tapKey(tester, 'undo-${can.id}');
    await tapKey(tester, 'tool-send');
    expect(find.text('Please give a reason.'), findsOneWidget);
    expect(remote.attempts, isEmpty);
    await tester.enterText(find.byKey(const Key('undo-reason')), 'Wrong person');
    await tapKey(tester, 'tool-send');
    final w = remote.writes.single;
    expect([w.$1, w.$2['p_record'], w.$2['p_reason']], ['tl_team_reverse', can.id, 'Wrong person']);
    sameParams(w);
  });

  /// Each form is a WmPage: a round back button, and Send pinned at the bottom of the screen.
  void expectPinnedSend(WidgetTester tester) {
    expect(find.byKey(const Key('wm-page-back')), findsOneWidget);
    final screen = tester.view.physicalSize / tester.view.devicePixelRatio;
    final send = tester.getRect(find.byKey(const Key('tool-send')));
    expect(send.bottom, greaterThan(screen.height - 140), reason: 'Send sits in the pinned footer');
    expect(send.bottom, lessThanOrEqualTo(screen.height));
  }

  testWidgets('every tool form is a page with Send pinned in the footer and a round back button', (tester) async {
    await showTools(tester, leader: true);
    // Report a problem (a tool held by the signed-in person: Mine).
    await tester.tap(find.text('Mine (2)'));
    await tester.pumpAndSettle();
    await tapKey(tester, 'tool-${remote.mineAnswer.first.id}');
    await tapKey(tester, 'tool-report');
    expectPinnedSend(tester);
    await tester.pageBack();
    await tester.pumpAndSettle();
    // Issue a tool.
    await team(tester);
    await tapKey(tester, 'tools-issue');
    expectPinnedSend(tester);
    await tester.pageBack();
    await tester.pumpAndSettle();
    // Hand over, then Return.
    await openTeamTool(tester, remote.teamAnswer[1]);
    await tapKey(tester, 'tool-handover');
    expectPinnedSend(tester);
    await tester.pageBack();
    await tester.pumpAndSettle();
    await tapKey(tester, 'tool-return');
    expectPinnedSend(tester);
    await tester.pageBack();
    await tester.pumpAndSettle();
    // Undo (the switch is at the top of the sheet's list: scroll back up to it).
    await tester.drag(find.byType(ListView).first, const Offset(0, 2000));
    await tester.pumpAndSettle();
    await tester.tap(find.text('My records'));
    await tester.pumpAndSettle();
    await tapKey(tester, 'undo-${remote.recordsAnswer.firstWhere((r) => r.canReverse).id}');
    expectPinnedSend(tester);
  });

  // ── The sheet itself ────────────────────────────────────────────

  testWidgets("a worker's own tool opens in place with Report a problem only", (tester) async {
    await showTools(tester);
    expect(find.byKey(const Key('tools-sheet')), findsOneWidget);
    expect(find.text('My tools'), findsOneWidget);
    await tapKey(tester, 'tool-${remote.mineAnswer.first.id}');
    expect(find.byKey(const Key('tool-report')), findsOneWidget);
    expect(find.byKey(const Key('tool-handover')), findsNothing);
    expect(find.byKey(const Key('tool-return')), findsNothing);
  });

  testWidgets("a leader's team tool in good condition: Hand over and Return", (tester) async {
    await showTools(tester, leader: true);
    await openTeamTool(tester, remote.teamAnswer.first);
    expect(find.byKey(const Key('tool-handover')), findsOneWidget);
    expect(find.byKey(const Key('tool-return')), findsOneWidget);
    expect(find.byKey(const Key('tool-report')), findsNothing);
  });

  testWidgets('a team tool needing repair: the note and Return, no Hand over', (tester) async {
    final raw = {...remote.teamAnswer[3].raw, 'condition': 'needs_repair'};
    remote.teamAnswer = [...remote.teamAnswer.take(3), PhoneTool.fromJson(raw)];
    await showTools(tester, leader: true);
    await openTeamTool(tester, remote.teamAnswer[3]);
    expect(find.textContaining('It needs repair, so it stays with them'), findsOneWidget);
    expect(find.byKey(const Key('tool-handover')), findsNothing);
    expect(find.byKey(const Key('tool-return')), findsOneWidget);
  });

  testWidgets('history rows appear after the card opens; not before', (tester) async {
    await showTools(tester);
    expect(find.text('Issued'), findsNothing);
    await tapKey(tester, 'tool-${remote.mineAnswer.first.id}');
    expect(find.text('History'), findsOneWidget);
    expect(find.text('Issued'), findsOneWidget);
  });

  testWidgets('history that cannot be read says so, in two languages', (tester) async {
    await showTools(tester);
    remote.failReads = const SocketException('no signal');
    await tapKey(tester, 'tool-${remote.mineAnswer.first.id}');
    expect(find.byKey(const Key('tool-history-failure')), findsOneWidget);
    expect(find.text('Its history needs signal.'), findsOneWidget);
  });

  testWidgets('opening a second card closes the first; tapping an open card closes it', (tester) async {
    await showTools(tester, leader: true);
    await tester.tap(find.byKey(const Key('tools-part-team')));
    await tester.pumpAndSettle();
    final a = remote.teamAnswer[0], b = remote.teamAnswer[1];
    await tapKey(tester, 'tool-${a.id}');
    expect(find.byKey(const Key('tool-return')), findsOneWidget);
    await tapKey(tester, 'tool-${b.id}');
    expect(find.byKey(const Key('tool-return')), findsOneWidget, reason: 'only one card is open');
    await tapKey(tester, 'tool-${b.id}');
    expect(find.byKey(const Key('tool-return')), findsNothing, reason: 'closed again');
  });

  testWidgets("the leader's switch shows the counts and changes the part", (tester) async {
    await showTools(tester, leader: true);
    expect(find.byKey(const Key('tools-part-mine')), findsOneWidget);
    expect(find.text('Mine (2)'), findsOneWidget);
    expect(find.text('Team (4)'), findsOneWidget);
    expect(find.text('My records'), findsOneWidget);
    expect(find.byKey(const Key('tools-issue')), findsNothing);
    await tester.tap(find.byKey(const Key('tools-part-team')));
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('tools-issue')), findsOneWidget);
    await tester.tap(find.byKey(const Key('tools-part-records')));
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('tools-issue')), findsNothing);
    expect(find.byKey(Key('undo-${remote.recordsAnswer.firstWhere((r) => r.canReverse).id}')), findsOneWidget);
  });

  testWidgets('the sheet closes with Back', (tester) async {
    await showTools(tester);
    await tester.binding.handlePopRoute(); // Android Back
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('tools-sheet')), findsNothing);
  });

  testWidgets("after a form records, the sheet reads again and re-reads the open card's history", (tester) async {
    await showTools(tester);
    final t = remote.mineAnswer.first;
    await tapKey(tester, 'tool-${t.id}');
    final before = remote.mineCalls;
    final details = remote.detailCalls;
    await tapKey(tester, 'tool-report');
    await tapKey(tester, 'report-broken');
    await tapKey(tester, 'tool-send');
    expect(remote.mineCalls, greaterThan(before), reason: 'the list was read again');
    expect(remote.detailCalls, details + 1, reason: 'the open tool itself was read again');
    expect(find.text('Recorded. · Naitala na.'), findsOneWidget);
    expect(find.text('Issued'), findsOneWidget, reason: 'history is still shown for the open card');
  });

  testWidgets('"Recorded." does not stay once another form is opened', (tester) async {
    await showTools(tester);
    final t = remote.mineAnswer.first;
    await tapKey(tester, 'tool-${t.id}');
    await tapKey(tester, 'tool-report');
    await tapKey(tester, 'report-broken');
    await tapKey(tester, 'tool-send');
    expect(find.byKey(const Key('tool-recorded')), findsOneWidget);
    await tapKey(tester, 'tool-report');
    await tester.pageBack();
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('tool-recorded')), findsNothing, reason: 'that form recorded nothing');
  });

  testWidgets('after a record, a re-read that fails shows no history from before it', (tester) async {
    await showTools(tester);
    final t = remote.mineAnswer.first;
    await tapKey(tester, 'tool-${t.id}');
    expect(find.text('Issued'), findsOneWidget);
    await tapKey(tester, 'tool-report');
    await tapKey(tester, 'report-broken');
    remote.failDetail = const SocketException('down');
    await tapKey(tester, 'tool-send');
    expect(find.byKey(const Key('tool-recorded')), findsOneWidget);
    expect(find.text('Issued'), findsNothing, reason: 'the old history is not shown as if it were current');
    expect(find.byKey(const Key('tool-history-failure')), findsOneWidget);
  });

  testWidgets('a refusal from the waiting box is shown pinned inside the sheet, in view', (tester) async {
    await showTools(tester, leader: true);
    await openTeamTool(tester, remote.teamAnswer.first);
    await tapKey(tester, 'tool-return');
    await tapKey(tester, 'return-good');
    remote.failNextWrite = TimeoutException('lost on the way');
    await tapKey(tester, 'tool-send');
    await tapKey(tester, 'unsure-check');
    await tester.pageBack();
    await tester.pumpAndSettle();
    await tapKey(tester, 'unsure-cancel');
    expect(find.byKey(const Key('tool-refused')), findsOneWidget);
    final screen = tester.view.physicalSize / tester.view.devicePixelRatio;
    final r = tester.getRect(find.byKey(const Key('tool-refused')));
    expect(r.bottom, lessThanOrEqualTo(screen.height));
    expect(r.top, greaterThan(screen.height - 220), reason: 'in the pinned footer');
  });

  testWidgets('Undo, the answer lost: Cancel it — nothing is recorded', (tester) async {
    await showTools(tester, leader: true);
    await tester.tap(find.text('My records'));
    await tester.pumpAndSettle();
    final can = remote.recordsAnswer.firstWhere((r) => r.canReverse);
    await tapKey(tester, 'undo-${can.id}');
    await tester.enterText(find.byKey(const Key('undo-reason')), 'Wrong person');
    remote.failNextWrite = TimeoutException('lost on the way');
    await tapKey(tester, 'tool-send');
    await tapKey(tester, 'unsure-cancel');
    expect([remote.writes, remote.cancelled.length, submitter.unresolved], [isEmpty, 1, isEmpty]);
  });

  testWidgets('The Team Leader role but no team led now: Team says so, and there is nothing to issue', (tester) async {
    remote.failTeam = refusal('NOT_LEADER');
    await showTools(tester, leader: true);
    await tester.tap(find.text('Team (0)'));
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('tools-not-leading')), findsOneWidget);
    expect(find.byKey(const Key('tools-issue')), findsNothing);
  });

  testWidgets('No signal: the saved copy shows with its time; another account sees none of it', (tester) async {
    // ignore: invalid_use_of_visible_for_testing_member
    SharedPreferences.resetStatic();
    SharedPreferences.setMockInitialValues({});
    final saved = ToolsSavedCopy(await SharedPreferences.getInstance());
    await showTools(tester, saved: saved);
    remote.failReads = const SocketException('no signal');
    await showTools(tester, saved: saved);
    expect(find.text('TOOL-0001 · Grinder'), findsOneWidget);
    expect(find.byKey(const Key('tools-saved-copy')), findsOneWidget);
    expect(find.byKey(const Key('tools-signal')), findsOneWidget);
    await showTools(tester, saved: saved, user: 'u2');
    expect(find.text('TOOL-0001 · Grinder'), findsNothing, reason: 'not their copy');
  });
}
