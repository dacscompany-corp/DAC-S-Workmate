import 'package:flutter/foundation.dart';

import '../domain/tool_failure.dart';
import '../domain/tool_submission.dart';
import 'tool_pending_store.dart';
import 'tools_remote.dart';

enum ToolSendResult {
  /// The server answered: it is recorded (or was already — the same answer).
  recorded,

  /// Refused, and nothing can still record it: its first Send was refused,
  /// or the server holds its id cancelled (OP_CANCELLED).
  refused,

  /// Not known: the answer was lost, or a Send again was refused while the
  /// first Send might still arrive. It stays, unchanged, until settled (R101).
  unsure,

  /// Another unresolved tool submission must be settled first (R101).
  blocked,
}

class ToolSendOutcome {
  const ToolSendOutcome(this.result, {this.opId, this.failure, this.answer});
  final ToolSendResult result;

  /// The submission it is about (null when blocked).
  final String? opId;
  final ToolFailure? failure;
  final Map<String, dynamic>? answer;
}

/// What the server says about an unresolved submission's id (R102).
enum ToolSettleResult {
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

class ToolSettleOutcome {
  const ToolSettleOutcome(this.result, {this.failure});
  final ToolSettleResult result;
  final ToolFailure? failure;
}

/// Sends every tool record from the phone (Q22: stock's rule, R101–R104 —
/// this is stock's StockSubmitter word for word, for tools, so the published
/// stock code stays untouched). Each submission is
/// saved BEFORE it leaves, with its operation id and exact payload; a lost
/// answer leaves it saved and unchanged. It is settled only by the SERVER:
/// a reply, a refusal of its first Send, or — asked by Check (read only,
/// `pur_op_state`) or Cancel (`pur_op_cancel`, under the same lock recording
/// takes) — the id recorded or cancelled for good. Until then: no edit, no new
/// tool submission for that account, nothing sent by itself. A saved entry
/// the phone can no longer read is kept and blocks new sends too (R104): by
/// its id it can still be checked or cancelled; without one it needs recovery.
class ToolSubmitter extends ChangeNotifier {
  ToolSubmitter({required this.remote, required this.store, DateTime Function()? now}) : _now = now ?? DateTime.now;

  final ToolsRemote remote;
  final ToolPendingStore store;
  final DateTime Function() _now;

  List<ToolSubmission> _all = const [];
  List<UnreadableToolSubmission> _unreadable = const [];
  bool _damaged = false;
  String? _userId;
  final _busy = <String>{};
  bool _disposed = false;

  /// The signed-in account's unresolved submissions, oldest first.
  List<ToolSubmission> get unresolved => [
        for (final s in _all)
          if (s.userId == _userId) s,
      ];

  /// This account's saved entries that no longer read in full but whose id
  /// does: the server can settle each by Check or Cancel (R104).
  List<UnreadableToolSubmission> get unreadable => [
        for (final u in _unreadable)
          if (u.settleable && u.userId == _userId) u,
      ];

  /// Saved tool data the phone cannot read and cannot settle by id — the
  /// whole store, an entry with no readable account (it could be anyone's),
  /// or one of this account's with no readable operation id (R104).
  bool get recoveryNeeded =>
      _damaged || _unreadable.any((u) => u.userId == null || (u.userId == _userId && u.opId == null));

  /// No new tool submission until every one of these is settled.
  bool get blocked => unresolved.isNotEmpty || unreadable.isNotEmpty || recoveryNeeded;
  bool isBusy(String opId) => _busy.contains(opId);
  ToolSubmission? byOp(String opId) => unresolved.where((s) => s.opId == opId).firstOrNull;

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

  /// A new tool record. Refused while this account has one unresolved.
  Future<ToolSendOutcome> submit({
    required ToolWrite write,
    required Map<String, dynamic> Function(String opId) params,
    required String summary,
  }) async {
    final userId = _userId;
    if (userId == null) throw StateError('load() first');
    if (blocked) return const ToolSendOutcome(ToolSendResult.blocked);
    final opId = newToolOpId();
    final s = ToolSubmission.create(opId: opId, userId: userId, write: write, params: params(opId), summary: summary, now: _now());
    return _send(s);
  }

  /// Send again: the saved submission, byte for byte — never the form.
  Future<ToolSendOutcome> retry(String opId) async {
    final s = byOp(opId);
    if (s == null) return ToolSendOutcome(ToolSendResult.recorded, opId: opId);
    return _send(s);
  }

