import 'dart:io';

import '../../attendance/sync/submission_sync.dart' show SyncResult;
import '../data/workplan_db.dart';
import '../data/workplan_remote.dart';
import '../domain/wp_failure.dart';
import '../domain/wp_op.dart';

/// A sane ceiling for one pass.
const _maxPerRun = 100;

/// Drains the My Work queue: ONE run sends this worker's ops in queue order,
/// stopping at the first transient failure, so "I've read this" always lands
/// before the Start made after it, and a report before its photo.
class WorkPlanSync {
  WorkPlanSync({required this.db, required this.remote});

  final WorkPlanDb db;
  final WorkPlanRemote remote;

  /// Ops the last [drain] finished with: sent, or refused for good.
  int settled = 0;

  Future<SyncResult> drain(String workerId) async {
    settled = 0;
    // With no session nothing may be sent: it would file under whoever signs in next.
    if (workerId.isEmpty) return SyncResult.done;
    for (var i = 0; i < _maxPerRun; i++) {
      final queue = await db.sendable(workerId);
      if (queue.isEmpty) return SyncResult.done;
      if (await _send(queue.first, workerId) == SyncResult.retry) return SyncResult.retry;
      settled++;
    }
    return SyncResult.done;
  }

  Future<SyncResult> _send(WpOp op, String workerId) async {
    try {
      final task = op.taskId;
      Map<String, dynamic>? answer;
      switch (op.kind) {
        case WpOpKind.acknowledge:
          // An outdated version is answered with the current task and recorded
          // nowhere (0093): the saved task then shows it as still to read.
          answer = await remote.acknowledge(op.opId, task!, op.version ?? 0, workerId: workerId);
        case WpOpKind.start:
          answer = await remote.startWork(op.opId, task!, workerId: workerId);
        case WpOpKind.progress:
          final result = await remote.reportProgress(op.opId, task!, op.note, workerId: workerId);
          await db.settle(op, task: _task(result), eventId: (result['event_id'] as num?)?.toInt());
          return SyncResult.done;
        case WpOpKind.blocker:
          final b = op.body;
          final result = await remote.reportBlocker(
              op.opId, task!, b['kind'] as String, b['description'] as String, b['request_id'] as String?,
              workerId: workerId);
          await db.settle(op, task: _task(result), blockerId: result['blocker_id'] as String?);
          return SyncResult.done;
        case WpOpKind.done:
          answer = await remote.reportDone(op.opId, task!, op.note, workerId: workerId);
        case WpOpKind.check:
          answer = await remote.leaderCheck(op.opId, task!, op.note, workerId: workerId);
        case WpOpKind.propose:
          await remote.propose(op.opId, op.body, workerId: workerId);
        case WpOpKind.photo:
          final file = File(op.localPath ?? '');
          // Its report never landed (refused, which fails this op too): there
          // is nothing to link it to.
          if (op.blockerId == null && op.eventId == null) {
            await db.markFailed(op.opId, 'PHOTO_ORPHAN');
            return SyncResult.done;
          }
          if (!file.existsSync()) {
            await db.markFailed(op.opId, 'PHOTO_MISSING');
            return SyncResult.done;
          }
          await remote.attachPhoto(
            opId: op.opId,
            taskId: task!,
            blockerId: op.blockerId,
            eventId: op.eventId,
            photoId: op.photoId!,
            localPath: file.path,
            workerId: workerId,
          );
          await db.deleteOp(op.opId);
          _discard(file); // only now is the photo safe to delete
          return SyncResult.done;
      }
      await db.settle(op, task: _task(answer));
      return SyncResult.done;
    } catch (error) {
      final failure = WpFailure.of(error);
      await db.recordAttempt(op.opId, failure.name, countsTowardCap: failure.countsTowardCap);
      final givingUp = failure.countsTowardCap && op.attempts + 1 >= maxWpAttempts;
      if (failure.retryable && !givingUp) return SyncResult.retry;
      // Kept, flagged and shown: never let a worker believe it reached the office.
      await db.markFailed(op.opId, failure.name);
      await db.failChildren(op.opId, failure.name);
      return SyncResult.done;
    }
  }

  /// The task the server answered with (0093 returns it after each action).
  Map<String, dynamic>? _task(Map<String, dynamic>? result) {
    final t = result?['task'];
    return t is Map ? Map<String, dynamic>.from(t) : null;
  }

  void _discard(File photo) {
    try {
      photo.deleteSync();
    } catch (_) {}
  }
}
