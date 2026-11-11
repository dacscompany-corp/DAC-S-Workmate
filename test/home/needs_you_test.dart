import 'package:flutter_test/flutter_test.dart';
import 'package:workmate/home/needs_you.dart';
import 'package:workmate/requests/data/requests_api.dart';
import 'package:workmate/requests/domain/remote_request.dart';
import 'package:workmate/requests/domain/request_draft.dart';
import 'package:workmate/requests/domain/request_status.dart';
import 'package:workmate/tools/domain/tool_submission.dart';
import 'package:workmate/workplan/domain/wp_op.dart';
import 'package:workmate/workplan/domain/wp_rules.dart';
import 'package:workmate/workplan/ui/workplan_copy.dart' show opLabel;

import '../requests/domain/request_models_test.dart' show requestDoc;
import '../requests/request_fakes.dart';
import '../workplan/workplan_fakes.dart';

WpEntry entry(Map<String, dynamic> doc, {List<WpOp> pending = const [], List<WpOp> failed = const []}) =>
    WpEntry(task: task0(doc), pendingOps: pending, failedOps: failed);

WpOp op(WpOpKind kind, {String id = 'op1', String task = 't1', String? parent, bool refused = true}) => WpOp(
      opId: id,
      workerId: 'u1',
      kind: kind,
      createdAt: DateTime.utc(2026, 11, 11),
      taskId: task,
      parentOpId: parent,
      lastError: refused ? 'NOT_ALLOWED' : null,
      failedPermanently: refused,
    );

RequestEntry remote(String id, SyncState state, {bool mine = true}) =>
    RequestEntry(state: state, remote: RemoteRequest.fromJson(requestDoc(id: id, mine: mine)));

RequestEntry draft(String id, {int lines = 2, bool placed = true}) => RequestEntry(
      state: SyncState.draft,
      draft: RequestDraft(
        id: id,
        createdAt: DateTime.utc(2026, 11, 11),
        destination: placed ? site : null,
        lines: [for (var i = 0; i < lines; i++) DraftLine.fromCatalog('$id-l$i', pipe)],
      ),
    );

ToolSubmission toolRecord(String id) => ToolSubmission.create(
      opId: id,
      userId: 'u1',
      write: ToolWrite.giveBack,
      params: {'p_op': id},
      summary: 'Return TOOL-0001 · Grinder',
      now: DateTime.utc(2026, 11, 11),
    );

List<(NeedsKind, String, String, String, String?)> shape(NeedsYou n) =>
    [for (final r in n.rows) (r.kind, r.title, r.line, r.action, r.target)];

