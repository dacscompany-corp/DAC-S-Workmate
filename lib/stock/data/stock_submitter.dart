import 'package:flutter/foundation.dart';

import '../domain/stock_failure.dart';
import '../domain/stock_submission.dart';
import 'stock_pending_store.dart';
import 'stock_remote.dart';

enum StockSendResult {
  /// The server answered: it is recorded (or was already — the same answer).
  recorded,

  /// Refused, and nothing can still record it: its first Send was refused,
  /// or the server holds its id cancelled (OP_CANCELLED).
  refused,

  /// Not known: the answer was lost, or a Send again was refused while the
  /// first Send might still arrive. It stays, unchanged, until settled (R101).
  unsure,

  /// Another unresolved stock submission must be settled first (R101).
  blocked,
}

class StockSendOutcome {
  const StockSendOutcome(this.result, {this.opId, this.failure, this.answer});
  final StockSendResult result;

  /// The submission it is about (null when blocked).
  final String? opId;
  final StockFailure? failure;
  final Map<String, dynamic>? answer;
}

/// What the server says about an unresolved submission's id (R102).
enum StockSettleResult {
  /// Recorded, once, under this id: nothing to change.
  recorded,

  /// Cancelled for good — no request with this id can record it any more:
  /// only now may it be changed (a new submission) or dropped.
  cancelled,

  /// (Check only) the server has neither: it may still arrive. Send again,
  /// or Cancel it.
  pending,

  /// No answer (no signal): nothing known, nothing changed.
  unknown,
}

class StockSettleOutcome {
  const StockSettleOutcome(this.result, {this.failure});
  final StockSettleResult result;
  final StockFailure? failure;
}

/// Sends every stock record from the phone (R101–R103). Each submission is
/// saved BEFORE it leaves, with its operation id and exact payload; a lost
/// answer leaves it saved and unchanged. It is settled only by the SERVER:
/// a reply, a refusal of its first Send, or — asked by Check (read only,
/// `pur_op_state`) or Cancel (`pur_op_cancel`, under the same lock recording
/// takes) — the id recorded or cancelled for good. Until then: no edit, no new
/// stock submission for that account, nothing sent by itself. A saved entry
/// the phone can no longer read is kept and blocks new sends too (R104): by
/// its id it can still be checked or cancelled; without one it needs recovery.
class StockSubmitter extends ChangeNotifier {
  StockSubmitter({required this.remote, required this.store, DateTime Function()? now}) : _now = now ?? DateTime.now;

  final StockRemote remote;
  final StockPendingStore store;
  final DateTime Function() _now;

  List<StockSubmission> _all = const [];
  List<UnreadableSubmission> _unreadable = const [];
  bool _damaged = false;
  String? _userId;
  final _busy = <String>{};
  bool _disposed = false;

  /// The signed-in account's unresolved submissions, oldest first.
  List<StockSubmission> get unresolved => [
        for (final s in _all)
          if (s.userId == _userId) s,
      ];

  /// This account's saved entries that no longer read in full but whose id
  /// does: the server can settle each by Check or Cancel (R104).
  List<UnreadableSubmission> get unreadable => [
        for (final u in _unreadable)
          if (u.settleable && u.userId == _userId) u,
      ];

  /// Saved stock data the phone cannot read and cannot settle by id — the
  /// whole store, an entry with no readable account (it could be anyone's),
  /// or one of this account's with no readable operation id (R104).
  bool get recoveryNeeded =>
      _damaged || _unreadable.any((u) => u.userId == null || (u.userId == _userId && u.opId == null));

  /// No new stock submission until every one of these is settled.
  bool get blocked => unresolved.isNotEmpty || unreadable.isNotEmpty || recoveryNeeded;
  bool isBusy(String opId) => _busy.contains(opId);
  StockSubmission? byOp(String opId) => unresolved.where((s) => s.opId == opId).firstOrNull;

  /// Reads what is waiting on the phone for [userId]; never sends.
  Future<void> load(String userId) async {
    _userId = userId;
    await _reload();
    _notify();
  }

  Future<void> _reload() async {
    final l = await store.load();
    _all = l.readable;
    _unreadable = l.unreadable;
    _damaged = l.damaged;
  }

  /// A new stock record. Refused while this account has one unresolved.
  Future<StockSendOutcome> submit({
    required StockWrite write,
    required Map<String, dynamic> Function(String opId) params,
    required String summary,
  }) async {
    final userId = _userId;
    if (userId == null) throw StateError('load() first');
    if (blocked) return const StockSendOutcome(StockSendResult.blocked);
    final opId = newStockOpId();
    final s = StockSubmission.create(opId: opId, userId: userId, write: write, params: params(opId), summary: summary, now: _now());
    return _send(s);
  }

  /// Send again: the saved submission, byte for byte — never the form.
  Future<StockSendOutcome> retry(String opId) async {
    final s = byOp(opId);
    if (s == null) return StockSendOutcome(StockSendResult.recorded, opId: opId);
    return _send(s);
  }

