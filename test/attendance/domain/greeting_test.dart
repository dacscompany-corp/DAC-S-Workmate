import 'package:flutter_test/flutter_test.dart';
import 'package:workmate/attendance/domain/greeting.dart';

/// Ported from GreetingTest.kt: it once said good morning to a worker timing
/// out at half past one.
void main() {
  test('morning until noon', () {
    expect(greetingAtHour(5), Greeting.morning);
    expect(greetingAtHour(11), Greeting.morning);
  });

  test('afternoon from noon', () {
    expect(greetingAtHour(12), Greeting.afternoon);
    expect(greetingAtHour(17), Greeting.afternoon);
  });

  test('evening from six, and through the night', () {
    expect(greetingAtHour(18), Greeting.evening);
    expect(greetingAtHour(23), Greeting.evening);
    expect(greetingAtHour(4), Greeting.evening);
  });

  test('the hour is Manila, whatever the phone says', () {
    // 04:30 UTC is 12:30 in Manila: afternoon, not "morning" from a UTC reading.
    expect(greetingAt(DateTime.parse('2026-09-09T04:30:00Z')), Greeting.afternoon);
    expect(greetingAt(DateTime.parse('2026-09-08T22:00:00Z')).text, 'Good morning'); // 06:00 Manila
  });
}