void main() {
  test('a new task and a changed task: Read, each with its own words', () {
    final n = needsYou(work: [
      entry(taskDoc(id: 't1', title: 'Skim coat')),
      entry(taskDoc(id: 't2', title: 'Ceiling', version: 2, ackVersion: 1)),
    ]);
    expect(shape(n), [
      (NeedsKind.read, 'Skim coat', 'New task · read it first', 'Read', 't1'),
      (NeedsKind.read, 'Ceiling', 'Changed by the office · read it again', 'Read', 't2'),
    ]);
  });

  test('reported work a leader can check: Check', () {
    final n = needsYou(work: [entry(taskDoc(id: 't3', title: 'Tiles', status: 'reported_done', canCheck: true, ackVersion: 1))]);
    expect(shape(n), [(NeedsKind.check, 'Tiles', 'Reported done · check the work', 'Check', 't3')]);
  });

  test('a refused My Work action, on a listed task or not: See', () {
    final start = op(WpOpKind.start);
    final gone = op(WpOpKind.progress, id: 'op2', task: 'gone');
    final n = needsYou(work: [entry(taskDoc(id: 't1', ackVersion: 1), failed: [start])], workOtherFailed: [gone]);
    expect(shape(n), [
      (NeedsKind.notAccepted, opLabel(start), 'Not accepted · see why', 'See', 'op1'),
      (NeedsKind.notAccepted, opLabel(gone), 'Not accepted · see why', 'See', 'op2'),
    ]);
  });

  test('a photo refused with its report is one row, not two', () {
    final report = op(WpOpKind.progress, id: 'op1');
    final photo = op(WpOpKind.photo, id: 'op1-photo', parent: 'op1');
    final n = needsYou(work: [entry(taskDoc(ackVersion: 1), failed: [report, photo])]);
    expect(n.rows.single.target, 'op1');
  });

  test('own requests to fix; a team member\'s request never', () {
    final requests = [
      remote('r1', SyncState.needsResolution),
      remote('r2', SyncState.needsResolution, mine: false),
      RequestEntry(state: SyncState.failed, draft: RequestDraft(id: 'd9', createdAt: DateTime.utc(2026, 11, 11), destination: site)),
      remote('r3', SyncState.pending),
      remote('r4', SyncState.received),
    ];
    expect(shape(needsYou(requests: requests)), [
      (NeedsKind.fixRequest, 'Request · Santos Townhouse · Main Contract', 'Needs resolution · check it and send again', 'Fix', 'r1'),
      (NeedsKind.fixRequest, 'Request · Santos Townhouse · Main Contract', 'Not accepted · check it and send again', 'Fix', 'd9'),
    ]);
    expect(ownToFix(requests), 2);
    expect(isOwnRequest(requests[1]), isFalse);
  });

  test('a draft: Finish, grey, with its item count', () {
    final n = needsYou(requests: [draft('d1'), draft('d2', lines: 1), draft('d3', lines: 0, placed: false)]);
    expect(shape(n), [
      (NeedsKind.finishDraft, 'Draft · Santos Townhouse · Main Contract', '2 items · not sent yet', 'Finish', 'd1'),
      (NeedsKind.finishDraft, 'Draft · Santos Townhouse · Main Contract', '1 item · not sent yet', 'Finish', 'd2'),
      (NeedsKind.finishDraft, 'Draft · New request', '0 items · not sent yet', 'Finish', 'd3'),
    ]);
    expect(n.rows.every((r) => r.quiet), isTrue);
  });

  test('things only waiting for signal are never rows (the badge says them)', () {
    final n = needsYou(
      work: [entry(taskDoc(ackVersion: 1), pending: [op(WpOpKind.progress, refused: false)])],
      requests: [remote('r3', SyncState.pending)],
    );
    expect(n.rows, isEmpty);
  });

  test('tool records not confirmed: one row each, and one for records the phone cannot read', () {
    final n = needsYou(toolsUnresolved: [toolRecord('op7')], toolRecordsNeedChecking: true);
    expect(shape(n), [
      (NeedsKind.toolUnresolved, 'Return TOOL-0001 · Grinder', 'Not confirmed · Send again or Check', 'Check', 'op7'),
      (NeedsKind.toolRecords, 'Saved tool records', 'Need checking', 'Check', null),
    ]);
    expect(n.rows.last.id, 'toolRecords-all');
  });

  test('the order: read, check, not accepted, fix, finish, tools', () {
    final n = needsYou(
      work: [
        entry(taskDoc(id: 't3', title: 'Tiles', status: 'reported_done', canCheck: true, ackVersion: 1)),
        entry(taskDoc(id: 't1', title: 'Skim coat'), failed: [op(WpOpKind.start)]),
      ],
      requests: [draft('d1'), remote('r1', SyncState.needsResolution)],
      toolsUnresolved: [toolRecord('op7')],
    );
    expect([for (final r in n.rows) r.kind], [
      NeedsKind.read,
      NeedsKind.check,
      NeedsKind.notAccepted,
      NeedsKind.fixRequest,
      NeedsKind.finishDraft,
      NeedsKind.toolUnresolved,
    ]);
  });

  test('"all caught up" only when every source was read', () {
    expect(needsYou(work: [], requests: [], toolsUnresolved: []).caughtUp, isTrue);
    final unread = needsYou(work: [], workRead: false, requests: []);
    expect([unread.caughtUp, unread.hidden], [false, true]);
    final partly = needsYou(work: [], workRead: false, requests: [draft('d1')]);
    expect([partly.caughtUp, partly.hidden, partly.rows.length], [false, false, 1]);
  });

  test('a module that is off counts as read, with nothing to show', () {
    final n = needsYou();
    expect([n.rows, n.caughtUp], [isEmpty, true]);
  });
}
