import 'dart:async';

import 'package:flutter/foundation.dart';

import 'auth/auth_repository.dart';
import 'auth/login_failure.dart';
import 'auth/worker_profile.dart';
import 'terms/terms_gates.dart';
import 'terms/terms_repository.dart';
import 'update/app_release.dart';
import 'update/app_update_repository.dart';

sealed class AppState {}

class Starting extends AppState {}

class SignedOut extends AppState {
  SignedOut({this.notice});
  final LoginFailure? notice;
}

class NeedsTerms extends AppState {
  NeedsTerms(this.worker);
  final WorkerProfile worker;
}

class TermsUnavailable extends AppState {
  TermsUnavailable(this.worker);
  final WorkerProfile worker;
}

class Ready extends AppState {
  Ready(this.worker);
  final WorkerProfile worker;
}

/// Startup, sign-in, Terms and the required-update check.
class AppController extends ChangeNotifier {
  AppController({required this.auth, required this.terms, required this.updates, required Stream<void> nudges}) {
    _nudgeSub = nudges.listen((_) => checkForUpdate());
  }

  final AuthRepository auth;
  final TermsRepository terms;
  final AppUpdateRepository updates;
  late final StreamSubscription<void> _nudgeSub;

  AppState _state = Starting();
  AppState get state => _state;

  AppRelease? _requiredUpdate;
  AppRelease? get requiredUpdate => _requiredUpdate;

  void _set(AppState s) {
    _state = s;
    notifyListeners();
  }

  Future<void> start() async {
    unawaited(checkForUpdate());
    WorkerProfile? worker;
    try {
      worker = await auth.currentWorker();
      if (worker == null) return _set(SignedOut());
      await _afterWorker(worker);
    } catch (_) {
      // Never strand the worker on the spinner: a resolved worker gets the
      // screen with TRY AGAIN and Log out, otherwise the login screen.
      _set(worker == null ? SignedOut() : TermsUnavailable(worker));
    }
  }

  Future<void> retryStartup() async {
    _set(Starting());
    await start();
  }

  Future<void> _afterWorker(WorkerProfile worker) async {
    // An account turned off since the last launch is told at the door.
    final eligibility = worker.eligibility();
    if (eligibility != Eligibility.allowed) {
      await auth.signOut();
      return _set(SignedOut(
          notice: eligibility == Eligibility.accountInactive ? LoginFailure.accountInactive : LoginFailure.notAWorker));
    }
    switch (await terms.startupDecision(worker)) {
      case StartupDecision.ready:
        _set(Ready(worker));
      case StartupDecision.mustAccept:
        _set(NeedsTerms(worker));
      case StartupDecision.unavailable:
        _set(TermsUnavailable(worker));
    }
  }

  /// Returns the failure to show, or null on success.
  Future<LoginFailure?> signIn(String email, String password) async {
    try {
      final worker = await auth.signIn(email, password);
      try {
        await _afterWorker(worker);
      } catch (e) {
        return LoginFailure.of(e);
      }
      return null;
    } on LoginRejected catch (e) {
      return e.failure;
    } catch (e) {
      return LoginFailure.of(e);
    }
  }

  Future<LoginFailure?> acceptTerms() async {
    final s = _state;
    if (s is! NeedsTerms) return null;
    try {
      await terms.accept(s.worker);
      _set(Ready(s.worker));
      return null;
    } catch (e) {
      return LoginFailure.of(e);
    }
  }

  Future<void> signOut() async {
    // Immediate feedback, and whatever happens the worker ends signed out.
    _set(Starting());
    try {
      await auth.signOut();
    } catch (_) {
      // The local session is cleared first; a failure must not strand the UI.
    } finally {
      _set(SignedOut());
    }
  }

  Future<void> checkForUpdate() async {
    try {
      final r = await updates.requiredRelease();
      if (r?.versionCode != _requiredUpdate?.versionCode) {
        _requiredUpdate = r;
        notifyListeners();
      }
    } catch (_) {
      // Keep whatever is already known; the next nudge or resume re-checks.
    }
  }

  @override
  void dispose() {
    _nudgeSub.cancel();
    super.dispose();
  }
}
