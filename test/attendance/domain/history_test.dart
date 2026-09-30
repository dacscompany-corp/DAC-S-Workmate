import 'package:flutter_test/flutter_test.dart';
import 'package:workmate/attendance/domain/attendance_record.dart';
import 'package:workmate/attendance/domain/history.dart';
import 'package:workmate/attendance/domain/total_hours.dart';

void main() {
  final today = DateTime.utc(2026, 8, 26); // a Wednesday
  AttendanceRecord rec(String id, String day, AttendanceStatus s, {int? minutes}) =>
      AttendanceRecord(id: id, workDate: day, status: s, totalMinutes: minutes);

  test('this week runs Monday to today, not seven days back', () {
    final r = historyRange(HistorySpan.week, today);
    expect(r.start, DateTime.utc(2026, 8, 24));
    expect(r.end, today);
  });

  test('this month runs from the first, not thirty days back', () {
    final r = historyRange(HistorySpan.month, today);
    expect(r.start, DateTime.utc(2026, 8, 1));
    expect(r.end, today);
  });

  test('a day with no record still appears, newest first', () {
    final worked = rec('r1', '2026-08-25', AttendanceStatus.complete, minutes: 585);
    final days = historyDays(historyRange(HistorySpan.week, today), [worked]);
    expect(days.map((d) => d.workDate), ['2026-08-26', '2026-08-25', '2026-08-24']);
    expect(days[0].record, isNull);
    expect(days[1].record, same(worked));
    expect(days[2].record, isNull);
  });

  test('a record outside the range is not shown', () {
    final days = historyDays(historyRange(HistorySpan.week, today), [rec('old', '2026-08-01', AttendanceStatus.complete)]);
    expect(days.length, 3);
    expect(days.every((d) => d.record == null), isTrue);
  });

  test('the totals summarise only the days that were worked', () {
    final s = historySummary(historyDays(historyRange(HistorySpan.week, today), [
      rec('a', '2026-08-25', AttendanceStatus.complete, minutes: 585),
      rec('b', '2026-08-24', AttendanceStatus.complete, minutes: 480),
    ]));
    expect(s.daysWorked, 2);
    expect(s.totalMinutes, 1065);
    expect(formatMinutes(s.totalMinutes), '17h 45m');
  });

  test('a still-open day contributes no hours to the total', () {
    final s = historySummary(historyDays(historyRange(HistorySpan.week, today), [rec('a', '2026-08-26', AttendanceStatus.working)]));
    expect(s.daysWorked, 1);
    expect(s.totalMinutes, 0);
  });

  test('the week strip is Monday to Saturday, six cells', () {
    final cells = weekStrip([rec('a', '2026-08-24', AttendanceStatus.complete)], today);
    expect(cells.map((c) => c.label), ['Mo', 'Tu', 'We', 'Th', 'Fr', 'Sa']);
    expect(cells[0].worked, isTrue);
    expect(cells[2].isToday, isTrue);
    expect(cells[3].future, isTrue);
    expect(cells[1].worked, isFalse);
  });
}
