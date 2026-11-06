import 'dart:async';
import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import 'password_change.dart';

const _timeout = Duration(seconds: 15);

/// What the server says about an account's temporary password (0111, 0112).
class PasswordOwed {
  const PasswordOwed({required this.mustChange, this.resetId});

  final bool mustChange;

  /// The open reset (0112's `reset_id`): the one a change confirms. Null when
  /// none is open — or when the server has no 0112, so nothing can be confirmed.
  final int? resetId;
}

/// What the password prompt needs (3b, Q3): the server's records of a
/// temporary password, and this phone's notes of changes it made. Every call
/// names the account it is for, and is refused (AUTH_REQUIRED) unless that
/// account is the one signed in: a shared phone never asks or confirms for
/// one account with another's sign-in.
class PasswordPromptServices {
  const PasswordPromptServices({required this.owed, required this.confirm, required this.changePassword, required this.notes});

  /// `wk_password_state`, for [userId].
  final Future<PasswordOwed> Function(String userId) owed;

  /// `wk_password_changed_for` (0112): confirms the change of that one reset,
  /// for [userId]; true when it recorded it. A reset that is no longer open —
  /// confirmed already, or replaced by a newer reset — records nothing.
  final Future<bool> Function(String userId, int resetId) confirm;

  /// Saves [userId]'s new password — and only theirs: see [boundChange].
  final Future<void> Function(String userId, String newPassword) changePassword;
  final PasswordNotes notes;

  /// The password change, bound to the account the prompt was opened for.
  /// Supabase changes the password of whoever is signed in when the request
  /// leaves; so who that is is read in the same step as the request is made —
  /// with nothing in between that could let another account sign in — and
  /// anyone else's sign-in is refused before anything is sent. The answer must
  /// name the same account. Refusals read as a session problem ("Please log in
  /// again."), never as a password problem.
  static Future<void> Function(String userId, String newPassword) boundChange({
    required String? Function() signedIn,
    required Future<String?> Function(String newPassword) change,
  }) =>
      (userId, newPassword) async {
        if (signedIn() != userId) throw StateError('Not this account\'s session: the password was not changed');
        final changed = await change(newPassword);
        if (changed != userId) throw StateError('The password change answered for another session');
      };

  /// Every function the prompt calls, with its parameter names.
  static const calls = <String, List<String>>{
    'wk_password_state': [],
    'wk_password_changed_for': ['p_reset'],
  };

  factory PasswordPromptServices.supabase(SupabaseClient client, SharedPreferences prefs) {
    void same(String userId) {
      final session = client.auth.currentUser?.id;
      if (session == null || session != userId) throw StateError('AUTH_REQUIRED');
    }

    return PasswordPromptServices(
      owed: (userId) async {
        same(userId);
        final r = Map<String, dynamic>.from(await client.rpc('wk_password_state').timeout(_timeout) as Map);
        return PasswordOwed(mustChange: r['must_change'] == true, resetId: (r['reset_id'] as num?)?.toInt());
      },
      confirm: (userId, resetId) async {
        same(userId);
        final r = await client.rpc('wk_password_changed_for', params: {'p_reset': resetId}).timeout(_timeout);
        return (r as Map)['recorded'] == true;
      },
      // gotrue's updateUser takes the signed-in session's token before it
      // awaits anything (gotrue 2.27), so the check and the token are one step.
      changePassword: boundChange(
        signedIn: () => client.auth.currentUser?.id,
        change: (newPassword) async =>
            (await client.auth.updateUser(UserAttributes(password: newPassword)).timeout(const Duration(seconds: 20))).user?.id,
      ),
      notes: PasswordNotes(prefs),
    );
  }
}

/// "Changed on this phone, not yet confirmed": each note names its account and
/// the reset it answers. The new password is saved; only the server's record
/// of it is missing. It is confirmed for that reset only, with that account
/// signed in — and never asks the worker again for it.
class PasswordNotes {
  PasswordNotes(this._prefs);

  static const key = 'password.changed_unconfirmed.v1';
  final SharedPreferences _prefs;

  List<(String, int)> _entries() {
    try {
      final v = jsonDecode(_prefs.getString(key) ?? '[]');
      if (v is! List) return const [];
      return [
        for (final e in v)
          if (e is Map && e['user'] is String && e['reset'] is int) (e['user'] as String, e['reset'] as int),
      ];
    } on FormatException {
      return const [];
    }
  }

  Future<void> _save(List<(String, int)> entries) async {
    final ok = await _prefs.setString(key, jsonEncode([for (final (u, r) in entries) {'user': u, 'reset': r}]));
    if (!ok) throw StateError('PASSWORD_NOTE_NOT_SAVED');
  }

  /// This account's changes still to confirm, each by its own reset.
  List<int> pending(String userId) => [for (final (u, r) in _entries()) if (u == userId) r];

  Future<void> add(String userId, int resetId) async {
    final entries = _entries();
    if (!entries.contains((userId, resetId))) await _save([...entries, (userId, resetId)]);
  }

  Future<void> remove(String userId, int resetId) => _save([for (final e in _entries()) if (e != (userId, resetId)) e]);
}

enum PasswordPromptState {
  /// Not answered yet (no signal since the app opened): nothing is asked.
  unknown,

  /// No temporary password is waiting to be changed.
  notOwed,

  /// A temporary password is waiting: the prompt is wanted, for [PasswordPrompt.resetId].
  owed,

  /// Changed on this phone; its confirmation is still to reach the server.
  /// Nothing is asked meanwhile: the server decides once it can be reached.
  changedNotRecorded,

  /// Changed and confirmed.
  done,
}

