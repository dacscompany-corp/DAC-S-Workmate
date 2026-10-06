import 'dart:io';

import '../../attendance/sync/submission_sync.dart' show SyncResult;
import '../data/request_remote.dart';
import '../data/requests_db.dart';
import '../domain/request_failure.dart';
import '../domain/request_op.dart';

/// A sane ceiling for one pass.
const _maxPerRun = 100;

/// Drains the request queue: ONE run sends this worker's ops in queue order,
/// stopping at the first transient failure (an op that must wait keeps every
/// later op of the same request behind it, so they land in the order made).
class RequestSync {
  RequestSync({required this.db, required this.remote});

  final RequestsDb db;
  final RequestRemote remote;

  /// Ops the last [drain] finished with: sent, or refused for good.
  int settled = 0;

  Future<SyncResult> drain(String workerId) async {
    settled = 0;
    // With no session nothing may be sent: it would file under whoever signs in next.
    if (workerId.isEmpty) return SyncResult.done;
    for (var i = 0; i < _maxPerRun; i++) {
      final queue = await db.sendable(workerId);
      if (queue.isEmpty) return SyncResult.done;
      if (await _send(queue.first, queue.sublist(1), workerId) == SyncResult.retry) return SyncResult.retry;
      settled++;
    }
    return SyncResult.done;
  }

  Future<SyncResult> _send(RequestOp op, List<RequestOp> later, String workerId) async {
    try {
      switch (op.kind) {
        case OpKind.submit:
          final result = await remote.submit(op.opId, op.body, workerId: workerId);
          final lineIds = [for (final id in (result['line_ids'] as List<dynamic>? ?? const [])) id as String];
          await db.link(workerId, op.draftId!, result['request_id'] as String, lineIds);
          await db.deleteOp(op.opId);
        case OpKind.photo:
          final requestId = op.requestId;
          final file = File(op.localPath ?? '');
          // Its submit never landed (it was refused, which fails this op too):
          // there is nothing to attach it to.
          if (requestId == null) {
            await db.markFailed(op.opId, 'PHOTO_ORPHAN');
            return SyncResult.done;
          }
          if (!file.existsSync()) {
            await db.markFailed(op.opId, 'PHOTO_MISSING');
            return SyncResult.done;
          }
          await remote.attachPhoto(
            opId: op.opId,
            requestId: requestId,
            lineId: op.lineId,
            photoId: op.photoId!,
            localPath: file.path,
            workerId: workerId,
          );
          await db.deleteOp(op.opId);
          _discard(file); // only now is the photo safe to delete
        case OpKind.quantity:
          final result = await remote.changeQuantity(op.opId, op.lineId!, op.baseVersion ?? 0, op.quantity!, workerId: workerId);
          await db.deleteOp(op.opId);
          await _rebase(later, op.lineId!, result);
        case OpKind.cancelLine:
          final result = await remote.cancelLine(op.opId, op.lineId!, workerId: workerId);
          await db.deleteOp(op.opId);
          await _rebase(later, op.lineId!, result);
        case OpKind.cancelRequest:
          await remote.cancelRequest(op.opId, op.requestId!, workerId: workerId);
          await db.deleteOp(op.opId);
      }
      return SyncResult.done;
    } catch (error) {
      final failure = RequestFailure.of(error);
      await db.recordAttempt(op.opId, failure.name, countsTowardCap: failure.countsTowardCap);
      final givingUp = failure.countsTowardCap && op.attempts + 1 >= maxUnexpectedAttempts;
      if (failure.retryable && !givingUp) return SyncResult.retry;
      // Kept, flagged and shown: never let a worker believe it reached the office.
      await db.markFailed(op.opId, failure.name);
      for (final e in rebaseAfterRefusal(later, op).entries) {
        await db.setBase(e.key, e.value);
      }
      if (op.kind == OpKind.submit && op.draftId != null) await db.failDraftOps(op.draftId!, failure.name);
      return SyncResult.done;
    }
  }

  Future<void> _rebase(List<RequestOp> later, String lineId, Map<String, dynamic> result) async {
    for (final e in rebaseAfter(later, lineId, result).entries) {
      await db.setBase(e.key, e.value);
    }
  }

  void _discard(File photo) {
    try {
      photo.deleteSync();
    } catch (_) {}
  }
}
