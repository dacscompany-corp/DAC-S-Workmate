import 'package:flutter_test/flutter_test.dart';
import 'package:workmate/attendance/data/reward_remote.dart';
import 'package:workmate/attendance/domain/weekly_reward.dart';

void main() {
  test('a server row becomes a reward day on its calendar date', () {
    final d = rewardDayFromRow({'work_date': '2026-09-08', 'required': true, 'day_status': 'on_time', 'timein_at': null, 'start_time': '08:00:00'})!;
    expect(d.date, DateTime.utc(2026, 9, 8));
    expect(d.required, isTrue);
    expect(d.status, RewardDayStatus.onTime);
  });

  test('a closed day keeps required false', () {
    final d = rewardDayFromRow({'work_date': '2026-09-09', 'required': false, 'day_status': 'not_required'})!;
    expect(d.required, isFalse);
    expect(d.status, RewardDayStatus.notRequired);
  });

  test('a row whose date cannot be read is dropped, not guessed', () {
    expect(rewardDayFromRow({'work_date': 'soon', 'required': true, 'day_status': 'late'}), isNull);
    expect(rewardDayFromRow({'work_date': null, 'required': true, 'day_status': 'late'}), isNull);
  });

  test('a missing required flag counts the day, as the server would', () {
    // rewardCells treats a date with no row as required; a row with no flag gets the same benefit of the doubt.
    expect(rewardDayFromRow({'work_date': '2026-09-10', 'day_status': 'missing'})!.required, isTrue);
  });
}
