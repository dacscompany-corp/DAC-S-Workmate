import '../domain/work_date.dart';

const _weekdays = ['Monday', 'Tuesday', 'Wednesday', 'Thursday', 'Friday', 'Saturday', 'Sunday'];
const _monthsLong = [
  'January', 'February', 'March', 'April', 'May', 'June',
  'July', 'August', 'September', 'October', 'November', 'December',
];
const _monthsShort = ['Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun', 'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec'];

// Every helper taking an INSTANT reads it as Manila wall time; the phone's
// zone is never used (PH is UTC+8 and a UTC date rolls most Time Ins back a day).

/// "7:45 AM".
String clockTime(DateTime instant) {
  final t = manilaFields(instant);
  final hour = t.hour % 12 == 0 ? 12 : t.hour % 12;
  return '$hour:${t.minute.toString().padLeft(2, '0')} ${t.hour < 12 ? 'AM' : 'PM'}';
}

/// "Wednesday".
String weekdayName(DateTime instant) => _weekdays[manilaFields(instant).weekday - 1];

/// "19 August 2026".
String longDate(DateTime instant) {
  final t = manilaFields(instant);
  return '${t.day} ${_monthsLong[t.month - 1]} ${t.year}';
}

/// "19 Aug 2026".
String shortDate(DateTime instant) {
  final t = manilaFields(instant);
  return '${t.day} ${_monthsShort[t.month - 1]} ${t.year}';
}

/// "19 Aug".
String dayMonth(DateTime instant) {
  final t = manilaFields(instant);
  return '${t.day} ${_monthsShort[t.month - 1]}';
}

/// "Wednesday, 26 Aug" for a CALENDAR date (a UTC midnight, as History uses) —
/// read as it is, not shifted.
String dayHeading(DateTime calendarDate) =>
    '${_weekdays[calendarDate.weekday - 1]}, ${calendarDate.day} ${_monthsShort[calendarDate.month - 1]}';

/// "1 day worked" / "3 days worked".
String daysWorked(int n) => n == 1 ? '1 day worked' : '$n days worked';

/// "₱500", and "₱500.50" only when the centavos are real.
String pesos(double amount) => amount % 1 == 0 ? '₱${amount.toInt()}' : '₱${amount.toStringAsFixed(2)}';
