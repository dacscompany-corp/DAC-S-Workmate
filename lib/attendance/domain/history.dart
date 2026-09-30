import 'attendance_record.dart';
import 'work_date.dart';

enum HistorySpan { week, month }

/// Inclusive range of calendar dates (UTC midnights).
class DateRange {
  const DateRange(this.start, this.end);
  final DateTime start;
  final DateTime end;
}

/// "This week" is Monday-to-today and "this month" is the 1st-to-today — the
/// week the worker is standing in, not a rolling window. [today] is a UTC
/// midnight in Manila terms (use manilaDate(DateTime.now())).
DateRange historyRange(HistorySpan span, DateTime today) {
  final start = span == HistorySpan.week
      ? today.subtract(Duration(days: today.weekday - DateTime.monday))
      : DateTime.utc(today.year, today.month, 1);
  return DateRange(start, today);
}

class HistoryDay {
  const HistoryDay({required this.workDate, required this.date, required this.record});
  final String workDate;
  final DateTime date;
  final AttendanceRecord? record;
}

/// Every day in the range, newest first, WITH the days that have no record —
/// the gaps are what a worker checking their attendance needs to see.
List<HistoryDay> historyDays(DateRange range, List<AttendanceRecord> records) {
  final byDate = {for (final r in records) r.workDate: r};
  final days = <HistoryDay>[];
  for (var d = range.end; !d.isBefore(range.start); d = d.subtract(const Duration(days: 1))) {
    final key = isoDate(d);
    days.add(HistoryDay(workDate: key, date: d, record: byDate[key]));
  }
  return days;
}

class HistorySummary {
  const HistorySummary({required this.daysWorked, required this.totalMinutes});
  final int daysWorked;
  final int totalMinutes;
}

/// An open day counts as worked but adds ZERO minutes: total_minutes is the
/// server's to compute.
HistorySummary historySummary(List<HistoryDay> days) {
  final worked = days.where((d) => d.record != null).toList();
  return HistorySummary(
    daysWorked: worked.length,
    totalMinutes: worked.fold(0, (sum, d) => sum + (d.record!.totalMinutes ?? 0)),
  );
}

class WeekDayCell {
  const WeekDayCell({required this.date, required this.label, required this.worked, required this.isToday, required this.future});
  final DateTime date;
  final String label;
  final bool worked;
  final bool isToday;
  final bool future;
}

const _weekLabels = ['Mo', 'Tu', 'We', 'Th', 'Fr', 'Sa'];

/// Monday to Saturday of [today]'s week: SIX cells — DACs does not schedule
/// Sunday work, and an always-empty seventh column would read as a missed day.
List<WeekDayCell> weekStrip(List<AttendanceRecord> records, DateTime today) {
  final monday = today.subtract(Duration(days: today.weekday - DateTime.monday));
  final worked = records.map((r) => r.workDate).toSet();
  return [
    for (var i = 0; i < 6; i++)
      () {
        final day = monday.add(Duration(days: i));
        return WeekDayCell(
          date: day,
          label: _weekLabels[i],
          worked: worked.contains(isoDate(day)),
          isToday: day == today,
          future: day.isAfter(today),
        );
      }(),
  ];
}
