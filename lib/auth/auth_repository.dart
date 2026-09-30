import 'auth_backend.dart';
import 'login_failure.dart';
import 'session_gate.dart';
import 'sign_in_api.dart';
import 'worker_cache.dart';
import 'worker_profile.dart';

class LoginRejected implements Exception {
  LoginRejected(this.failure);
  final LoginFailure failure;
  @override
  String toString() => 'LoginRejected(${failure.name})';
}

class AuthRepository {
  AuthRepository({required this.api, required this.backend, required this.cache});

  final SignInApi api;
  final AuthBackend backend;
  final WorkerCache cache;

  /// The function checks credentials AND eligibility before any token
  /// exists, so a success is always an active worker.
  Future<WorkerProfile> signIn(String email, String password) async {
    final trimmed = email.trim();
    if (trimmed.isEmpty || password.isEmpty) throw LoginRejected(LoginFailure.missingFields);

    final SignInOutcome outcome;
    try {
      outcome = await api.signIn(trimmed, password);
    } catch (e) {
      throw LoginRejected(LoginFailure.of(e));
    }

    switch (outcome) {
      case SignInRefused(:final code):
        throw LoginRejected(LoginFailure.forCode(code));
      case SignInSuccess():
        try {
          await backend.adopt(accessToken: outcome.accessToken, refreshToken: outcome.refreshToken);
        } catch (e) {
          throw LoginRejected(LoginFailure.of(e));
        }
        // Cached here: sign-in is the one moment there is surely signal, and
        // the FIRST offline launch needs this to not land on the login screen.
        await cache.remember(outcome.worker);
        return outcome.worker;
    }
  }

  /// Forgets the worker BEFORE the session goes, while the id is readable.
  /// Offline the client reports nobody, so the cached id is the fallback.
  Future<void> signOut() async {
    final id = backend.currentUserId ?? cache.lastSignedInId;
    if (id != null) await cache.forget(id);
    await backend.signOut();
  }

  /// Who is signed in: the server's answer when it can be asked as the
  /// worker, otherwise the last profile this device saw, otherwise nobody.
  Future<WorkerProfile?> currentWorker() async {
    final lastId = cache.lastSignedInId;
    final decision = decideSession(await backend.presence(), hasLastKnownWorker: lastId != null);
    switch (decision) {
      case SessionDecision.askTheServer:
        final id = backend.currentUserId ?? lastId;
        if (id == null) return null;
        try {
          final row = await backend.readProfile(id);
          if (row == null) return null;
          final worker = WorkerProfile.fromRow(row);
          await cache.remember(worker);
          return worker;
        } catch (_) {
          // No signal, or a token the server rejects while the client still
          // believes in it (a phone with a badly wrong clock): not a sign-out.
          return cache.recall(id);
        }
      case SessionDecision.useLastKnown:
        return lastId == null ? null : cache.recall(lastId);
      case SessionDecision.signedOut:
        return null;
    }
  }
}
