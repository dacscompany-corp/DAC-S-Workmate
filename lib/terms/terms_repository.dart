import 'package:supabase_flutter/supabase_flutter.dart';

import '../auth/worker_cache.dart';
import '../auth/worker_profile.dart';
import 'attendance_terms.dart';
import 'terms_gates.dart';

abstract class TermsBackend {
  /// Throws when it cannot be asked. Never returns an empty set for
  /// "could not ask": that would send an accepted worker back to the Terms.
  Future<Set<String>> acceptedVersions(String workerId);

  /// When [workerId] accepted [version], or null when there is no such row.
  /// Throws when it cannot be asked.
  Future<DateTime?> acceptedAt(String workerId, String version);
  Future<void> insertEvidence(Map<String, dynamic> row);
  Future<void> insertAcceptance(Map<String, dynamic> row);
}

class SupabaseTermsBackend implements TermsBackend {
  SupabaseTermsBackend(this._client);

  final SupabaseClient _client;

  @override
  Future<Set<String>> acceptedVersions(String workerId) async {
    // Rows are readable only by their worker. Asked without a session, RLS
    // returns none and that looks like "never accepted" -- so refuse.
    if (_client.auth.currentSession == null) throw StateError('No session to read the Terms acceptance with');
    final rows = await _client.from('attendance_terms_acceptances').select('terms_version').eq('worker_id', workerId).timeout(const Duration(seconds: 15));
    return rows.map((r) => r['terms_version'] as String).toSet();
  }

  @override
  Future<DateTime?> acceptedAt(String workerId, String version) async {
    // Asked without a session RLS returns nothing, which would read as "never accepted".
    if (_client.auth.currentSession == null) throw StateError('No session to read the Terms acceptance with');
    final rows = await _client
        .from('attendance_terms_acceptances')
        .select('accepted_at')
        .eq('worker_id', workerId)
        .eq('terms_version', version)
        .limit(1)
        .timeout(const Duration(seconds: 15));
    if (rows.isEmpty) return null;
    return DateTime.tryParse(rows.first['accepted_at'].toString())?.toUtc();
  }

  @override
  Future<void> insertEvidence(Map<String, dynamic> row) => _client.from('agreement_events').insert(row).timeout(const Duration(seconds: 15));

  @override
  Future<void> insertAcceptance(Map<String, dynamic> row) => _client.from('attendance_terms_acceptances').insert(row).timeout(const Duration(seconds: 15));
}

bool isUniqueViolation(Object error) {
  if (error is PostgrestException && error.code == '23505') return true;
  final text = error.toString().toLowerCase();
  return text.contains('23505') || text.contains('duplicate key');
}

class TermsRepository {
  TermsRepository({required this.backend, required this.cache, required this.userAgent});

  final TermsBackend backend;
  final WorkerCache cache;
  final String userAgent;

  Future<StartupDecision> startupDecision(WorkerProfile worker) async {
    Set<String>? versions;
    try {
      versions = await backend.acceptedVersions(worker.id);
    } catch (_) {
      versions = null;
    }
    if (versions != null && versions.contains(AttendanceTerms.version)) {
      await cache.recordTermsAccepted(worker.id, AttendanceTerms.version);
    }
    return decideStartup(
      acceptedVersions: versions,
      cachedVersion: cache.acceptedTermsVersion(worker.id),
      currentVersion: AttendanceTerms.version,
    );
  }

  /// Evidence FIRST (agreement_events, append-only), then the flag the gate
  /// reads. A failure in between costs a harmless duplicate evidence row;
  /// the other order could mark a worker accepted with no record of what.
  Future<void> accept(WorkerProfile worker) async {
    await backend.insertEvidence({
      'user_id': worker.id,
      'email': worker.email,
      'audience': 'worker',
      'doc_type': 'attendance_terms',
      'doc_title': AttendanceTerms.title,
      'doc_sha256': AttendanceTerms.sha256Hex(),
      'doc_text': AttendanceTerms.canonicalText(),
      'user_agent': userAgent,
    });
    try {
      await backend.insertAcceptance({'worker_id': worker.id, 'terms_version': AttendanceTerms.version});
    } catch (e) {
      if (!isUniqueViolation(e)) rethrow;
    }
    await cache.recordTermsAccepted(worker.id, AttendanceTerms.version);
  }

  /// When this worker accepted the CURRENT Terms, as the server recorded it.
  /// The phone's copy first (only if it is for this version); null when it
  /// cannot be known -- an invented acceptance date is worse than none.
  Future<DateTime?> acceptedAt(String workerId) async {
    final cached = cache.termsAcceptedAt(workerId, AttendanceTerms.version);
    if (cached != null) return cached;
    try {
      final at = await backend.acceptedAt(workerId, AttendanceTerms.version);
      if (at != null) await cache.recordTermsAcceptedAt(workerId, AttendanceTerms.version, at);
      return at;
    } catch (_) {
      return null;
    }
  }
}
