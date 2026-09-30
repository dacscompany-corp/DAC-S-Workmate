/// Asia/Manila is UTC+8 all year: the Philippines has observed no daylight
/// saving since 1978, so a fixed offset is exact and needs no tz database.
const manilaOffset = Duration(hours: 8);

/// [instant] shifted so its year/month/day/hour/minute read as Manila wall
/// time. The result is UTC-typed on purpose: read its fields, never convert
/// it again.
DateTime manilaFields(DateTime instant) => instant.toUtc().add(manilaOffset);

/// The Manila calendar date of [instant], as a UTC midnight — the one date
/// representation this package uses (UTC dates have no DST to trip on).
DateTime manilaDate(DateTime instant) {
  final f = manilaFields(instant);
  return DateTime.utc(f.year, f.month, f.day);
}

String _two(int n) => n.toString().padLeft(2, '0');

/// "2026-08-19". Lexical order is chronological, which the local mirror
/// relies on for BETWEEN queries.
String isoDate(DateTime date) => '${date.year.toString().padLeft(4, '0')}-${_two(date.month)}-${_two(date.day)}';

/// The calendar day an attendance record belongs to, derived exactly as
/// attendance_time_in derives it: (captured_at at time zone 'Asia/Manila')::date.
/// Never the phone's zone, never a UTC date (PH is UTC+8, so anything before
/// 08:00 local would roll back a day — which is most Time Ins).
class WorkDate {
  const WorkDate._(this.iso);

  factory WorkDate.of(DateTime captured) => WorkDate._(isoDate(manilaDate(captured)));

  factory WorkDate.today([DateTime? now]) => WorkDate.of(now ?? DateTime.now());

  final String iso;

  @override
  String toString() => iso;

  @override
  bool operator ==(Object other) => other is WorkDate && other.iso == iso;

  @override
  int get hashCode => iso.hashCode;
}

/// Which half of the day a capture is.
enum TimeDirection {
  timeIn('IN', 'in'),
  timeOut('OUT', 'out');

  const TimeDirection(this.wire, this.slug);

  /// Stored in the local queue ("IN"/"OUT"), as the Kotlin app stores it.
  final String wire;

  /// The `in` / `out` token in the storage path contract.
  final String slug;

  static TimeDirection parse(String wire) => values.firstWhere((d) => d.wire == wire);
}

/// The Storage object path fixed by migration 0050 §7:
/// {worker_id}/{work_date}/{in|out}-{event_id}.jpg — the bucket's RLS compares
/// the FIRST segment to auth.uid(), so this shape is a permission check.
String photoPath({
  required String workerId,
  required WorkDate workDate,
  required TimeDirection direction,
  required String eventId,
}) =>
    '$workerId/$workDate/${direction.slug}-$eventId.jpg';
