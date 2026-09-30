import 'package:flutter_test/flutter_test.dart';
import 'package:workmate/attendance/domain/attendance_failure.dart';
import 'package:workmate/attendance/domain/submission_queue.dart';
import 'package:workmate/attendance/domain/work_date.dart';

void main() {
  const me = 'worker-a';
  QueuedSubmission pending(String id, TimeDirection d, String created, {String workerId = me}) =>
      QueuedSubmission(eventId: id, direction: d, createdAt: DateTime.parse(created), workerId: workerId);

  test('the queue drains oldest first', () {
    final out = pending('b', TimeDirection.timeOut, '2026-08-19T09:30:00Z');
    final timeIn = pending('a', TimeDirection.timeIn, '2026-08-18T23:45:00Z');
    expect(nextToSend([out, timeIn], me), same(timeIn));
  });

  test('a time out waits for its own time in even when it was queued first', () {
    final out = pending('b', TimeDirection.timeOut, '2026-08-18T23:00:00Z');
    final timeIn = pending('a', TimeDirection.timeIn, '2026-08-18T23:45:00Z');
    expect(nextToSend([out, timeIn], me), same(timeIn));
  });

  test('an empty queue has nothing to send', () => expect(nextToSend([], me), isNull));

  test('a lone time out is still sent', () {
    final out = pending('b', TimeDirection.timeOut, '2026-08-19T09:30:00Z');
    expect(nextToSend([out], me), same(out));
  });

  test("another worker's queued submission is never sent under my session", () {
    expect(nextToSend([pending('b', TimeDirection.timeIn, '2026-08-18T23:00:00Z', workerId: 'worker-b')], me), isNull);
  });

  test('my own submission is still sent when someone else\'s is queued too', () {
    final theirs = pending('b', TimeDirection.timeIn, '2026-08-18T23:00:00Z', workerId: 'worker-b');
    final mine = pending('a', TimeDirection.timeIn, '2026-08-19T00:00:00Z');
    expect(nextToSend([theirs, mine], me), same(mine));
  });

  test('a row with no owner is not sent to anyone', () {
    expect(nextToSend([pending('c', TimeDirection.timeIn, '2026-08-19T00:00:00Z', workerId: '')], me), isNull);
  });

  test('a refusal about the state of the day drops the row instead of retrying', () {
    expect(outcomeFor(AttendanceFailure.alreadyTimedIn), QueueOutcome.dropAndReconcile);
    expect(outcomeFor(AttendanceFailure.alreadyComplete), QueueOutcome.dropAndReconcile);
  });

  test('transient and fixable-elsewhere refusals are retried', () {
    for (final f in [
      AttendanceFailure.noConnection,
      AttendanceFailure.notTimedIn,
      AttendanceFailure.projectGeofenceUnavailable,
      AttendanceFailure.appUpdateRequired,
      AttendanceFailure.sessionExpired,
      AttendanceFailure.unexpected,
    ]) {
      expect(outcomeFor(f), QueueOutcome.retry, reason: f.name);
    }
  });

  test('a refusal the worker must act on is surfaced, not silently dropped', () {
    for (final f in [
      AttendanceFailure.outsideRadius,
      AttendanceFailure.mockLocation,
      AttendanceFailure.locationPermissionDenied,
      AttendanceFailure.locationDisabled,
      AttendanceFailure.deviceClockWrong,
      AttendanceFailure.timeOutBeforeTimeIn,
      AttendanceFailure.shiftTooLong,
      AttendanceFailure.projectUnavailable,
      AttendanceFailure.noOwnerAssigned,
      AttendanceFailure.accountInactive,
      AttendanceFailure.notAWorker,
    ]) {
      expect(outcomeFor(f), QueueOutcome.failPermanently, reason: f.name);
    }
  });
}
