import 'dart:async';
import 'dart:io';

import 'package:shared_preferences/shared_preferences.dart';
import 'package:workmate/profile/password_prompt.dart';

/// The server's password records (0111 + 0112) for every account, and
/// Supabase's password change, in memory — with one phone's sign-in
/// ([session]) and signal that can drop. As on live: a reset is a numbered
/// `temporary_set`; it stays open until a change names it; a confirmation of
/// any other reset records nothing; and every call is refused (AUTH_REQUIRED)
/// for an account that isn't the one signed in, as PasswordPromptServices.supabase does.
class FakePasswordServer {
  FakePasswordServer({this.session = 'u7'});

  /// Who is signed in on this phone now.
  String session;

  /// No signal: every call fails as a dropped connection.
  bool offline = false;

  /// Thrown by the next password change (after the network was reached).
  Object? failNextChange;

  /// The next confirmation never reaches the server (this is thrown).
  Object? failNextConfirm;

  /// The next confirmation is recorded, then its answer is lost (thrown).
  Object? loseNextConfirmAnswer;

  final _resets = <String, List<int>>{};
  final _closed = <String, Set<int>>{};
  int _id = 0;
  int owedCalls = 0;
  int confirmCalls = 0;

  /// Every confirmation that reached the server: (account, reset).
  final confirmations = <(String, int)>[];

  /// New passwords saved, per account.
  final changedTo = <String, List<String>>{};

  /// The main owner sets a temporary password for [user]: a new reset.
  int reset(String user) {
    final r = ++_id;
    (_resets[user] ??= []).add(r);
    return r;
  }

  /// [user]'s open reset: their latest, unless a change named it (0112).
  int? openReset(String user) {
    final all = _resets[user];
    if (all == null || all.isEmpty) return null;
    return (_closed[user] ?? const {}).contains(all.last) ? null : all.last;
  }

  /// Changes recorded for [user] (rows of kind "changed").
  int changes(String user) => (_closed[user] ?? const {}).length;

  void _reach(String userId) {
    if (offline) throw const SocketException('no signal');
    if (session != userId) throw StateError('AUTH_REQUIRED');
  }

  Future<PasswordOwed> owed(String userId) async {
    owedCalls++;
    _reach(userId);
    final r = openReset(userId);
    return PasswordOwed(mustChange: r != null, resetId: r);
  }

  Future<bool> confirm(String userId, int resetId) async {
    confirmCalls++;
    _reach(userId);
    final f = failNextConfirm;
    if (f != null) {
      failNextConfirm = null;
      throw f;
    }
    confirmations.add((userId, resetId));
    final recorded = openReset(userId) == resetId;
    if (recorded) (_closed[userId] ??= {}).add(resetId);
    final lost = loseNextConfirmAnswer;
    if (lost != null) {
      loseNextConfirmAnswer = null;
      throw lost;
    }
    return recorded;
  }

  /// Supabase's own password change, as gotrue does it: it changes the
  /// password of WHOEVER IS SIGNED IN when the request leaves, and answers
  /// with that account. No account check here — that is the app's job.
  Future<String> goTrueChange(String to) async {
    if (offline) throw const SocketException('no signal');
    final f = failNextChange;
    if (f != null) {
      failNextChange = null;
      throw f;
    }
    (changedTo[session] ??= []).add(to);
    return session;
  }

  /// Profile's change (the signed-in account's own, unbound).
  Future<void> changePassword(String to) => goTrueChange(to);

  /// The prompt's services, with the app's own account-bound password change
  /// (PasswordPromptServices.boundChange) over gotrue's behaviour above.
  PasswordPromptServices services(SharedPreferences prefs) => PasswordPromptServices(
        owed: owed,
        confirm: confirm,
        changePassword: PasswordPromptServices.boundChange(signedIn: () => session, change: goTrueChange),
        notes: PasswordNotes(prefs),
      );
}

/// A lost answer, as the phone sees it.
TimeoutException lostAnswer() => TimeoutException('answer lost');
