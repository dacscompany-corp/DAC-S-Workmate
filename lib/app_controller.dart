import 'dart:async';

import 'package:flutter/foundation.dart';

import 'auth/auth_repository.dart';
import 'auth/login_failure.dart';
import 'auth/worker_profile.dart';
import 'auth/workmate_access.dart';
import 'purchasing/buyer_access.dart';
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

/// 2A-3b: an office account that may buy. Shopping list · My purchases ·
/// Profile (Q2). Never the Attendance Terms (Q23), never attendance: every
/// worker part of the app keys on [Ready] and so stays off.
class BuyerReady extends AppState {
  BuyerReady(this.worker);
  final WorkerProfile worker;
}

/// 2A-3a R2: this phone knew the account as a buyer and the Buyer switch is
/// now off. Unsent purchases stay on the phone.
class BuyingOff extends AppState {
  BuyingOff(this.worker);
  final WorkerProfile worker;
}

/// First launch with no signal: whether the account may buy cannot be
/// checked, and is never assumed.
class BuyerUnavailable extends AppState {
  BuyerUnavailable(this.worker);
  final WorkerProfile worker;
}

/// Startup, sign-in, Terms and the required-update check.
class AppController extends ChangeNotifier {
  AppController({
    required this.auth,
    required this.terms,
    required this.updates,
    required Stream<void> nudges,
    this.buyers,
  }) {
    _nudgeSub = nudges.listen((_) => checkForUpdate());
  }

  final AuthRepository auth;
  final TermsRepository terms;
  final AppUpdateRepository updates;

  /// 2A-3b. Null: an office account is turned away as before 0101.
  final BuyerAccess? buyers;
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
      _set(worker == null
          ? SignedOut()
          : (!worker.isWorker && buyers != null)
              ? BuyerUnavailable(worker)
              : TermsUnavailable(worker));
    }
  }

  Future<void> retryStartup() async {
    _set(Starting());
    await start();
  }

  Future<void> _afterWorker(WorkerProfile worker, {WorkMateAccess access = WorkMateAccess.worker}) async {
    final buyers = this.buyers;
    if (!worker.isWorker && buyers != null) return _afterBuyer(worker, buyers, letIn: access == WorkMateAccess.buyer);
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

  /// An office account (2A-3a): the server's buying answer, or this phone's
  /// last copy of it offline. Buyers skip the Attendance Terms (Q23).
  Future<void> _afterBuyer(WorkerProfile worker, BuyerAccess buyers, {required bool letIn}) async {
    if (!worker.isActive) {
      await auth.signOut();
      await buyers.forget(worker.id);
      return _set(SignedOut(notice: LoginFailure.accountInactive));
    }
    // The function just let this account in as a buyer: a launch offline
    // straight after still gets in.
    if (letIn) await buyers.letIn(worker.id);
    switch (await buyers.decide(worker.id)) {
      case BuyerDecision.canBuy:
        _set(BuyerReady(worker));
      case BuyerDecision.turnedOff:
        _set(BuyingOff(worker));
      case BuyerDecision.neverABuyer:
        await auth.signOut();
        await buyers.forget(worker.id);
        _set(SignedOut(notice: LoginFailure.noWorkMateAccess));
      case BuyerDecision.unknown:
        _set(BuyerUnavailable(worker));
    }
  }

  /// A buying screen was refused BUYER_REQUIRED (R2): the switch went off
  /// while the app was open. Nothing else changes; unsent purchases stay.
  Future<void> buyingTurnedOff() async {
    final s = _state;
    if (s is! BuyerReady) return;
    await buyers?.markTurnedOff(s.worker.id);
    _set(BuyingOff(s.worker));
  }

  /// Returns the failure to show, or null on success.
  Future<LoginFailure?> signIn(String email, String password) async {
    try {
      final signedIn = await auth.signIn(email, password);
      try {
        await _afterWorker(signedIn.worker, access: signedIn.access);
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
    final buyer = switch (_state) {
      BuyerReady(:final worker) || BuyingOff(:final worker) || BuyerUnavailable(:final worker) => worker.id,
      _ => null,
    };
    // Immediate feedback, and whatever happens the worker ends signed out.
    _set(Starting());
    try {
      if (buyer != null) await buyers?.forget(buyer);
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
