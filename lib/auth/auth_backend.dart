import 'dart:async';

import 'package:supabase_flutter/supabase_flutter.dart';

import 'session_gate.dart';
import 'worker_profile.dart';

/// The parts of Supabase auth the app relies on, behind an interface so the
/// sign-in and startup rules test without a server.
abstract class AuthBackend {
  /// Make the session from attendance-signin the client's own.
  Future<void> adopt({required String accessToken, required String refreshToken});

  Future<SessionPresence> presence();

  String? get currentUserId;

  /// The worker's profiles row, read AS the worker. Throws when it cannot be
  /// asked (no session, no signal); returns null only for "no such row".
  Future<Map<String, dynamic>?> readProfile(String userId);

  /// Changes THIS session's password. Only ever the worker signed in on this
  /// phone: there is no way to name anyone else.
  Future<void> changePassword(String newPassword);

  Future<void> signOut();
}

class SupabaseAuthBackend implements AuthBackend {
  SupabaseAuthBackend(this._client, this._storage);

  final SupabaseClient _client;
  final LocalStorage _storage;

  @override
  Future<void> adopt({required String accessToken, required String refreshToken}) async {
    // With an access token this validates it (one getUser call) and keeps
    // the pair; it only refreshes when the token is already expired.
    await _client.auth.setSession(refreshToken, accessToken: accessToken).timeout(const Duration(seconds: 20));
  }

  @override
  Future<SessionPresence> presence() async {
    // Supabase.initialize does not wait for the stored session to be
    // refreshed: gotrue has already loaded it into currentSession, even when
    // its access token expired hours ago, and a refresh is running behind it.
    final session = _client.auth.currentSession;
    if (session == null) {
      return await _storage.hasAccessToken() ? SessionPresence.unverifiable : SessionPresence.absent;
    }
    if (!session.isExpired) return SessionPresence.confirmed;
    // Expired: getSession() joins the refresh already in flight (gotrue
    // de-duplicates by refresh token) instead of spending the token twice.
    try {
      await _client.auth.getSession().timeout(const Duration(seconds: 10));
      return SessionPresence.confirmed;
    } on AuthRetryableFetchException {
      return SessionPresence.unverifiable; // no signal: cannot check, not a sign-out
    } on TimeoutException {
      return SessionPresence.unverifiable;
    } on AuthException {
      return SessionPresence.absent; // token revoked; gotrue already signed out
    } on Object {
      return SessionPresence.unverifiable; // an unexpected error is not a sign-out
    }
  }

  @override
  String? get currentUserId => _client.auth.currentUser?.id;

  @override
  Future<Map<String, dynamic>?> readProfile(String userId) async {
    // Without a session the client would send the anon key and RLS would
    // answer "no rows" -- a lie that looks like a missing worker.
    if (_client.auth.currentSession == null) throw StateError('No session to read the profile with');
    return _client.from('profiles').select(WorkerProfile.columns).eq('id', userId).maybeSingle().timeout(const Duration(seconds: 15));
  }

  @override
  Future<void> changePassword(String newPassword) async {
    // Without a session gotrue would fail with a message that reads as a password problem.
    if (_client.auth.currentSession == null) throw StateError('No session to change the password with');
    await _client.auth.updateUser(UserAttributes(password: newPassword)).timeout(const Duration(seconds: 20));
  }

  @override
  Future<void> signOut() async {
    try {
      // gotrue clears the local session first, then calls the server; on weak
      // signal that call may throw or hang, so it is bounded to 5 s and
      // neither outcome may keep the worker signed in.
      await _client.auth.signOut().timeout(const Duration(seconds: 5));
    } catch (_) {}
    await _storage.removePersistedSession();
  }
}