  Future<ToolSendOutcome> _send(ToolSubmission s) async {
    if (!_busy.add(s.opId)) return ToolSendOutcome(ToolSendResult.unsure, opId: s.opId);
    _notify();
    try {
      // Sent before? Then that Send might still arrive.
      final sentBefore = s.lastSentAt != null;
      final sent = s.sentAt(_now());
      try {
        await _put(sent);
      } catch (_) {
        // Not saved, so not sent. The phone cannot keep tool records safely:
        // nothing new is sent until that is fixed (R104).
        _damaged = true;
        if (!sentBefore) {
          // A new one: nothing left the phone — refused, the form stays editable.
          _all = [..._all.where((x) => x.opId != s.opId)];
          return ToolSendOutcome(ToolSendResult.refused, opId: s.opId, failure: ToolFailure.unexpected);
        }
        return ToolSendOutcome(ToolSendResult.unsure, opId: s.opId, failure: ToolFailure.unexpected);
      }
      try {
        final answer = await remote.write(sent.write, sent.params, userId: sent.userId);
        await _drop(sent.opId);
        return ToolSendOutcome(ToolSendResult.recorded, opId: s.opId, answer: answer);
      } catch (e) {
        final f = ToolFailure.of(e);
        if (f.uncertain) return ToolSendOutcome(ToolSendResult.unsure, opId: s.opId, failure: f);
        // A refusal settles it only if no earlier Send of it can still arrive
        // — or the server says the id itself is cancelled (R102).
        if (sentBefore && f != ToolFailure.opCancelled) {
          return ToolSendOutcome(ToolSendResult.unsure, opId: s.opId, failure: f);
        }
        await _drop(sent.opId);
        return ToolSendOutcome(ToolSendResult.refused, opId: s.opId, failure: f);
      }
    } finally {
      _busy.remove(s.opId);
      _notify();
    }
  }

  /// Check: asks the server, read only; never sends, never cancels.
  Future<ToolSettleOutcome> check(String opId) => _settle(opId, cancel: false);

  /// Cancel it: the server settles the id — recorded (nothing changes) or
  /// cancelled for good. Only a 'cancelled' answer lets it be changed or dropped.
  Future<ToolSettleOutcome> cancel(String opId) => _settle(opId, cancel: true);

  Future<ToolSettleOutcome> _settle(String opId, {required bool cancel}) async {
    final s = byOp(opId);
    // An unreadable entry is settled by its id alone — its payload is never rebuilt (R104).
    final u = s == null ? unreadable.where((x) => x.opId == opId).firstOrNull : null;
    final userId = s?.userId ?? u?.userId;
    if (userId == null) return const ToolSettleOutcome(ToolSettleResult.recorded);
    if (!_busy.add(opId)) return const ToolSettleOutcome(ToolSettleResult.unknown);
    _notify();
    try {
      final String state;
      try {
        state = cancel ? await remote.cancelOp(opId, userId: userId) : await remote.opState(opId, userId: userId);
      } catch (e) {
        return ToolSettleOutcome(ToolSettleResult.unknown, failure: ToolFailure.of(e));
      }
      if (u != null) {
        final result = switch (state) {
          'recorded' => ToolSettleResult.recorded,
          'cancelled' => ToolSettleResult.cancelled,
          'none' when !cancel => ToolSettleResult.pending,
          _ => ToolSettleResult.unknown,
        };
        if (result == ToolSettleResult.recorded || result == ToolSettleResult.cancelled) {
          try {
            await store.dropUnreadable(userId, opId);
            await _reload();
          } catch (_) {
            // Not removed from the phone: it stays (and blocks) until it can be.
            return const ToolSettleOutcome(ToolSettleResult.unknown, failure: ToolFailure.unexpected);
          }
        }
        return ToolSettleOutcome(result, failure: result == ToolSettleResult.unknown ? ToolFailure.unexpected : null);
      }
      final result = switch (state) {
        'recorded' => ToolSettleResult.recorded,
        'cancelled' => ToolSettleResult.cancelled,
        'none' when !cancel => ToolSettleResult.pending,
        _ => ToolSettleResult.unknown,
      };
      if (result == ToolSettleResult.recorded || result == ToolSettleResult.cancelled) await _drop(opId);
      return ToolSettleOutcome(result, failure: result == ToolSettleResult.unknown ? ToolFailure.unexpected : null);
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

  Future<void> _put(ToolSubmission s) async {
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
