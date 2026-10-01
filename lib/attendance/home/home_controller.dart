import 'dart:async';

import 'package:flutter/foundation.dart';

import '../data/attendance_api.dart';
import '../data/submission_request.dart';
import '../domain/attendance_failure.dart';
import '../domain/attendance_record.dart';
import '../domain/history.dart';
import '../domain/total_hours.dart';
import '../domain/work_date.dart';
import '../sync/upload_scheduler.dart';

/// Home's state. Ported from DACS Attendance's DashboardViewModel: today's
/// record decides the one hero action.
class HomeController extends ChangeNotifier {
  HomeController({required AttendanceApi attendance, required UploadScheduler scheduler, DateTime Function()? now})
      : _attendance = attendance,
        _scheduler = scheduler,
        now = now ?? DateTime.now;

  final AttendanceApi _attendance;
  final UploadScheduler _scheduler;

  /// The clock the screen reads (fixed in tests).
  final DateTime Function() now;

  bool _loading = true;
  AttendanceRecord? _record;
  AttendanceFailure? _failure;
  List<WeekDayCell> _week = const [];
  List<PendingSubmission> _refused = const [];
  bool _disposed = false;

  bool get loading => _loading;
  AttendanceRecord? get record => _record;
  AttendanceFailure? get failure => _failure;
  List<PendingSubmission> get refused => _refused;
  bool get working => _record?.status == AttendanceStatus.working;
  bool get complete => _record?.status == AttendanceStatus.complete;

  /// The single decision this screen makes. Null = no hero button.
  TimeDirection? get nextAction {
    // "Not loaded yet" and "no record today" are different facts: offering an
    // action before the read resolves invites a double Time In.
    if (_loading) return null;
    final r = _record;
    if (r != null) return r.nextAction;
    // No signal and nothing on the phone: a worker at 07:45 with no bars must
    // still be able to start the day. A double Time In is refused by the RPC
    // (ALREADY_TIMED_IN) and the queue drops and reconciles it.
    if (_failure == AttendanceFailure.noConnection) return TimeDirection.timeIn;
    // Any other failure is the server refusing, not unreachable.
    if (_failure != null) return null;
    return TimeDirection.timeIn;
  }

  /// Monday to Saturday. The week comes from the server's history and the
  /// record from the phone (which knows about a queued Time In): the record
  /// only ever turns today ON.
  List<WeekDayCell> get week {
    final today = manilaDate(now());
    final cells = _week.isEmpty ? weekStrip(const [], today) : _week;
    if (_record == null) return cells;
    return [
      for (final c in cells)
        c.isToday && !c.worked ? WeekDayCell(date: c.date, label: c.label, worked: true, isToday: true, future: c.future) : c,
    ];
  }

  /// Minutes for the meter; null means "no figure" (an empty track, not zero hours).
  int? get minutes {
    final r = _record;
    if (r == null) return null;
    final timeIn = r.timeInAt;
    if (r.status == AttendanceStatus.working && timeIn != null) {
      final m = now().difference(timeIn).inMinutes;
      return m < 0 ? 0 : m;
    }
    return r.totalMinutes;
  }

  /// Live while working; once closed, the SERVER's total, never recomputed.
  String get hoursLabel {
    final r = _record;
    if (r == null) return nothingYet;
    final timeIn = r.timeInAt;
    if (r.status == AttendanceStatus.working && timeIn != null) return hoursSince(timeIn, now());
    return formatMinutes(r.totalMinutes);
  }

  Future<void> refresh() async {
    _loading = true;
    _failure = null;
    _notify();
    // Opening Home is the clearest sign a human is present and probably back
    // in coverage: queued records get a fresh attempt now.
    unawaited(_quietly(_scheduler.sendNow));
    // Warm the project cache while there is signal; the picker reads it offline.
    unawaited(_quietly(_attendance.activeProjects));
    // Read separately so a failure here cannot take the hero button down.
    unawaited(_loadWeek());
    unawaited(_loadRefused());
    try {
      _record = await _attendance.today();
    } catch (e) {
      // Deliberately NOT "no record yet": that reads as "you have not timed in".
      _failure = AttendanceFailure.of(e);
    }
    _loading = false;
    _notify();
  }

  Future<void> dismissRefused(String eventId) async {
    try {
      await _attendance.dismissRefused(eventId);
    } catch (_) {
      // Left listed; the worker can dismiss it again.
    }
    await _loadRefused();
  }

  /// Re-draws the live "Hours so far".
  void tick() => _notify();

  Future<void> _loadWeek() async {
    final today = manilaDate(now());
    final range = historyRange(HistorySpan.week, today);
    try {
      final records = await _attendance.history(isoDate(range.start), isoDate(range.end));
      _week = weekStrip(records, today);
      _notify();
    } catch (_) {
      // The strip is a glance; six empty cells until it can be read.
    }
  }

  Future<void> _loadRefused() async {
    try {
      _refused = await _attendance.refusedSubmissions();
      _notify();
    } catch (_) {
      // Shown next time.
    }
  }

  static Future<void> _quietly(Future<void> Function() action) async {
    try {
      await action();
    } catch (_) {
      // Best effort.
    }
  }

  void _notify() {
    if (!_disposed) notifyListeners();
  }

  @override
  void dispose() {
    _disposed = true;
    super.dispose();
  }
}
