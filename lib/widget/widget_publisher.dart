import 'package:flutter/foundation.dart';

import '../attendance/data/attendance_db.dart';
import '../attendance/domain/work_date.dart';
import 'widget_bridge.dart';
import 'widget_snapshot.dart';

/// Takes today's snapshot from the phone's mirror and hands it to the widget.
/// The mirror only -- never the network: the app has already reconciled it.
class WidgetPublisher {
  WidgetPublisher(this._bridge, {DateTime Function()? now}) : _now = now ?? DateTime.now;

  final WidgetBridge _bridge;
  final DateTime Function() _now;

  /// [workerId] is '' when nobody is let in: the widget then asks for a sign-in.
  Future<WidgetSnapshot> snapshotFor(AttendanceDb db, String workerId) async {
    if (workerId.isEmpty) return const WidgetSnapshot.signedOut();
    try {
      final today = WorkDate.today(_now()).iso;
      final record = await db.recordFor(workerId, today);
      final pending = await db.hasPendingFor(workerId);
      return WidgetSnapshot(
        signedIn: true,
        workDate: today,
        status: record?.status.name,
        timeInAt: record?.timeInAt,
        timeOutAt: record?.timeOutAt,
        notSentYet: pending,
      );
    } catch (_) {
      return const WidgetSnapshot(signedIn: true, readFailed: true);
    }
  }

  Future<void> _queue = Future.value();

  /// Never throws: a widget that cannot be told must not break a Time In.
  ///
  /// Publishes run one at a time, in request order: a sign-out requested after
  /// a worker's publish must land last, or the slower earlier publish would
  /// push the previous worker's day back onto the widget.
  Future<void> publish(AttendanceDb db, String workerId) {
    final next = _queue.then((_) => _publishNow(db, workerId));
    _queue = next.catchError((_) {});
    return next;
  }

  /// For a drain that captured [workerId] when it started: publishes only if
  /// that worker is still the one let in. A sign-out during the send must not
  /// put their day back on the widget; a skipped push loses nothing (sign-in /
  /// sign-out and Home's next today() publish anyway).
  Future<void> publishIfCurrent(AttendanceDb db, String workerId, String Function() currentWorkerId) async {
    try {
      if (currentWorkerId() != workerId) return;
    } catch (_) {
      return;
    }
    await publish(db, workerId);
  }

  Future<void> _publishNow(AttendanceDb db, String workerId) async {
    try {
      await _bridge.push(await snapshotFor(db, workerId));
    } catch (e) {
      debugPrint('Widget update failed: $e');
    }
  }
}
