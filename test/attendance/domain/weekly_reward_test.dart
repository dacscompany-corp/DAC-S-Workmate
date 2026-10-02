import 'package:flutter_test/flutter_test.dart';
import 'package:workmate/attendance/domain/weekly_reward.dart';

/// Ported from DACS Attendance WeeklyRewardTest.kt. These must stay in step
/// with 0066's attendance_week_days: if the two disagree, the reward a worker
/// was shown all week is not the reward they get.
void main() {
  // 2026-09-07 is a Monday; the reward week runs to Friday the 11th.
  final monday = DateTime.utc(2026, 9, 7);
  final tuesday = DateTime.utc(2026, 9, 8);
  final wednesday = DateTime.utc(2026, 9, 9);
  final thursday = DateTime.utc(2026, 9, 10);
  final friday = DateTime.utc(2026, 9, 11);

  RewardDay day(DateTime date, RewardDayStatus status, {bool required = true}) =>
      RewardDay(date: date, required: required, status: status);

  List<RewardDay> fullWeek(List<RewardDayStatus> statuses) {
    final dates = rewardWeekDates(monday);
    return [for (var i = 0; i < 5; i++) day(dates[i], statuses[i])];
  }

  const onTime = RewardDayStatus.onTime;
  const late = RewardDayStatus.late;
  const missing = RewardDayStatus.missing;
  const unverified = RewardDayStatus.unverified;

  test('the week starts on Monday, from any day inside it', () {
    expect(rewardWeekStart(wednesday), monday);
    expect(rewardWeekStart(monday), monday);
    // The Sunday at the end of the week still belongs to it.
    expect(rewardWeekStart(DateTime.utc(2026, 9, 13)), monday);
  });

  test('an unverified day disqualifies, but is neither late nor missing', () {
    final s = rewardSummary(fullWeek([onTime, unverified, onTime, onTime, onTime]), DateTime.utc(2026, 9, 14));
    expect(s.status, RewardStatus.disqualified);
    expect(s.unverifiedDays, 1);
    expect(s.lateDays, 0);
    expect(s.missingDays, 0);
    expect(s.completedDays, 5);
  });

  test("the server's unverified status is understood, not left as unknown", () {
    expect(RewardDayStatus.parse('unverified'), RewardDayStatus.unverified);
    final cells = rewardCells(monday, [day(tuesday, unverified)], friday);
    expect(cells[1].state, RewardCellState.unverified);
  });

  test('the reward week is five days, not the six the strip draws', () {
    final dates = rewardWeekDates(monday);
    expect(dates.length, 5);
    expect(dates.first, monday);
    expect(dates.last, friday);
  });

  test('a day later than today is pending, never missing', () {
    final s = rewardSummary(fullWeek([onTime, onTime, onTime, missing, missing]), wednesday);
    expect(s.pendingDays, 2);
    expect(s.missingDays, 0);
    expect(s.status, RewardStatus.inProgress);
  });

  test('one late day settles the week immediately', () {
    final s = rewardSummary(fullWeek([onTime, late, onTime, missing, missing]), wednesday);
    expect(s.lateDays, 1);
    expect(s.status, RewardStatus.disqualified);
  });

  test('five on-time days qualify', () {
    final s = rewardSummary(fullWeek([onTime, onTime, onTime, onTime, onTime]), friday);
    expect(s.requiredDays, 5);
    expect(s.onTimeDays, 5);
    expect(s.status, RewardStatus.qualified);
  });

  test('a closed day shrinks the week, so four of four still qualifies', () {
    final days = [
      day(monday, onTime),
      day(tuesday, onTime),
      day(wednesday, RewardDayStatus.notRequired, required: false),
      day(thursday, onTime),
      day(friday, onTime),
    ];
    final s = rewardSummary(days, friday);
    expect(s.requiredDays, 4);
    expect(s.onTimeDays, 4);
    expect(s.missingDays, 0);
    expect(s.status, RewardStatus.qualified);
  });

  test('a past day with no Time In disqualifies', () {
    final s = rewardSummary(fullWeek([onTime, missing, onTime, onTime, onTime]), friday);
    expect(s.missingDays, 1);
    expect(s.status, RewardStatus.disqualified);
  });

  test('a whole week of closed days is not a free reward', () {
    final days = [for (final d in rewardWeekDates(monday)) day(d, RewardDayStatus.notRequired, required: false)];
    final s = rewardSummary(days, friday);
    expect(s.requiredDays, 0);
    expect(s.status, RewardStatus.disqualified);
  });

  test('an unknown day status says in progress, never disqualified', () {
    final s = rewardSummary(fullWeek([onTime, onTime, RewardDayStatus.unknown, onTime, onTime]), friday);
    expect(s.status, RewardStatus.inProgress);
  });

  test('an unrecognised status string parses to unknown rather than throwing', () {
    expect(RewardDayStatus.parse('on_time'), RewardDayStatus.onTime);
    expect(RewardDayStatus.parse('not_required'), RewardDayStatus.notRequired);
    expect(RewardDayStatus.parse('excused'), RewardDayStatus.unknown);
    expect(RewardDayStatus.parse(null), RewardDayStatus.unknown);
  });

  test('the strip always draws five cells, even on a short answer', () {
    final cells = rewardCells(monday, [day(monday, onTime), day(tuesday, late)], wednesday);
    expect(cells.length, 5);
    expect(cells.map((c) => c.label), ['Mo', 'Tu', 'We', 'Th', 'Fr']);
    expect(cells[0].state, RewardCellState.onTime);
    expect(cells[1].state, RewardCellState.late);
    // Today, unrecorded: PENDING, not missed.
    expect(cells[2].state, RewardCellState.pending);
    expect(cells[3].state, RewardCellState.pending);
    expect(cells[4].state, RewardCellState.pending);
  });

  test('a closed day draws as not required, not as a miss', () {
    final cells = rewardCells(monday, [day(wednesday, RewardDayStatus.notRequired, required: false)], friday);
    expect(cells[2].state, RewardCellState.notRequired);
  });

  test('today is marked, and only today', () {
    final cells = rewardCells(monday, const [], wednesday);
    expect(cells.where((c) => c.isToday).length, 1);
    expect(cells.singleWhere((c) => c.isToday).date, wednesday);
  });

  test('a late day still counts as a day worked', () {
    final s = rewardSummary(fullWeek([late, onTime, onTime, onTime, onTime]), friday);
    expect(s.completedDays, 5);
    expect(s.status, RewardStatus.disqualified);
  });

  test('today with no Time In yet is pending, not a miss', () {
    final s = rewardSummary(fullWeek([onTime, missing, missing, missing, missing]), tuesday);
    expect(s.missingDays, 0);
    expect(s.pendingDays, 4);
    expect(s.status, RewardStatus.inProgress);
  });

  test('today draws as pending, and yesterday as missed', () {
    final cells = rewardCells(monday, [day(monday, missing), day(tuesday, missing)], tuesday);
    expect(cells[0].state, RewardCellState.missing);
    expect(cells[1].state, RewardCellState.pending);
  });
}
