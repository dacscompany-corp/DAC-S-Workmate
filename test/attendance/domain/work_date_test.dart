import 'package:flutter_test/flutter_test.dart';
import 'package:workmate/attendance/domain/work_date.dart';

void main() {
  test('an early morning capture lands on today, not yesterday', () {
    expect(WorkDate.of(DateTime.parse('2026-08-18T23:45:00Z')).iso, '2026-08-19');
  });

  test('late night and just after midnight are different work dates', () {
    final before = WorkDate.of(DateTime.parse('2026-08-19T15:50:00Z'));
    final after = WorkDate.of(DateTime.parse('2026-08-19T16:10:00Z'));
    expect(before.iso, '2026-08-19');
    expect(after.iso, '2026-08-20');
    expect(before == after, isFalse);
  });

  test('a capture at midday is on the obvious date', () {
    expect(WorkDate.of(DateTime.parse('2026-08-19T04:00:00Z')).iso, '2026-08-19');
  });

  test('the phone zone never matters: a local DateTime is read as its instant', () {
    final local = DateTime.parse('2026-08-18T23:45:00Z').toLocal();
    expect(WorkDate.of(local).iso, '2026-08-19');
  });

  test('the photo path follows the storage contract exactly', () {
    expect(
      photoPath(
        workerId: '11111111-1111-1111-1111-111111111111',
        workDate: WorkDate.of(DateTime.parse('2026-08-18T23:45:00Z')),
        direction: TimeDirection.timeIn,
        eventId: 'abcdefab-1234-5678-9abc-def012345678',
      ),
      '11111111-1111-1111-1111-111111111111/2026-08-19/in-abcdefab-1234-5678-9abc-def012345678.jpg',
    );
  });

  test('a time out photo is named out, not in', () {
    expect(
      photoPath(
        workerId: 'w',
        workDate: WorkDate.of(DateTime.parse('2026-08-19T09:30:00Z')),
        direction: TimeDirection.timeOut,
        eventId: 'e',
      ),
      'w/2026-08-19/out-e.jpg',
    );
  });

  test('direction wire values round-trip', () {
    expect(TimeDirection.parse('IN'), TimeDirection.timeIn);
    expect(TimeDirection.parse('OUT'), TimeDirection.timeOut);
    expect(TimeDirection.timeOut.wire, 'OUT');
  });
}