/// The forced change of a temporary password (P1 = A): forced while there is
/// signal, never in the way of attendance. With no signal — to ask, or to
/// save — Home stays reachable and the prompt comes back once a later check
/// reaches the server. After a failed save the worker may continue: a no-signal
/// failure is asked again at the next answer from the server, any other
/// failure (the server's fault) after [pauseAfterServerFault], so a broken
/// server never nags every minute.
///
/// A change confirms the reset it answers, for its own account (0112): a
/// confirmation sent late never closes a newer reset, and a note of one
/// account's change is never sent with another's sign-in. After confirming,
/// the server says what is owed now — so a newer reset's prompt is kept.
class PasswordPrompt extends ChangeNotifier {
  PasswordPrompt({
    required this.services,
    required this.userId,
    DateTime Function()? now,
    this.recheckEvery = const Duration(minutes: 2),
    this.pauseAfterServerFault = const Duration(minutes: 15),
  }) : _now = now ?? DateTime.now;

  final PasswordPromptServices services;

  /// The account the prompt was opened for: every call — the password change
  /// itself included — is for this account only.
  final String userId;
  final DateTime Function() _now;
  final Duration recheckEvery;
  final Duration pauseAfterServerFault;

  PasswordPromptState state = PasswordPromptState.unknown;
  int? _resetId;
  DateTime? _pausedUntil;
  bool _checking = false;
  bool _disposed = false;
  Timer? _timer;

  /// The reset the prompt is for, while owed.
  int? get resetId => _resetId;

  /// Paused: the worker continued after a failed save.
  bool get paused => _pausedUntil != null;

  /// Show the prompt now (Home decides when: never over a Time In).
  bool get wanted => state == PasswordPromptState.owed && !paused;

  /// Confirms what this phone changed, then asks what is owed now. Never
  /// throws: no answer changes nothing, and the timer asks again.
  Future<void> check() async {
    if (_checking || _disposed || state == PasswordPromptState.notOwed || state == PasswordPromptState.done) return;
    _checking = true;
    try {
      await _confirmNotes();
      _apply(await services.owed(userId));
      // An answer from the server: signal is back. A pause ends now, or — for
      // a server fault — once its time is up.
      final until = _pausedUntil;
      if (until != null && !_now().isBefore(until)) _pausedUntil = null;
    } catch (e) {
      debugPrint('Password check: no answer ($e)');
      if (services.notes.pending(userId).isNotEmpty) state = PasswordPromptState.changedNotRecorded;
    } finally {
      _checking = false;
      _schedule();
      _notify();
    }
  }

  /// Saves the new password — for the account the prompt was opened for, and
  /// no other — then confirms it for the reset the prompt was for. Throws what
  /// went wrong (PasswordChangeFailure.of explains it) if the password wasn't
  /// saved; after that, nothing throws.
  Future<void> save(String newPassword) async {
    final reset = _resetId;
    if (state != PasswordPromptState.owed || reset == null) throw StateError('NOTHING_OWED');
    await services.changePassword(userId, newPassword);
    try {
      await services.notes.add(userId, reset);
    } catch (e) {
      debugPrint('Password note not kept: $e');
    }
    state = PasswordPromptState.changedNotRecorded;
    _resetId = null;
    _pausedUntil = null;
    try {
      await services.confirm(userId, reset);
      await services.notes.remove(userId, reset);
      _apply(await services.owed(userId), changedHere: true);
    } catch (e) {
      // The password is changed; only its confirmation waits. Not asked again for it.
      debugPrint('Password change not confirmed yet: $e');
    }
    _schedule();
    _notify();
  }

  /// A change this phone made that the server hasn't confirmed: confirmed for
  /// its own reset, with its own account. Whatever the answer — recorded now,
  /// recorded before, or that reset replaced by a newer one — it is settled,
  /// and what is owed next is the server's answer that follows.
  Future<void> _confirmNotes() async {
    final pending = services.notes.pending(userId);
    for (final reset in pending) {
      await services.confirm(userId, reset);
      await services.notes.remove(userId, reset);
    }
    if (pending.isNotEmpty && state == PasswordPromptState.changedNotRecorded) state = PasswordPromptState.unknown;
  }

  void _apply(PasswordOwed o, {bool changedHere = false}) {
    if (_disposed) return;
    if (o.mustChange && o.resetId != null) {
      state = PasswordPromptState.owed;
      _resetId = o.resetId;
    } else {
      // Nothing open — or a server without 0112: nothing could be confirmed, so nothing is asked.
      if (o.mustChange) debugPrint('Password: a change is owed, but the server names no reset (0112 missing)');
      state = changedHere ? PasswordPromptState.done : PasswordPromptState.notOwed;
      _resetId = null;
    }
  }

  /// "Continue for now", offered only after a save failed for a reason other
  /// than what was typed: Home again, and the prompt waits for the server.
  void continueForNow(PasswordChangeFailure why) {
    final now = _now();
    _pausedUntil = why == PasswordChangeFailure.noConnection ? now : now.add(pauseAfterServerFault);
    _schedule();
    _notify();
  }

  /// Asks again on a timer only while something is still open.
  void _schedule() {
    final open = state == PasswordPromptState.unknown ||
        state == PasswordPromptState.changedNotRecorded ||
        (state == PasswordPromptState.owed && paused);
    if (!open || _disposed) {
      _timer?.cancel();
      _timer = null;
    } else {
      _timer ??= Timer.periodic(recheckEvery, (_) => check());
    }
  }

  void _notify() {
    if (!_disposed) notifyListeners();
  }

  @override
  void dispose() {
    _disposed = true;
    _timer?.cancel();
    super.dispose();
  }
}
