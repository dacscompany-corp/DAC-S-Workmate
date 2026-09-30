import 'attendance_failure.dart';
import 'work_date.dart';

/// A submission waiting to reach the server.
class QueuedSubmission {
  const QueuedSubmission({required this.eventId, required this.direction, required this.createdAt, required this.workerId});
  final String eventId;
  final TimeDirection direction;
  final DateTime createdAt;

  /// Who queued it. Empty for rows nobody can be identified for.
  final String workerId;
}

int _compare(QueuedSubmission a, QueuedSubmission b) {
  final byDirection = (a.direction == TimeDirection.timeIn ? 0 : 1) - (b.direction == TimeDirection.timeIn ? 0 : 1);
  return byDirection != 0 ? byDirection : a.createdAt.compareTo(b.createdAt);
}

/// Which queued submission to send next: an unsent Time In always before a Time
/// Out, otherwise oldest first — and only ever [currentWorkerId]'s own rows
/// (phones are shared; the RPC files each record against auth.uid()).
QueuedSubmission? nextToSend(List<QueuedSubmission> queue, String currentWorkerId) {
  QueuedSubmission? best;
  for (final q in queue) {
    if (q.workerId.isEmpty || q.workerId != currentWorkerId) continue;
    if (best == null || _compare(q, best) < 0) best = q;
  }
  return best;
}

enum QueueOutcome {
  /// Transient. Keep the row and try again later.
  retry,

  /// The server already holds this day. Reconcile to the server's row, drop ours.
  dropAndReconcile,

  /// Will never succeed; keep it visible so nobody believes the day was recorded.
  failPermanently,
}

QueueOutcome outcomeFor(AttendanceFailure failure) => switch (failure) {
      AttendanceFailure.alreadyTimedIn || AttendanceFailure.alreadyComplete => QueueOutcome.dropAndReconcile,
      // NotTimedIn: its Time In may still be one row ahead in this very queue.
      // ProjectGeofenceUnavailable: fixed by the office configuring the site.
      // AppUpdateRequired: the queue survives the APK update and sends the same row.
      AttendanceFailure.noConnection ||
      AttendanceFailure.notTimedIn ||
      AttendanceFailure.projectGeofenceUnavailable ||
      AttendanceFailure.appUpdateRequired ||
      AttendanceFailure.sessionExpired ||
      AttendanceFailure.unexpected =>
        QueueOutcome.retry,
      // Coordinates and captured_at are frozen at the shutter: a retry sends the
      // same values and earns the same refusal.
      AttendanceFailure.outsideRadius ||
      AttendanceFailure.mockLocation ||
      AttendanceFailure.locationPermissionDenied ||
      AttendanceFailure.locationDisabled ||
      AttendanceFailure.deviceClockWrong ||
      AttendanceFailure.timeOutBeforeTimeIn ||
      AttendanceFailure.shiftTooLong ||
      AttendanceFailure.projectUnavailable ||
      AttendanceFailure.noOwnerAssigned ||
      AttendanceFailure.accountInactive ||
      AttendanceFailure.notAWorker =>
        QueueOutcome.failPermanently,
    };
