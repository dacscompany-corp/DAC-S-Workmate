import 'package:flutter_test/flutter_test.dart';
import 'package:workmate/attendance/domain/total_hours.dart';

void main() {
  test("the MVP's own example formats as 9h 45m", () => expect(formatMinutes(585), '9h 45m'));
  test('a whole number of hours still shows the minutes', () => expect(formatMinutes(480), '8h 0m'));
  test('under an hour shows zero hours', () => expect(formatMinutes(20), '0h 20m'));
  test('a shift past midnight keeps counting up', () => expect(formatMinutes(1505), '25h 5m'));
  test('nothing recorded yet is a dash, not a zero', () => expect(formatMinutes(null), '--'));

  test('hours so far counts from time in to now', () {
    expect(hoursSince(DateTime.parse('2026-08-18T23:45:00Z'), DateTime.parse('2026-08-19T02:30:00Z')), '2h 45m');
  });

  test('a device clock behind the server never shows negative hours', () {
    expect(hoursSince(DateTime.parse('2026-08-19T02:30:00Z'), DateTime.parse('2026-08-19T02:25:00Z')), '0h 0m');
  });
}
