import 'attendance_record.dart';

sealed class TodayDecision {}

/// Show this record.
final class TodayUse extends TodayDecision {
  TodayUse(this.record);
  final AttendanceRecord record;
}

/// There is genuinely no record today; drop any stale mirror.
final class TodayClear extends TodayDecision {}

/// We could not find out. Not the same as "no record".
final class TodayUnknown extends TodayDecision {}

/// Reconciles the server, the local mirror and the queue. "The server has no
/// record" and "the server could not be reached" demand opposite behaviour, and
/// a still-queued submission makes "no server row" the EXPECTED state.
///
/// While a sendable row is queued for the day, the phone's copy WINS even over
/// a server row: the server's row is older than the queued submission (e.g. it
/// still says "working" while a Time Out waits to upload), and showing it would
/// invite a second Time Out and overwrite the phone's newer mirror.
TodayDecision reconcileToday({
  required bool serverAnswered,
  required AttendanceRecord? server,
  required AttendanceRecord? cached,
  required bool hasPending,
}) {
  if (serverAnswered) {
    if (hasPending && cached != null) return TodayUse(cached);
    if (server != null) return TodayUse(server);
    return TodayClear();
  }
  return cached != null ? TodayUse(cached) : TodayUnknown();
}
