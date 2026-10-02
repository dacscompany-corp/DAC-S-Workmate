import 'work_date.dart';

/// How Home opens. Not decoration: the old app said "good morning" to a
/// worker timing out at half past one. Ported from Greeting.kt.
enum Greeting {
  morning('Good morning'),
  afternoon('Good afternoon'),
  evening('Good evening');

  const Greeting(this.text);
  final String text;
}

Greeting greetingAtHour(int hour) {
  if (hour >= 5 && hour <= 11) return Greeting.morning;
  if (hour >= 12 && hour <= 17) return Greeting.afternoon;
  return Greeting.evening;
}

/// By the MANILA hour: the greeting should match the worker's day.
Greeting greetingAt(DateTime instant) => greetingAtHour(manilaFields(instant).hour);
