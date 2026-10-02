import 'package:flutter_test/flutter_test.dart';
import 'package:workmate/attendance/ui/formats.dart';

void main() {
  final morning = DateTime.parse('2026-08-18T23:45:00Z'); // 7:45 AM, Wednesday 19 Aug, Manila

  test('clock times are Manila, 12-hour, never 0', () {
    expect(clockTime(morning), '7:45 AM');
    expect(clockTime(DateTime.parse('2026-08-19T09:30:00Z')), '5:30 PM');
    expect(clockTime(DateTime.parse('2026-08-19T04:05:00Z')), '12:05 PM');
    expect(clockTime(DateTime.parse('2026-08-19T16:05:00Z')), '12:05 AM');
  });

  test('dates are the Manila date, not the UTC one', () {
    expect(weekdayName(morning), 'Wednesday');
    expect(longDate(morning), '19 August 2026');
    expect(shortDate(morning), '19 Aug 2026');
    expect(dayMonth(morning), '19 Aug');
  });

  test('a history heading reads the calendar date as it is', () {
    expect(dayHeading(DateTime.utc(2026, 8, 26)), 'Wednesday, 26 Aug');
  });

  test('"1 days worked" never appears', () {
    expect(daysWorked(1), '1 day worked');
    expect(daysWorked(0), '0 days worked');
    expect(daysWorked(3), '3 days worked');
  });

  test('pesos shows centavos only when they are real', () {
    expect(pesos(500), '₱500');
    expect(pesos(500.5), '₱500.50');
    expect(pesos(1250.25), '₱1250.25');
  });
}
