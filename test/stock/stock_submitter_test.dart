import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:supabase_flutter/supabase_flutter.dart' show PostgrestException;
import 'package:workmate/stock/data/stock_pending_store.dart';
import 'package:workmate/stock/data/stock_submitter.dart';
import 'package:workmate/stock/domain/stock_failure.dart';
import 'package:workmate/stock/domain/stock_submission.dart';

import 'stock_fakes.dart';

Map<String, dynamic> issue(String op, {String qty = '4'}) => {
      'p_op': op,
      'p_body': {'item_id': 'item-cement', 'quantity': qty, 'on': '2026-10-27', 'note': '', 'from': 'warehouse', 'to': 'f-barlin', 'request_line_id': 'l1'},
    };

PostgrestException refusal(String code) => PostgrestException(message: code, code: 'P0001');

void main() {
  late FakeStockRemote remote;
  late MemoryStockPendingStore store;
  late DateTime clock;
  late StockSubmitter s;

  setUp(() async {
    remote = FakeStockRemote();
    store = MemoryStockPendingStore();
    clock = DateTime.utc(2026, 10, 27, 2);
    s = StockSubmitter(remote: remote, store: store, now: () => clock);
    await s.load('u1');
  });

  Future<StockSendOutcome> send({String qty = '4'}) =>
      s.submit(write: StockWrite.move, params: (op) => issue(op, qty: qty), summary: 'Issued $qty bag Cement');

  test('answered: recorded, and nothing is left on the phone', () async {
    final o = await send();
    expect(o.result, StockSendResult.recorded);
    expect(remote.writes, hasLength(1));
    expect(s.unresolved, isEmpty);
    expect((await store.load()).readable, isEmpty);
  });

  test('saved BEFORE it leaves the phone — a restart mid-send still finds it', () async {
    final seen = <int>[];
    final gate = Completer<void>();
    final slow = _SlowRemote(remote, () async => seen.add((await store.load()).readable.length), gate.future);
    final t = StockSubmitter(remote: slow, store: store, now: () => clock);
    await t.load('u1');
    final pending = t.submit(write: StockWrite.move, params: (op) => issue(op), summary: 'x');
    await Future<void>.delayed(Duration.zero);
    gate.complete();
    await pending;
    expect(seen, [1], reason: 'stored while the request was out');
  });

  test('a lost answer keeps it — the same operation id and the exact payload — and blocks a new one', () async {
    remote.failNextWrite = TimeoutException('lost');
    final o = await send();
    expect(o.result, StockSendResult.unsure);
    expect(o.failure, StockFailure.noConnection);
    final kept = s.unresolved.single;
    expect(kept.params, issue(kept.opId));
    expect((await store.load()).readable.single.payload, kept.payload);
    expect((await send(qty: '6')).result, StockSendResult.blocked, reason: 'no new submission until it is resolved');
    expect(remote.attempts, hasLength(1));
  });

  test('an unknown error (a garbled reply, a server fault) is unsure too — kept, not dropped', () async {
    remote.loseNextAnswer = const FormatException('garbled reply after commit');
    final o = await send();
    expect([o.result, o.failure], [StockSendResult.unsure, StockFailure.unexpected]);
    expect(s.unresolved, hasLength(1));
    expect((await s.retry(s.unresolved.single.opId)).answer?['replayed'], isTrue);
    expect(remote.writes, hasLength(1));
  });

  test('Send again sends the saved payload byte for byte, under the same id', () async {
    remote.failNextWrite = const SocketException('lost');
    await send();
    final op = s.unresolved.single.opId;
    final o = await s.retry(op);
    expect(o.result, StockSendResult.recorded);
    expect(remote.attempts.map((a) => a.$1).toSet(), {op});
    expect(remote.attempts[1].$2, remote.attempts[0].$2, reason: 'unchanged');
    expect(s.unresolved, isEmpty);
  });

  test('recorded but the answer lost: Send again is answered, never recorded twice', () async {
    remote.loseNextAnswer = TimeoutException('lost after commit');
    expect((await send()).result, StockSendResult.unsure);
    final o = await s.retry(s.unresolved.single.opId);
    expect(o.result, StockSendResult.recorded);
    expect(o.answer?['replayed'], isTrue);
    expect(remote.writes, hasLength(1));
  });

  test('Check is read only: recorded → it goes (nothing sent); none → it stays, with no way to change it', () async {
    remote.loseNextAnswer = TimeoutException('lost');
    await send();
    final before = remote.attempts.length;
    expect((await s.check(s.unresolved.single.opId)).result, StockSettleResult.recorded);
    expect(s.unresolved, isEmpty);
    expect(remote.attempts.length, before, reason: 'a check never sends');

    remote.failNextWrite = TimeoutException('lost');
    await send();
    final op = s.unresolved.single.opId;
    clock = clock.add(const Duration(hours: 5));
    expect((await s.check(op)).result, StockSettleResult.pending, reason: 'no clock decides it — only the server');
    expect(s.byOp(op), isNotNull);
    expect(remote.cancelled, isEmpty, reason: 'a check never cancels');
    expect((await send(qty: '6')).result, StockSendResult.blocked);
  });

  test('Cancel: the server settles it — recorded (it goes as recorded, never changed) or cancelled for good', () async {
    remote.loseNextAnswer = TimeoutException('lost');
    await send();
    expect((await s.cancel(s.unresolved.single.opId)).result, StockSettleResult.recorded);
    expect([remote.writes.length, remote.cancelled.length, s.unresolved.length], [1, 0, 0], reason: 'it was recorded: nothing cancelled');

    remote.failNextWrite = TimeoutException('lost');
    await send();
    final op = s.unresolved.single.opId;
    expect((await s.cancel(op)).result, StockSettleResult.cancelled);
    expect(remote.cancelled, {'u1:$op'});
    expect(s.unresolved, isEmpty, reason: 'settled: it may be changed now');
    expect((await send(qty: '6')).result, StockSendResult.recorded);
    expect(remote.writes.last.$2['p_body']['quantity'], '6');
    expect(remote.writes.last.$2['p_op'], isNot(op), reason: 'a new operation id');
  });

  test('the original arriving after the cancel and a new submission is refused: only the new one records', () async {
    remote.failNextWrite = TimeoutException('lost before it reached the server');
    await send(qty: '4');
    final original = s.unresolved.single;
    expect((await s.cancel(original.opId)).result, StockSettleResult.cancelled);
    expect((await send(qty: '6')).result, StockSendResult.recorded);
    // The first request, held up on the network, arrives now — exactly as sent.
    await expectLater(remote.write(original.write, original.params, userId: 'u1'),
        throwsA(isA<Exception>().having((e) => e.toString(), 'refusal', contains('OP_CANCELLED'))));
    expect(remote.writes.map((w) => w.$2['p_body']['quantity']), ['6'], reason: 'only the new submission is recorded');
  });

  test('a cancel whose answer was lost: nothing known, it stays; a Check (or Cancel again) finds it cancelled', () async {
    remote.failNextWrite = TimeoutException('lost');
    await send();
    final op = s.unresolved.single.opId;
    remote.loseNextCancel = TimeoutException('cancel answer lost');
    expect((await s.cancel(op)).result, StockSettleResult.unknown);
    expect(s.byOp(op), isNotNull, reason: 'not settled on the phone without the server\'s word');
    expect((await s.check(op)).result, StockSettleResult.cancelled);
    expect(s.unresolved, isEmpty);
  });

  test('Send again of a cancelled id is refused OP_CANCELLED — settled, nothing recorded', () async {
    remote.failNextWrite = TimeoutException('lost');
    await send();
    final op = s.unresolved.single.opId;
    remote.loseNextCancel = TimeoutException('cancel answer lost');
    await s.cancel(op);
    final o = await s.retry(op);
    expect([o.result, o.failure], [StockSendResult.refused, StockFailure.opCancelled]);
    expect([remote.writes.length, s.unresolved.length], [0, 0]);
  });

  test('a refusal on the first Send settles it; on a Send again it does not (the first Send may still arrive)', () async {
    remote.failNextWrite = refusal('NOT_ENOUGH');
    expect((await send()).result, StockSendResult.refused);
    expect(s.unresolved, isEmpty);

    remote.failNextWrite = TimeoutException('lost');
    await send();
    final op = s.unresolved.single.opId;
    clock = clock.add(const Duration(hours: 5));
    remote.failNextWrite = refusal('NOT_ENOUGH');
    final o = await s.retry(op);
    expect([o.result, o.failure], [StockSendResult.unsure, StockFailure.notEnough], reason: 'however long after');
    expect(s.byOp(op), isNotNull);
    expect((await s.cancel(op)).result, StockSettleResult.cancelled, reason: 'only the server settles it');
  });

  test('no signal for a check or a cancel: nothing known, nothing changed', () async {
    remote.failNextWrite = TimeoutException('lost');
    await send();
    remote.failReads = const SocketException('offline');
    expect((await s.check(s.unresolved.single.opId)).result, StockSettleResult.unknown);
    expect((await s.cancel(s.unresolved.single.opId)).result, StockSettleResult.unknown);
    expect(s.unresolved, hasLength(1));
    expect(remote.cancelled, isEmpty);
  });

  test('one phone, two accounts: each sees and sends only its own', () async {
    remote.failNextWrite = TimeoutException('lost');
    await send();
    await s.load('u2');
    expect(s.unresolved, isEmpty);
    expect(s.blocked, isFalse);
    expect((await store.load()).readable, hasLength(1), reason: 'kept for its own account');
    await s.load('u1');
    expect(s.unresolved, hasLength(1));
  });

  test('nothing is sent or cancelled by itself: loading and checking all never write', () async {
    remote.failNextWrite = TimeoutException('lost');
    await send();
    final t = StockSubmitter(remote: remote, store: store, now: () => clock.add(const Duration(hours: 5)));
    await t.load('u1');
    await t.checkAll();
    expect([remote.attempts.length, remote.cancels, t.unresolved.length], [1, 0, 1]);
  });

  test('the settings file keeps it word for word across a fresh read (a restart)', () async {
    SharedPreferences.setMockInitialValues({});
    final p1 = PrefsStockPendingStore(await SharedPreferences.getInstance());
    final a = StockSubmitter(remote: remote, store: p1, now: () => clock);
    await a.load('u1');
    remote.failNextWrite = TimeoutException('lost');
    await a.submit(write: StockWrite.receive, params: (op) => {'p_op': op, 'p_purchase': 'p-1', 'p_line_no': 1, 'p_qty': '5', 'p_on': '2026-10-27', 'p_note': ''}, summary: 'Received 5 bag');
    final raw = (await SharedPreferences.getInstance()).getString(PrefsStockPendingStore.key)!;
    // ignore: invalid_use_of_visible_for_testing_member
    SharedPreferences.resetStatic();
    SharedPreferences.setMockInitialValues({PrefsStockPendingStore.key: raw});
    final b = StockSubmitter(remote: remote, store: PrefsStockPendingStore(await SharedPreferences.getInstance()), now: () => clock);
    await b.load('u1');
    final kept = b.unresolved.single;
    expect([kept.write, kept.summary, kept.sends, kept.payload], [StockWrite.receive, 'Received 5 bag', 1, a.unresolved.single.payload]);
    await b.retry(kept.opId);
    expect(remote.attempts[1], remote.attempts[0]);
  });

  group('saved data the phone cannot read (R104)', () {
    const a = 'aaaaaaaa-0000-4000-8000-000000000001';
    const b = 'bbbbbbbb-0000-4000-8000-000000000002';
    const op1 = '11111111-0000-4000-8000-000000000001';
    const op2 = '22222222-0000-4000-8000-000000000002';
    String bad(String op, String user) =>
        '{"op_id":"$op","user_id":"$user","fn":"stk_move","payload":"not json","created_at":"2026-10-27T02:00:00Z"}';
    late SharedPreferences prefs;

    Future<StockSubmitter> stored(String raw, String user) async {
      // ignore: invalid_use_of_visible_for_testing_member
      SharedPreferences.resetStatic();
      SharedPreferences.setMockInitialValues({PrefsStockPendingStore.key: raw});
      prefs = await SharedPreferences.getInstance();
      final t = StockSubmitter(remote: remote, store: PrefsStockPendingStore(prefs), now: () => clock);
      await t.load(user);
      return t;
    }

    List<dynamic> entries() => jsonDecode(prefs.getString(PrefsStockPendingStore.key)!) as List<dynamic>;
    Future<StockSendOutcome> sendWith(StockSubmitter t, {String qty = '4'}) =>
        t.submit(write: StockWrite.move, params: (op) => issue(op, qty: qty), summary: 'Issued $qty bag Cement');

    test('a damaged entry of this account blocks new sends; Check and Cancel settle it by its id, never its payload', () async {
      final t = await stored('[${bad(op1, a)}]', a);
      expect([t.unresolved.length, t.unreadable.single.opId, t.blocked, t.recoveryNeeded], [0, op1, true, false]);
      expect((await sendWith(t)).result, StockSendResult.blocked, reason: 'malformed data never unblocks a new send');
      expect((await t.check(op1)).result, StockSettleResult.pending);
      expect([t.blocked, entries().length], [true, 1], reason: 'not settled: still there, still blocking');
      expect((await t.cancel(op1)).result, StockSettleResult.cancelled);
      expect(remote.cancelled, {'$a:$op1'});
      expect([t.blocked, entries()], [false, isEmpty], reason: 'settled by the server: only now it goes');
      expect(remote.attempts, isEmpty, reason: 'its payload was never rebuilt or sent');
      expect((await sendWith(t)).result, StockSendResult.recorded);
    });

    test('a damaged entry the server had recorded: Check finds it — it goes, nothing sent', () async {
      await remote.write(StockWrite.move, {'p_op': op2, 'p_body': <String, dynamic>{}}, userId: a);
      final t = await stored('[${bad(op2, a)}]', a);
      expect((await t.check(op2)).result, StockSettleResult.recorded);
      expect([remote.attempts.length, entries().length, t.blocked], [1, 0, false]);
    });

    test('a damaged entry survives every later save, word for word — and belongs to its own account', () async {
      final t = await stored('[${bad(op1, b)}]', a);
      final before = jsonDecode(bad(op1, b));
      expect(t.blocked, isFalse, reason: 'another account\'s entry does not hold this one back');
      remote.failNextWrite = TimeoutException('lost');
      await sendWith(t);
      expect(entries().first, before, reason: 'kept on the save of a new submission');
      await t.retry(t.unresolved.single.opId);
      expect(entries(), [before], reason: 'kept on the save that settles the other one');
      await t.load(b);
      expect([t.blocked, t.unreadable.single.opId], [true, op1], reason: 'it waits for its own account');
    });

    test('an entry with no readable account blocks every account, needs recovery, and is never overwritten', () async {
      final t = await stored('[{"payload":"x"}]', a);
      expect([t.blocked, t.recoveryNeeded, t.unreadable], [true, true, isEmpty], reason: 'cannot be settled by id');
      expect((await sendWith(t)).result, StockSendResult.blocked);
      await t.load(b);
      expect([t.blocked, t.recoveryNeeded], [true, true], reason: 'it could be anyone\'s');
      await PrefsStockPendingStore(prefs).save(const []);
      expect(entries(), [{'payload': 'x'}], reason: 'a save keeps it');
    });

    test('an entry of this account with no readable operation id needs recovery; another account is not held back', () async {
      final t = await stored('[{"op_id":"not-an-id","user_id":"$a","payload":"x"}]', a);
      expect([t.blocked, t.recoveryNeeded], [true, true]);
      await t.load(b);
      expect([t.blocked, t.recoveryNeeded], [false, false]);
    });

    test('storage that is not a list at all: everything blocked, and nothing ever overwrites it', () async {
      for (final raw in ['not json', '{"a":1}']) {
        final t = await stored(raw, a);
        expect([t.blocked, t.recoveryNeeded, t.unresolved, t.unreadable], [true, true, isEmpty, isEmpty], reason: raw);
        expect((await sendWith(t)).result, StockSendResult.blocked, reason: raw);
        await expectLater(PrefsStockPendingStore(prefs).save(const []), throwsStateError, reason: raw);
        await expectLater(PrefsStockPendingStore(prefs).dropUnreadable(a, op1), throwsStateError, reason: raw);
        expect(prefs.getString(PrefsStockPendingStore.key), raw, reason: 'untouched');
      }
      expect(remote.attempts, isEmpty);
    });

    test('storage turning unreadable while open: a new submission is not sent, the form stays editable, nothing new goes after', () async {
      final t = await stored('[]', a);
      await prefs.setString(PrefsStockPendingStore.key, 'garbage');
      final o = await sendWith(t);
      expect([o.result, o.failure], [StockSendResult.refused, StockFailure.unexpected], reason: 'not saved, so not sent');
      expect([remote.attempts, t.blocked, t.recoveryNeeded], [isEmpty, true, true]);
      expect((await sendWith(t)).result, StockSendResult.blocked);
      expect(prefs.getString(PrefsStockPendingStore.key), 'garbage');
    });

    test('readable entries beside damaged ones still read; each damaged one is kept apart', () async {
      final good = StockSubmission.create(opId: op2, userId: a, write: StockWrite.move, params: issue(op2), summary: 's', now: clock).sentAt(clock);
      final t = await stored('[${bad(op1, a)},${jsonEncode(good.toJson())},{"op_id":"$op1","user_id":"$a","fn":"stk_move","payload":"{}","created_at":"not a date"}]', a);
      expect(t.unresolved.single.opId, op2);
      expect(t.unreadable.map((u) => u.opId), [op1, op1]);
      expect(t.blocked, isTrue);
    });
  });

  test('a payload never travels without its own operation id', () {
    expect(() => StockSubmission.create(opId: 'a', userId: 'u1', write: StockWrite.move, params: {'p_op': 'b'}, summary: '', now: clock),
        throwsArgumentError);
    expect(StockSubmission.fromJson({'op_id': 'a', 'user_id': 'u1', 'fn': 'stk_move', 'payload': '{"p_op":"b"}', 'created_at': '2026-10-27T02:00:00Z'}),
        isNull);
  });
}

/// Holds a write until [gate] opens, running [during] while it is out.
class _SlowRemote extends FakeStockRemote {
  _SlowRemote(this.inner, this.during, this.gate);
  final FakeStockRemote inner;
  final Future<void> Function() during;
  final Future<void> gate;

  @override
  Future<Map<String, dynamic>> write(StockWrite w, Map<String, dynamic> params, {required String userId}) async {
    await during();
    await gate;
    return inner.write(w, params, userId: userId);
  }
}
