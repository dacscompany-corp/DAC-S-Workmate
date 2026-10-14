import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:supabase_flutter/supabase_flutter.dart' show PostgrestException;
import 'package:workmate/workplan/domain/wp_failure.dart';
import 'package:workmate/workplan/domain/wp_op.dart';
import 'package:workmate/workplan/domain/wp_rules.dart';
import 'package:workmate/workplan/domain/wp_task.dart';

import '../workplan_samples.dart';

WpOp op(WpOpKind kind, {int? version, String task = 't1'}) => WpOp(
      opId: 'o-${kind.name}',
      workerId: 'u1',
      kind: kind,
      createdAt: DateTime.utc(2026, 10, 14),
      taskId: task,
      body: {'version': ?version},
    );

void main() {
  const today = '2026-10-14';

  group('reading a task', () {
    test('every worker field is read; office-only fields do not exist', () {
      final t = task0(taskDoc(
        history: [
          {'id': 1, 'kind': 'published', 'note': '', 'by': 'Office', 'at': '2026-10-14T01:00:00+00:00'},
          {'id': 2, 'kind': 'revised', 'note': 'Changed: planned dates', 'by': 'Office', 'at': '2026-10-14T02:00:00+00:00'},
        ],
        blockers: [
          {'id': 'b1', 'kind': 'materials', 'description': 'No cement', 'request_id': 'r1', 'reported_at': '2026-10-14T03:00:00+00:00', 'reported_by': 'Danilo'},
        ],
        photos: [
          {'id': 'p1', 'path': 'u1/t1/x.jpg', 'blocker_id': 'b1', 'event_id': null, 'created_at': '2026-10-14T03:00:00+00:00'},
        ],
      ));
      expect(t.where, 'Barlin Residence · Main Contract');
      expect(t.responsible!.name, 'John Tapales');
      expect(t.helpers.single.name, 'Danilo Tapales');
      expect(t.blockers.single.requestId, 'r1');
      expect(t.photos.single.blockerId, 'b1');
      expect(t.latestChange, 'Changed: planned dates');
      expect(t.myRole, WpRole.responsible);
    });

    test('an unknown state or role is skipped, never guessed', () {
      expect(WpTask.fromJson(taskDoc(status: 'draft')), isNull);
      expect(WpTask.fromJson(taskDoc(role: 'owner')), isNull);
    });

    test('new, changed and read', () {
      expect(task0(taskDoc(version: 1)).needsReading, isTrue);
      expect(task0(taskDoc(version: 1)).changedSinceRead, isFalse, reason: 'never read: New, not Changed');
      expect(task0(taskDoc(version: 2, ackVersion: 1)).changedSinceRead, isTrue);
      expect(task0(taskDoc(version: 2, ackVersion: 2)).needsReading, isFalse);
      expect(task0(taskDoc(role: 'leader')).needsReading, isFalse, reason: 'a leader not on the task does not acknowledge');
    });
  });

  group('actions', () {
    test('the responsible person must read before starting', () {
      final a = actionsFor(WpEntry(task: task0()));
      expect(a.acknowledge, isTrue);
      expect(a.start, isTrue);
      expect(a.startLock, WpLock.mustRead);
    });

    test('a queued "I\'ve read this" for THIS version unlocks Start', () {
      final e = WpEntry(task: task0(), pendingOps: [op(WpOpKind.acknowledge, version: 1)]);
      expect(e.toRead, isFalse);
      expect(actionsFor(e).startLock, isNull);
      final old = WpEntry(task: task0(taskDoc(version: 2, ackVersion: 1)), pendingOps: [op(WpOpKind.acknowledge, version: 1)]);
      expect(old.toRead, isTrue, reason: 'reading version 1 never acknowledges version 2');
    });

    test('blocked locks Start and Report done; reading and problems stay open', () {
      final e = WpEntry(task: task0(taskDoc(blocked: true, ackVersion: 1)));
      final a = actionsFor(e);
      expect(a.startLock, WpLock.blocked);
      expect(a.problem, isTrue);
      final working = actionsFor(WpEntry(task: task0(taskDoc(status: 'in_progress', blocked: true, ackVersion: 1))));
      expect(working.done, isTrue);
      expect(working.doneLock, WpLock.blocked);
    });

    test('a problem reported from this phone locks Report done until the office clears it', () {
      final e = WpEntry(task: task0(taskDoc(status: 'in_progress', ackVersion: 1)), pendingOps: [op(WpOpKind.blocker)]);
      expect(actionsFor(e).doneLock, WpLock.blocked);
    });

    test('a queued Start lets the worker report done next, in order', () {
      final e = WpEntry(task: task0(taskDoc(ackVersion: 1)), pendingOps: [op(WpOpKind.start)]);
      expect(e.effectiveStatus, WpStatus.inProgress);
      final a = actionsFor(e);
      expect(a.start, isFalse);
      expect(a.done, isTrue);
    });

    test('helpers read and report problems; only the responsible person starts or reports', () {
      final a = actionsFor(WpEntry(task: task0(taskDoc(role: 'helper', ackVersion: 1))));
      expect(a.problem, isTrue);
      expect(a.start || a.progress || a.done, isFalse);
    });

    test('a leader checks reported work once; completed work offers nothing', () {
      final e = WpEntry(task: task0(taskDoc(role: 'leader', status: 'reported_done', canCheck: true)));
      expect(actionsFor(e).check, isTrue);
      expect(actionsFor(WpEntry(task: e.task, pendingOps: [op(WpOpKind.check)])).check, isFalse);
      final done = actionsFor(WpEntry(task: task0(taskDoc(status: 'completed', ackVersion: 1))));
      expect(done.problem || done.start || done.progress || done.done || done.check, isFalse);
    });
  });

  group('sections', () {
    WpGroup g(Map<String, dynamic> doc, {List<WpOp> pending = const []}) => groupOf(WpEntry(task: task0(doc), pendingOps: pending), today);

    test('what needs the worker is Today, whatever its dates', () {
      expect(g(taskDoc(start: '2026-10-20')), WpGroup.today, reason: 'unread');
      expect(g(taskDoc(role: 'leader', status: 'reported_done', canCheck: true)), WpGroup.today);
    });

    test('later start → Upcoming; blocked or reported → Waiting; completed → Done', () {
      expect(g(taskDoc(start: '2026-10-20', ackVersion: 1)), WpGroup.upcoming);
      expect(g(taskDoc(start: null, ackVersion: 1)), WpGroup.today);
      expect(g(taskDoc(blocked: true, ackVersion: 1)), WpGroup.waiting);
      expect(g(taskDoc(status: 'reported_done', ackVersion: 1)), WpGroup.waiting);
      expect(g(taskDoc(ackVersion: 1, status: 'in_progress'), pending: [op(WpOpKind.done)]), WpGroup.waiting);
      expect(g(taskDoc(status: 'completed', ackVersion: 1)), WpGroup.done);
    });

    test('late = planned end passed and not reported yet (Manila dates)', () {
      expect(isLate(WpEntry(task: task0(taskDoc(end: '2026-10-13', ackVersion: 1))), today), isTrue);
      expect(isLate(WpEntry(task: task0(taskDoc(end: '2026-10-14', ackVersion: 1))), today), isFalse);
      expect(isLate(WpEntry(task: task0(taskDoc(end: '2026-10-13', status: 'reported_done'))), today), isFalse);
    });
  });

  test('the badge counts what needs the worker; a waiting report and its photo are one pending item', () {
    final report = op(WpOpKind.blocker, task: 't3');
    final photo = WpOp(
        opId: 'o-photo3', workerId: 'u1', kind: WpOpKind.photo, createdAt: DateTime.utc(2026), taskId: 't3', parentOpId: report.opId);
    final u = summarizeWork([
      WpEntry(task: task0()),
      WpEntry(task: task0(taskDoc(id: 't2', role: 'leader', status: 'reported_done', canCheck: true))),
      WpEntry(task: task0(taskDoc(id: 't3', ackVersion: 1)), pendingOps: [report, photo]),
    ], otherFailed: 1);
    expect([u.toRead, u.toCheck, u.pending, u.failed, u.badge], [1, 1, 1, 1, 3]);
  });

  test('a photo refused with its report is one refusal, not two', () {
    final report = op(WpOpKind.blocker);
    final photo = WpOp(
        opId: 'o-photo', workerId: 'u1', kind: WpOpKind.photo, createdAt: DateTime.utc(2026), taskId: 't1', parentOpId: report.opId);
    expect(visibleFailures([report, photo]), [report]);
    expect(visibleFailures([photo]), [photo], reason: 'a photo refused on its own is shown');
    expect(summarizeWork([WpEntry(task: task0(taskDoc(ackVersion: 1)), failedOps: [report, photo])]).failed, 1);
  });

  test('a report and its photo wait as one item; a photo left after its report landed is its own', () {
    final report = op(WpOpKind.progress);
    final photo = WpOp(
        opId: 'o-photo2', workerId: 'u1', kind: WpOpKind.photo, createdAt: DateTime.utc(2026), taskId: 't1', parentOpId: report.opId);
    expect(visiblePending([report, photo]), [report]);
    expect(visiblePending([photo]), [photo]);
    expect(summarizeWork([WpEntry(task: task0(taskDoc(ackVersion: 1)), pendingOps: [photo])]).pending, 1);
  });

  group('failures', () {
    test('server codes', () {
      expect(WpFailure.of(const PostgrestException(message: 'NOT_ACKNOWLEDGED')), WpFailure.notAcknowledged);
      expect(WpFailure.of(const PostgrestException(message: 'TASK_BLOCKED')), WpFailure.taskBlocked);
      expect(WpFailure.of(const PostgrestException(message: 'NOT_A_REQUESTER')), WpFailure.notARequester);
      expect(WpFailure.of(const PostgrestException(message: 'NOT_ASSIGNED')), WpFailure.notAssigned);
      expect(WpFailure.of(StateError('AUTH_REQUIRED')), WpFailure.sessionExpired);
      expect(WpFailure.of(const SocketException('down')), WpFailure.noConnection);
      expect(WpFailure.of(StateError('something else')), WpFailure.unexpected);
      expect(WpFailure.of(const FileSystemException('x')), WpFailure.unexpected);
    });

    test('only the moment is worth retrying, never the content', () {
      expect(WpFailure.noConnection.retryable, isTrue);
      expect(WpFailure.notAcknowledged.retryable, isFalse);
      expect(WpFailure.taskBlocked.retryable, isFalse);
      expect(WpFailure.fromStored('PHOTO_MISSING'), WpFailure.unexpected);
    });
  });
}
