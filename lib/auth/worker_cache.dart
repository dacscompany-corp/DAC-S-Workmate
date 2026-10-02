import 'dart:convert';

import 'package:shared_preferences/shared_preferences.dart';

import 'worker_profile.dart';

/// What this device witnessed: who signed in, their profile, and the Terms
/// version it saw them accept. Offline, the auth client can report nobody
/// for a session it holds; this is what keeps a worker signed in on a
/// no-signal site. Set at sign-in, cleared at sign-out, nowhere else.
class WorkerCache {
  WorkerCache(this._prefs);

  final SharedPreferences _prefs;

  static const _lastKey = 'last_signed_in_id';
  static String _profileKey(String id) => 'worker.$id';
  static String _termsKey(String id) => 'terms.$id';
  static String _termsAtKey(String id) => 'terms_at.$id';

  String? get lastSignedInId => _prefs.getString(_lastKey);

  Future<void> remember(WorkerProfile worker) async {
    await _prefs.setString(_lastKey, worker.id);
    await _prefs.setString(_profileKey(worker.id), jsonEncode(worker.toRow()));
  }

  WorkerProfile? recall(String id) {
    final raw = _prefs.getString(_profileKey(id));
    return raw == null ? null : WorkerProfile.fromRow(jsonDecode(raw) as Map<String, dynamic>);
  }

  String? acceptedTermsVersion(String id) => _prefs.getString(_termsKey(id));

  Future<void> recordTermsAccepted(String id, String version) => _prefs.setString(_termsKey(id), version);

  /// When the server recorded this worker's acceptance of Terms [version]
  /// (Profile shows it). Stored as `version|ms` so a date remembered for
  /// an older version is never shown for a newer one. Never invented: null
  /// until the server said, for another version, or if the value is malformed.
  DateTime? termsAcceptedAt(String id, String version) {
    final raw = _prefs.getString(_termsAtKey(id));
    if (raw == null) return null;
    final cut = raw.lastIndexOf('|');
    if (cut < 0 || raw.substring(0, cut) != version) return null;
    final ms = int.tryParse(raw.substring(cut + 1));
    return ms == null ? null : DateTime.fromMillisecondsSinceEpoch(ms, isUtc: true);
  }

  Future<void> recordTermsAcceptedAt(String id, String version, DateTime at) => _prefs.setString(_termsAtKey(id), '$version|${at.millisecondsSinceEpoch}');

  /// Site phones are shared: nothing about a worker outlives their sign-out.
  Future<void> forget(String id) async {
    await _prefs.remove(_profileKey(id));
    await _prefs.remove(_termsKey(id));
    await _prefs.remove(_termsAtKey(id));
    if (lastSignedInId == id) await _prefs.remove(_lastKey);
  }
}
