import 'package:flutter_test/flutter_test.dart';
import 'package:workmate/attendance/domain/attendance_record.dart';
import 'package:workmate/attendance/domain/work_date.dart';

void main() {
  test('a project is identified by the pair, never the id alone', () {
    const pc = AttendanceProject(system: ProjectSystem.pc, id: 'x', name: 'A');
    const pm = AttendanceProject(system: ProjectSystem.pm, id: 'x', name: 'B');
    expect(pc.key, 'pc:x');
    expect(pc.key == pm.key, isFalse);
  });

  test('an unknown project system is null, not a guess', () {
    expect(ProjectSystem.of('pc'), ProjectSystem.pc);
    expect(ProjectSystem.of('PM'), ProjectSystem.pm);
    expect(ProjectSystem.of('xx'), isNull);
    expect(ProjectSystem.of(null), isNull);
  });

  test('status parsing never crashes on a new value', () {
    expect(AttendanceStatus.parse('working'), AttendanceStatus.working);
    expect(AttendanceStatus.parse('ABANDONED'), AttendanceStatus.abandoned);
    expect(AttendanceStatus.parse('something'), AttendanceStatus.unknown);
  });

  test('a server row maps, including Postgres timestamps with microseconds and offsets', () {
    final r = AttendanceRecord.fromRow({
      'id': 'r1',
      'work_date': '2026-08-19',
      'status': 'complete',
      'timein_at': '2026-08-19T07:45:00.123456+08:00',
      'timeout_at': '2026-08-19T17:30:00+08:00',
      'timein_project_name': 'ABC',
      'timeout_project_name': 'ABC',
      'total_minutes': 585,
      'timein_photo_path': 'w/2026-08-19/in-e.jpg',
      'extra_admin_column': 'ignored',
    });
    expect(r.timeInAt, DateTime.parse('2026-08-18T23:45:00.123456Z'));
    expect(r.timeOutAt!.isUtc, isTrue);
    expect(r.totalMinutes, 585);
    expect(r.timeOutPhotoPath, isNull);
    expect(r.pending, isFalse);
  });

  test('only a working day offers Time Out; a closed day offers nothing', () {
    AttendanceRecord r(AttendanceStatus s) => AttendanceRecord(id: 'r', workDate: '2026-08-19', status: s);
    expect(r(AttendanceStatus.working).nextAction, TimeDirection.timeOut);
    expect(r(AttendanceStatus.complete).nextAction, isNull);
    expect(r(AttendanceStatus.abandoned).nextAction, isNull);
  });
}
