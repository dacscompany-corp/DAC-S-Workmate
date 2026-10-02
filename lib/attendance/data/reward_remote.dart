import 'package:supabase_flutter/supabase_flutter.dart';

import '../domain/weekly_reward.dart';
import '../domain/work_date.dart';

/// The weekly reward reads. Deliberately NO offline mirror (as in DACS
/// Attendance's RewardRepository): a stale week could show "Qualified" for a
/// week already lost, so without signal the strip says it cannot check.
abstract interface class RewardApi {
  /// The server's day rows for the Monday-to-Friday week starting [weekStart].
  Future<List<RewardDay>> weekProgress(DateTime weekStart);

  /// The owner's configured reward, or null when none is set.
  Future<double?> rewardAmount();
}

/// One attendance_reward_progress row; null when its date cannot be read.
RewardDay? rewardDayFromRow(Map<String, dynamic> row) {
  final raw = row['work_date'];
  final parsed = raw == null ? null : DateTime.tryParse(raw.toString());
  if (parsed == null) return null;
  return RewardDay(
    date: DateTime.utc(parsed.year, parsed.month, parsed.day),
    // Only an explicit false is a closed day.
    required: row['required'] != false,
    status: RewardDayStatus.parse(row['day_status'] as String?),
  );
}

class SupabaseRewardRemote implements RewardApi {
  SupabaseRewardRemote(this._client);

  final SupabaseClient _client;
  static const _timeout = Duration(seconds: 15);

  @override
  Future<List<RewardDay>> weekProgress(DateTime weekStart) async {
    // Always THIS worker. The RPC refuses anyone else's id unless the caller
    // is an admin, but the app is never the thing that tries.
    final workerId = _client.auth.currentUser?.id;
    if (workerId == null) throw StateError('AUTH_REQUIRED');
    final rows = await _client
        .rpc('attendance_reward_progress', params: {'p_worker': workerId, 'p_week_start': isoDate(weekStart)})
        .timeout(_timeout);
    return (rows as List)
        .map((r) => rewardDayFromRow(Map<String, dynamic>.from(r as Map)))
        .whereType<RewardDay>()
        .toList();
  }

  @override
  Future<double?> rewardAmount() async {
    // RLS returns the worker's own owner's row only.
    final rows = await _client.from('attendance_config').select('reward_amount').limit(1).timeout(_timeout);
    if (rows.isEmpty) return null;
    return (rows.first['reward_amount'] as num?)?.toDouble();
  }
}
