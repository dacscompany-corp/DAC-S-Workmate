import 'dart:async';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:workmate/attendance/domain/attendance_failure.dart';
import 'package:workmate/attendance/domain/attendance_record.dart';
import 'package:workmate/attendance/domain/history.dart';
import 'package:workmate/attendance/history/history_controller.dart';

import '../fakes.dart';

void main() {
  late FakeAttendance attendance;
  final now = DateTime.parse('2026-08-26T02:00:00Z'); // Wednesday 26 Aug, Manila

  HistoryController history() => HistoryController(attendance: attendance, now: () => now);

  setUp(() => attendance = FakeAttendance());

  test('the week runs Monday to today and keeps the gaps', () async {
    attendance.historyRecords = [
      const AttendanceRecord(id: 'a', workDate: '2026-08-24', status: AttendanceStatus.complete, totalMinutes: 585),
    ];
    final c = history();
    await c.refresh();
    expect(attendance.historyCalls.single, ('2026-08-24', '2026-08-26'));
    expect(c.days.map((d) => d.workDate), ['2026-08-26', '2026-08-25', '2026-08-24']);
    expect(c.summary.daysWorked, 1);
    expect(c.summary.totalMinutes, 585);
    expect(c.loading, isFalse);
  });

  test('Month reads from the first of the month', () async {
    final c = history();
    await c.refresh();
    await c.setSpan(HistorySpan.month);
    expect(attendance.historyCalls.last, ('2026-08-01', '2026-08-26'));
    expect(c.span, HistorySpan.month);
    expect(c.days.length, 26);
  });

  test('choosing the span already shown does not read again', () async {
    final c = history();
    await c.refresh();
    await c.setSpan(HistorySpan.week);
    expect(attendance.historyCalls.length, 1);
  });

  test('no signal and nothing saved says so, instead of an empty history', () async {
    attendance.historyError = const SocketException('down');
    final c = history();
    await c.refresh();
    expect(c.failure, AttendanceFailure.noConnection);
    expect(c.days, isEmpty);
  });

  test('a slow answer for Week cannot overwrite the Month the worker switched to', () async {
    final gate = Completer<void>();
    attendance.historyGate = gate;
    final c = history();
    final week = c.refresh();
    attendance.historyGate = null;
    await c.setSpan(HistorySpan.month);
    gate.complete();
    await week;
    expect(c.span, HistorySpan.month);
    expect(c.days.length, 26);
  });
}
