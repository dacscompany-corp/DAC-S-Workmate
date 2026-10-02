import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:workmate/attendance/domain/attendance_failure.dart';
import 'package:workmate/attendance/domain/attendance_record.dart';
import 'package:workmate/attendance/domain/work_date.dart';
import 'package:workmate/attendance/home/home_controller.dart';

import '../fakes.dart';

void main() {
  late FakeAttendance attendance;
  late FakeScheduler scheduler;
  final now = DateTime.parse('2026-08-19T02:00:00Z'); // 10:00 AM, Wednesday 19 Aug, Manila

  HomeController home() => HomeController(attendance: attendance, scheduler: scheduler, now: () => now);
  AttendanceRecord working({bool pending = false}) => AttendanceRecord(
        id: 'r',
        workDate: '2026-08-19',
        status: AttendanceStatus.working,
        timeInAt: DateTime.parse('2026-08-18T23:45:00Z'),
        timeInProjectName: abc.name,
        pending: pending,
      );
  Future<void> settle() => Future<void>.delayed(Duration.zero);

  setUp(() {
    attendance = FakeAttendance();
    scheduler = FakeScheduler();
  });

  test('nothing is offered while today is still being read', () {
    final c = home();
    expect(c.loading, isTrue);
    expect(c.nextAction, isNull);
  });

  test('no record yet: Time In', () async {
    final c = home();
    await c.refresh();
    expect(c.nextAction, TimeDirection.timeIn);
    expect(c.hoursLabel, '--');
    expect(c.minutes, isNull);
  });

  test('working: Time Out, with the hours so far', () async {
    attendance.todayRecord = working();
    final c = home();
    await c.refresh();
    expect(c.nextAction, TimeDirection.timeOut);
    expect(c.working, isTrue);
    expect(c.minutes, 135);
    expect(c.hoursLabel, '2h 15m');
  });

  test("a closed day offers nothing and shows the server's total", () async {
    attendance.todayRecord = const AttendanceRecord(id: 'r', workDate: '2026-08-19', status: AttendanceStatus.complete, totalMinutes: 585);
    final c = home();
    await c.refresh();
    expect(c.nextAction, isNull);
    expect(c.complete, isTrue);
    expect(c.hoursLabel, '9h 45m');
    expect(c.minutes, 585);
  });

  test('no signal and nothing on the phone still offers Time In', () async {
    attendance.todayError = const SocketException('down');
    final c = home();
    await c.refresh();
    expect(c.failure, AttendanceFailure.noConnection);
    expect(c.nextAction, TimeDirection.timeIn);
  });

  test('a server refusal offers nothing', () async {
    attendance.todayError = const PostgrestException(message: 'ACCOUNT_INACTIVE', code: 'P0001');
    final c = home();
    await c.refresh();
    expect(c.failure, AttendanceFailure.accountInactive);
    expect(c.nextAction, isNull);
  });

  test('opening Home sends the queue now and warms the project list', () async {
    final c = home();
    await c.refresh();
    await settle();
    expect(scheduler.sendNows, 1);
    expect(attendance.projectLoads, 1);
  });

  test('a failed week read never takes today down with it', () async {
    attendance.historyError = const SocketException('down');
    attendance.todayRecord = working();
    final c = home();
    await c.refresh();
    await settle();
    expect(c.record, isNotNull);
    expect(c.week.length, 6);
  });

  test('the strip turns today on as soon as the phone has a record', () async {
    attendance.todayRecord = working(pending: true);
    final c = home();
    await c.refresh();
    await settle();
    expect(c.week.firstWhere((d) => d.isToday).worked, isTrue);
  });

  test('refused submissions are listed and can be dismissed', () async {
    attendance.refused = [refusedRow()];
    final c = home();
    await c.refresh();
    await settle();
    expect(c.refused.single.eventId, 'e9');
    await c.dismissRefused('e9');
    expect(attendance.dismissed, ['e9']);
    expect(c.refused, isEmpty);
  });

  test('a refresh after a background send does not ask to send again', () async {
    final c = home();
    await c.refresh(sendQueued: false);
    await settle();
    expect(scheduler.sendNows, 0);
    await c.refresh();
    await settle();
    expect(scheduler.sendNows, 1);
  });
}
