import 'work_date.dart';

// The weekly attendance reward, as the worker's own screen shows it. Ported
// from DACS Attendance domain/WeeklyReward.kt.
//
// NOTHING HERE IS AUTHORITATIVE. The reward that gets paid is frozen
// server-side by attendance_evaluate_week after the week ends (0066). This
// renders the week the worker is standing in, from the server's day rows, so
// the rules match 0066's attendance_week_days exactly rather than being
// re-derived.
//
// NO TIME OUT ANYWHERE: qualification reads the Time In and nothing else. A
// forgotten Time Out, or a day an admin closed, must not move anyone's money.
//
// FIVE DAYS, NOT SIX: the reward week is Monday to Friday, while Home's week
// strip draws six cells because DACs works Saturdays. Two true things, two rows.

/// A day's outcome, exactly as attendance_week_days reports it.
enum RewardDayStatus {
  onTime,
  late,
  missing,
  notRequired,

  /// A day WORKED that cannot earn the bonus (0078): a known-bad location, or
  /// a time no clock could vouch for. Not late, not missing.
  unverified,

  /// An outcome the server learned after this build shipped. Never folded
  /// into [missing]: see [rewardSummary].
  unknown;

  static RewardDayStatus parse(String? raw) => switch (raw?.toLowerCase()) {
        'on_time' => onTime,
        'late' => late,
        'missing' => missing,
        'not_required' => notRequired,
        'unverified' => unverified,
        _ => unknown,
      };
}

enum RewardStatus { inProgress, qualified, disqualified }

/// One row from attendance_reward_progress.
class RewardDay {
  const RewardDay({required this.date, required this.required, required this.status});

  /// Calendar date (UTC midnight).
  final DateTime date;
  final bool required;
  final RewardDayStatus status;
}

enum RewardCellState {
  onTime,
  late,
  missing,
  notRequired,

  /// Worked, but could not be verified (0078). Disqualifying, not a miss.
  unverified,

  /// Later this week. Nothing is wrong yet, and it must not look as if it is.
  pending,
}

class RewardCell {
  const RewardCell({required this.date, required this.label, required this.state, required this.isToday});
  final DateTime date;

  /// Two letters, matching the week strip: Mo Tu We Th Fr.
  final String label;
  final RewardCellState state;
  final bool isToday;
}

class RewardSummary {
  const RewardSummary({
    required this.requiredDays,
    required this.onTimeDays,
    required this.lateDays,
    required this.missingDays,
    required this.unverifiedDays,
    required this.pendingDays,
    required this.completedDays,
    required this.status,
  });

  final int requiredDays;
  final int onTimeDays;
  final int lateDays;
  final int missingDays;

  /// Days worked that could not be verified (0078). Disqualifying.
  final int unverifiedDays;

  /// Required days still ahead of the worker. Never counted as missed.
  final int pendingDays;

  /// Days with a Time In, on time or late. Reporting only.
  final int completedDays;
  final RewardStatus status;
}

const _labels = ['Mo', 'Tu', 'We', 'Th', 'Fr', 'Sa', 'Su'];

/// The Monday of the week [date] falls in (a Sunday belongs to the week before it).
DateTime rewardWeekStart(DateTime date) => DateTime.utc(date.year, date.month, date.day - (date.weekday - 1));

/// Monday to Friday of that week, in order.
List<DateTime> rewardWeekDates(DateTime weekStart) =>
    [for (var i = 0; i < 5; i++) DateTime.utc(weekStart.year, weekStart.month, weekStart.day + i)];

/// The week's standing, from the server's day rows.
///
/// A DAY LATER THAN TODAY IS PENDING, NEVER MISSING: the server reports a day
/// with no Time In as `missing` whether or not it has happened. Only a day
/// strictly in the PAST can be a miss; today is still winnable.
///
/// DISQUALIFICATION IS REPORTED AS SOON AS IT IS CERTAIN: one late day settles
/// the week.
///
/// AN UNKNOWN STATUS YIELDS inProgress, never disqualified: guessing would
/// show a worker a zero the database never agreed to.
RewardSummary rewardSummary(List<RewardDay> days, DateTime today) {
  var required = 0, onTime = 0, late = 0, missing = 0, unverified = 0, pending = 0, completed = 0, unknown = 0;

  for (final day in days) {
    // An unverified day (0078) was still a day worked.
    if (day.status == RewardDayStatus.onTime || day.status == RewardDayStatus.late || day.status == RewardDayStatus.unverified) {
      completed++;
    }
    if (!day.required) continue;

    required++;
    switch (day.status) {
      case RewardDayStatus.onTime:
        onTime++;
      case RewardDayStatus.late:
        late++;
      case RewardDayStatus.unverified:
        unverified++;
      case RewardDayStatus.unknown:
        unknown++;
      // A required day the server calls not_required is a contradiction:
      // counted with the ones we cannot read, never as a silent pass.
      case RewardDayStatus.notRequired:
        unknown++;
      case RewardDayStatus.missing:
        if (day.date.isBefore(today)) {
          missing++;
        } else {
          pending++;
        }
    }
  }

  final RewardStatus status;
  if (late > 0 || missing > 0 || unverified > 0) {
    status = RewardStatus.disqualified;
  } else if (unknown > 0 || pending > 0) {
    status = RewardStatus.inProgress;
  } else if (required > 0) {
    status = RewardStatus.qualified;
  } else {
    // Every day closed: nothing to be on time for, nothing to reward (0066 agrees).
    status = RewardStatus.disqualified;
  }

  return RewardSummary(
    requiredDays: required,
    onTimeDays: onTime,
    lateDays: late,
    missingDays: missing,
    unverifiedDays: unverified,
    pendingDays: pending,
    completedDays: completed,
    status: status,
  );
}

/// The five cells of the reward strip. Built from [rewardWeekDates], not from
/// [days], so an incomplete answer still draws five columns; a date with no
/// row is treated as required and unrecorded, which is what the server says.
List<RewardCell> rewardCells(DateTime weekStart, List<RewardDay> days, DateTime today) {
  final byDate = {for (final d in days) isoDate(d.date): d};
  return [
    for (final date in rewardWeekDates(weekStart))
      () {
        final day = byDate[isoDate(date)];
        final RewardCellState state;
        if (day != null && !day.required) {
          state = RewardCellState.notRequired;
        } else if (day?.status == RewardDayStatus.onTime) {
          state = RewardCellState.onTime;
        } else if (day?.status == RewardDayStatus.late) {
          state = RewardCellState.late;
        } else if (day?.status == RewardDayStatus.unverified) {
          state = RewardCellState.unverified;
        } else if (!date.isBefore(today)) {
          // Same rule as the summary: today is still running.
          state = RewardCellState.pending;
        } else {
          state = RewardCellState.missing;
        }
        return RewardCell(date: date, label: _labels[date.weekday - 1], state: state, isToday: date == today);
      }(),
  ];
}