  Future<StockSendOutcome> _send(StockSubmission s) async {
    if (!_busy.add(s.opId)) return StockSendOutcome(StockSendResult.unsure, opId: s.opId);
    _notify();
    try {
      // Sent before? Then that Send might still arrive.
      final sentBefore = s.lastSentAt != null;
      final sent = s.sentAt(_now());
      try {
        await _put(sent);
      } catch (_) {
        // Not saved, so not sent. The phone cannot keep stock records safely:
        // nothing new is sent until that is fixed (R104).
        _damaged = true;
        if (!sentBefore) {
          // A new one: nothing left the phone — refused, the form stays editable.
          _all = [..._all.where((x) => x.opId != s.opId)];
          return StockSendOutcome(StockSendResult.refused, opId: s.opId, failure: StockFailure.unexpected);
        }
        return StockSendOutcome(StockSendResult.unsure, opId: s.opId, failure: StockFailure.unexpected);
      }
      try {
        final answer = await remote.write(sent.write, sent.params, userId: sent.userId);
        await _drop(sent.opId);
        return StockSendOutcome(StockSendResult.recorded, opId: s.opId, answer: answer);
      } catch (e) {
        final f = StockFailure.of(e);
        if (f.uncertain) return StockSendOutcome(StockSendResult.unsure, opId: s.opId, failure: f);
        // A refusal settles it only if no earlier Send of it can still arrive
        // — or the server says the id itself is cancelled (R102).
        if (sentBefore && f != StockFailure.opCancelled) {
          return StockSendOutcome(StockSendResult.unsure, opId: s.opId, failure: f);
        }
        await _drop(sent.opId);
        return StockSendOutcome(StockSendResult.refused, opId: s.opId, failure: f);
      }
    } finally {
      _busy.remove(s.opId);
      _notify();
    }
  }

  /// Check: asks the server, read only; never sends, never cancels.
  Future<StockSettleOutcome> check(String opId) => _settle(opId, cancel: false);

  /// Cancel it: the server settles the id — recorded (nothing changes) or
  /// cancelled for good. Only a 'cancelled' answer lets it be changed or dropped.
  Future<StockSettleOutcome> cancel(String opId) => _settle(opId, cancel: true);

  Future<StockSettleOutcome> _settle(String opId, {required bool cancel}) async {
    final s = byOp(opId);
    // An unreadable entry is settled by its id alone — its payload is never rebuilt (R104).
    final u = s == null ? unreadable.where((x) => x.opId == opId).firstOrNull : null;
    final userId = s?.userId ?? u?.userId;
    if (userId == null) return const StockSettleOutcome(StockSettleResult.recorded);
    if (!_busy.add(opId)) return const StockSettleOutcome(StockSettleResult.unknown);
    _notify();
    try {
      final String state;
      try {
        state = cancel ? await remote.cancelOp(opId, userId: userId) : await remote.opState(opId, userId: userId);
      } catch (e) {
        return StockSettleOutcome(StockSettleResult.unknown, failure: StockFailure.of(e));
      }
      if (u != null) {
        final result = switch (state) {
          'recorded' => StockSettleResult.recorded,
          'cancelled' => StockSettleResult.cancelled,
          'none' when !cancel => StockSettleResult.pending,
          _ => StockSettleResult.unknown,
        };
        if (result == StockSettleResult.recorded || result == StockSettleResult.cancelled) {
          try {
            await store.dropUnreadable(userId, opId);
            await _reload();
          } catch (_) {
            // Not removed from the phone: it stays (and blocks) until it can be.
            return const StockSettleOutcome(StockSettleResult.unknown, failure: StockFailure.unexpected);
          }
        }
        return StockSettleOutcome(result, failure: result == StockSettleResult.unknown ? StockFailure.unexpected : null);
      }
      final result = switch (state) {
        'recorded' => StockSettleResult.recorded,
        'cancelled' => StockSettleResult.cancelled,
        'none' when !cancel => StockSettleResult.pending,
        _ => StockSettleResult.unknown,
      };
      if (result == StockSettleResult.recorded || result == StockSettleResult.cancelled) await _drop(opId);
      return StockSettleOutcome(result, failure: result == StockSettleResult.unknown ? StockFailure.unexpected : null);
    } finally {
      _busy.remove(opId);
      _notify();
    }
  }

  /// Checks every unresolved one (on open and on coming back): read only —
  /// one the server settled (recorded, or cancelled) goes; the rest stay.
  Future<void> checkAll() async {
    for (final s in unresolved) {
      if (!isBusy(s.opId)) await check(s.opId);
    }
    for (final u in unreadable) {
      if (!isBusy(u.opId!)) await check(u.opId!);
    }
  }

  Future<void> _put(StockSubmission s) async {
    final next = [for (final x in _all) x.opId == s.opId ? s : x];
    if (!next.any((x) => x.opId == s.opId)) next.add(s);
    await store.save(next);
    _all = next;
  }

  Future<void> _drop(String opId) async {
    final next = [..._all.where((x) => x.opId != opId)];
    try {
      await store.save(next);
      _all = next;
    } catch (_) {
      // Could not be removed from the phone: it stays unresolved (a Check
      // settles it again later) and nothing new is sent meanwhile.
      _damaged = true;
    }
  }

  void _notify() {
    if (!_disposed) notifyListeners();
  }

  @override
  void dispose() {
    _disposed = true;
    super.dispose();
  }
}
