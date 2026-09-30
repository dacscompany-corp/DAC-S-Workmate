import 'package:flutter_test/flutter_test.dart';
import 'package:workmate/attendance/domain/attendance_record.dart';
import 'package:workmate/attendance/domain/today_reconcile.dart';

void main() {
  final cached = AttendanceRecord(
    id: 'local',
    workDate: '2026-08-25',
    status: AttendanceStatus.working,
    timeInAt: DateTime.parse('2026-08-24T23:45:00Z'),
    timeInProjectName: 'ABC Building Project',
    pending: true,
  );
  final server = cached.copyWith(pending: false);

  test("the server's row wins whenever the server answers", () {
    final d = reconcileToday(serverAnswered: true, server: server, cached: cached, hasPending: false);
    expect(d, isA<TodayUse>().having((u) => u.record, 'record', same(server)));
  });

  test("a queued Time Out is not overwritten by the server's older row", () {
    final done = AttendanceRecord(
      id: 'local',
      workDate: '2026-08-25',
      status: AttendanceStatus.complete,
      timeInAt: DateTime.parse('2026-08-24T23:45:00Z'),
      timeOutAt: DateTime.parse('2026-08-25T09:30:00Z'),
      pending: true,
    );
    final d = reconcileToday(serverAnswered: true, server: server, cached: done, hasPending: true);
    expect(d, isA<TodayUse>().having((u) => u.record, 'record', same(done)));
  });

  test('offline falls back to what the phone remembers', () {
    final d = reconcileToday(serverAnswered: false, server: null, cached: cached, hasPending: true);
    expect(d, isA<TodayUse>().having((u) => u.record, 'record', same(cached)));
  });

  test('a queued submission survives the server saying there is nothing yet', () {
    final d = reconcileToday(serverAnswered: true, server: null, cached: cached, hasPending: true);
    expect(d, isA<TodayUse>().having((u) => u.record, 'record', same(cached)));
  });

  test('with nothing queued, the server saying no record clears a stale mirror', () {
    expect(reconcileToday(serverAnswered: true, server: null, cached: cached, hasPending: false), isA<TodayClear>());
  });

  test('offline with nothing cached is unknown, not empty', () {
    expect(reconcileToday(serverAnswered: false, server: null, cached: null, hasPending: false), isA<TodayUnknown>());
  });

  test('no record anywhere and nothing queued really is an empty day', () {
    expect(reconcileToday(serverAnswered: true, server: null, cached: null, hasPending: false), isA<TodayClear>());
  });
}
