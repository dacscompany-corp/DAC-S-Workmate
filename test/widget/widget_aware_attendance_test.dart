import 'package:flutter_test/flutter_test.dart';
import 'package:workmate/attendance/data/submission_request.dart';
import 'package:workmate/attendance/domain/attendance_record.dart';
import 'package:workmate/attendance/domain/work_date.dart';
import 'package:workmate/widget/widget_aware_attendance.dart';

import '../attendance/fakes.dart';

SubmissionRequest req() => SubmissionRequest(
    direction: TimeDirection.timeIn, projectSystem: ProjectSystem.pc, projectId: 'p1',
    capturedAt: DateTime.parse('2026-09-11T00:52:00Z'), trustedAt: null, photoPath: '/x.jpg', description: null, eventId: 'e1');

void main() {
  late FakeAttendance inner;
  late int told;
  late WidgetAwareAttendance api;

  setUp(() {
    inner = FakeAttendance();
    told = 0;
    api = WidgetAwareAttendance(inner, onTodayChanged: () async => told++);
  });

  test('a submit tells the widget, so it flips the moment the worker submits', () async {
    await api.submit(req());
    expect(inner.submitted.length, 1);
    expect(told, 1);
  });

  test('a failed submit still tells the widget, and still fails', () async {
    inner.submitError = StateError('AUTH_REQUIRED');
    await expectLater(api.submit(req()), throwsStateError);
    expect(told, 1);
  });

  test("reading today tells the widget: that is where the server's corrections land", () async {
    inner.todayRecord = const AttendanceRecord(id: 'r', workDate: '2026-09-11', status: AttendanceStatus.complete);
    expect((await api.today())!.status, AttendanceStatus.complete);
    expect(told, 1);
  });

  test('history and projects do not', () async {
    await api.history('2026-09-07', '2026-09-11');
    await api.activeProjects();
    expect(told, 0);
  });

  test('a widget that cannot be told never breaks a Time In', () async {
    api = WidgetAwareAttendance(inner, onTodayChanged: () async => throw StateError('boom'));
    await api.submit(req());
    expect(inner.submitted.length, 1);
  });
}
