import 'package:flutter/foundation.dart';

import '../data/attendance_api.dart';
import '../domain/attendance_failure.dart';
import '../domain/history.dart';
import '../domain/work_date.dart';

/// History's state: the span, its days (gaps included) and the totals.
/// Ported from DACS Attendance's HistoryViewModel.
class HistoryController extends ChangeNotifier {
  HistoryController({required AttendanceApi attendance, DateTime Function()? now})
      : _attendance = attendance,
        _now = now ?? DateTime.now;

  final AttendanceApi _attendance;
  final DateTime Function() _now;

  HistorySpan _span = HistorySpan.week;
  bool _loading = true;
  List<HistoryDay> _days = const [];
  HistorySummary _summary = const HistorySummary(daysWorked: 0, totalMinutes: 0);
  AttendanceFailure? _failure;
  int _generation = 0;
  bool _disposed = false;

  HistorySpan get span => _span;
  bool get loading => _loading;
  List<HistoryDay> get days => _days;
  HistorySummary get summary => _summary;
  AttendanceFailure? get failure => _failure;

  Future<void> setSpan(HistorySpan span) async {
    if (span == _span) return;
    await _load(span);
  }

  Future<void> refresh() => _load(_span);

  Future<void> _load(HistorySpan span) async {
    // A newer request makes an older answer stale: quick Week/Month taps
    // must never show one span's days under the other's label.
    final generation = ++_generation;
    _span = span;
    _loading = true;
    _failure = null;
    _notify();
    final range = historyRange(span, manilaDate(_now()));
    try {
      final records = await _attendance.history(isoDate(range.start), isoDate(range.end));
      if (generation != _generation) return;
      // The days come from the RANGE, not the records: a day with no record
      // has to appear as a gap.
      _days = historyDays(range, records);
      _summary = historySummary(_days);
    } catch (e) {
      if (generation != _generation) return;
      _days = const [];
      _failure = AttendanceFailure.of(e);
    }
    _loading = false;
    _notify();
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
