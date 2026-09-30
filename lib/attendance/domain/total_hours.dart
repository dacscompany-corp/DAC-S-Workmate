/// Hours as the worker reads them. The authoritative total is computed once,
/// server-side, into attendance_records.total_minutes; this only formats it.
const nothingYet = '--';

/// "9h 45m". Null means nothing is recorded yet.
String formatMinutes(int? minutes) {
  if (minutes == null) return nothingYet;
  final safe = minutes < 0 ? 0 : minutes;
  return '${safe ~/ 60}h ${safe % 60}m';
}

/// The live "Hours so far", clamped at zero: a phone clock a few minutes
/// behind the server must never render "-0h 5m".
String hoursSince(DateTime timeIn, DateTime now) {
  final minutes = now.difference(timeIn).inMinutes;
  return formatMinutes(minutes < 0 ? 0 : minutes);
}
