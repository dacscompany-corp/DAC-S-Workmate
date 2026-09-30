import 'dart:io';

import '../data/attendance_db.dart';
import '../data/attendance_remote.dart';
import '../data/submission_request.dart';
import '../domain/attendance_failure.dart';
import '../domain/attendance_record.dart';
import '../domain/submission_queue.dart';
import '../domain/work_date.dart';

enum SyncResult {
  /// Queue empty or everything settled.
  done,

  /// A transient failure: WorkManager should retry with backoff.
  retry,
}

/// A sane ceiling for one pass; a real queue is a handful of rows.
const _maxPerRun = 50;

/// Drains the queue: ONE run sends every row in order (Time In before Time Out,
/// oldest first, only this worker's), stopping at the first transient failure.
class SubmissionSync {
  SubmissionSync({required this.db, required this.remote});

  final AttendanceDb db;
  final AttendanceRemote remote;

  Future<SyncResult> drain(String workerId) async {
    // With no session nothing may be sent: the RPC would file it under whoever signs in next.
    if (workerId.isEmpty) return SyncResult.done;
    for (var i = 0; i < _maxPerRun; i++) {
      final queue = await db.sendable(workerId);
      final next = nextToSend(queue.map((p) => p.toQueued()).toList(), workerId);
      if (next == null) return SyncResult.done;
      final row = queue.firstWhere((p) => p.eventId == next.eventId);
      if (await _send(row, workerId) == SyncResult.retry) return SyncResult.retry;
    }
    return SyncResult.done;
  }

  Future<SyncResult> _send(PendingSubmission row, String workerId) async {
    final photo = File(row.photoLocalPath);
    if (!photo.existsSync()) {
      // Inventing a path would record attendance with no evidence.
      await db.markFailed(row.eventId, 'PHOTO_MISSING');
      return SyncResult.done;
    }
    final request = row.toRequest();
    if (request == null) {
      await db.markFailed(row.eventId, 'PROJECT_RETIRED');
      return SyncResult.done;
    }

    try {
      // The SHUTTER time travels with the row; the upload time is never used.
      final record = await remote.submit(request, workerId: workerId);
      await db.deletePending(row.eventId);
      await _adopt(workerId, record);
      _discard(photo); // only now is the photo safe to delete
      return SyncResult.done;
    } catch (error) {
      final failure = AttendanceFailure.of(error);
      await db.recordAttempt(row.eventId, failure.name);
      switch (outcomeFor(failure)) {
        case QueueOutcome.retry:
          return SyncResult.retry;
        case QueueOutcome.dropAndReconcile:
          // The server already holds this day (usually another phone). Its version wins.
          try {
            final server = await remote.today(WorkDate.of(row.capturedAt).iso);
            await db.deletePending(row.eventId);
            if (server != null) await _adopt(workerId, server);
          } catch (_) {
            await db.deletePending(row.eventId);
          }
          _discard(photo);
          return SyncResult.done;
        case QueueOutcome.failPermanently:
          // Kept, flagged and surfaced: never let a worker believe the day was recorded.
          await db.markFailed(row.eventId, failure.name);
          return SyncResult.done;
      }
    }
  }

  /// Mirrors the server's record unless a still-sendable row owns that day: the
  /// phone's mirror wins until every queued row for the day has been sent.
  Future<void> _adopt(String workerId, AttendanceRecord record) async {
    final owned = (await db.sendable(workerId)).any((p) => WorkDate.of(p.capturedAt).iso == record.workDate);
    if (!owned) await db.upsertRecord(workerId, record, pending: false);
  }

  void _discard(File photo) {
    try {
      photo.deleteSync();
    } catch (_) {}
  }
}
