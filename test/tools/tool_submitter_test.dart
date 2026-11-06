import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:workmate/tools/data/tool_pending_store.dart';
import 'package:workmate/tools/data/tool_submitter.dart';
import 'package:workmate/tools/domain/tool_failure.dart';
import 'package:workmate/tools/domain/tool_submission.dart';

import 'tool_fakes.dart';

Map<String, dynamic> issue(String op, {String holder = 'u-ben'}) => {
      'p_op': op,
      'p_body': {'tool_id': 't3', 'holder_id': holder, 'folder_id': 'f-house', 'request_line_id': null, 'note': ''},
    };

/// One payload per tool action, exactly as the forms build them (0111's parameters).
Map<String, dynamic> payloadFor(ToolWrite w, String op) => switch (w) {
      ToolWrite.issue => issue(op),
      ToolWrite.handover => {'p_op': op, 'p_body': {'tool_id': 't2', 'holder_id': 'u-amy', 'folder_id': 'f-house', 'note': ''}},
      ToolWrite.giveBack => {'p_op': op, 'p_body': {'tool_id': 't1', 'condition': 'damaged', 'note': 'Motor burnt'}},
      ToolWrite.undo => {'p_op': op, 'p_record': 'rec-9', 'p_reason': 'Wrong person'},
      ToolWrite.report => {'p_op': op, 'p_tool': 't1', 'p_kind': 'broken', 'p_note': ''},
    };

void main() {
  late FakeToolsRemote remote;
  late MemoryToolPendingStore store;
  late DateTime clock;
  late ToolSubmitter s;

  setUp(() async {
    remote = FakeToolsRemote();
    store = MemoryToolPendingStore();
    clock = DateTime.utc(2026, 11, 6, 2);
    s = ToolSubmitter(remote: remote, store: store, now: () => clock);
    await s.load('u1');
  });

  Future<ToolSendOutcome> send({String holder = 'u-ben'}) =>
      s.submit(write: ToolWrite.issue, params: (op) => issue(op, holder: holder), summary: 'Issued TOOL-0003 to $holder');

  test('answered: recorded, and nothing is left on the phone', () async {
    final o = await send();
    expect(o.result, ToolSendResult.recorded);
    expect(remote.writes.single.$1, 'tl_team_issue');
    expect(s.unresolved, isEmpty);
    expect((await store.load()).readable, isEmpty);
  });

  test('saved BEFORE it leaves the phone — a restart mid-send still finds it', () async {
    final seen = <int>[];
    final gate = Completer<void>();
    final slow = _SlowRemote(remote, () async => seen.add((await store.load()).readable.length), gate.future);
    final t = ToolSubmitter(remote: slow, store: store, now: () => clock);
    await t.load('u1');
    final pending = t.submit(write: ToolWrite.issue, params: (op) => issue(op), summary: 'x');
    await Future<void>.delayed(Duration.zero);
    gate.complete();
    await pending;
    expect(seen, [1], reason: 'stored while the request was out');
  });

  test('a lost answer keeps it — the same operation id and the exact payload — and blocks a new one', () async {
    remote.failNextWrite = TimeoutException('lost');
    final o = await send();
    expect(o.result, ToolSendResult.unsure);
    expect(o.failure, ToolFailure.noConnection);
    final kept = s.unresolved.single;
    expect(kept.params, issue(kept.opId));
    expect((await store.load()).readable.single.payload, kept.payload);
    expect((await send(holder: 'u-amy')).result, ToolSendResult.blocked, reason: 'no new submission until it is resolved');
    expect(remote.attempts, hasLength(1));
  });

  test('an unknown error (a garbled reply, a server fault) is unsure too — kept, not dropped', () async {
    remote.loseNextAnswer = const FormatException('garbled reply after commit');
    final o = await send();
    expect([o.result, o.failure], [ToolSendResult.unsure, ToolFailure.unexpected]);
    expect((await s.retry(s.unresolved.single.opId)).answer?['replayed'], isTrue);
    expect(remote.writes, hasLength(1));
  });

  test('a refusal on the first Send settles it; on a Send again it does not (the first Send may still arrive)', () async {
    remote.failNextWrite = refusal('NOT_YOUR_TEAM');
    final first = await send();
    expect([first.result, first.failure], [ToolSendResult.refused, ToolFailure.notYourTeam]);
    expect(s.unresolved, isEmpty);

    remote.failNextWrite = TimeoutException('lost');
    await send();
    final op = s.unresolved.single.opId;
    clock = clock.add(const Duration(hours: 5));
    remote.failNextWrite = refusal('NOT_AVAILABLE');
    final o = await s.retry(op);
    expect([o.result, o.failure], [ToolSendResult.unsure, ToolFailure.notAvailable], reason: 'however long after');
    expect(s.byOp(op), isNotNull);
    expect((await s.cancel(op)).result, ToolSettleResult.cancelled, reason: 'only the server settles it');
  });

  test('the original arriving after the cancel and a new submission is refused: only the new one records', () async {
    remote.failNextWrite = TimeoutException('lost before it reached the server');
    await send(holder: 'u-ben');
    final original = s.unresolved.single;
    expect((await s.cancel(original.opId)).result, ToolSettleResult.cancelled);
    expect((await send(holder: 'u-amy')).result, ToolSendResult.recorded);
    await expectLater(remote.write(original.write, original.params, userId: 'u1'),
        throwsA(isA<Exception>().having((e) => e.toString(), 'refusal', contains('OP_CANCELLED'))));
    expect(remote.writes.map((w) => w.$2['p_body']['holder_id']), ['u-amy'], reason: 'one tool is never issued twice');
  });

  test('a cancel whose answer was lost: nothing known, it stays; a Check finds it cancelled', () async {
    remote.failNextWrite = TimeoutException('lost');
    await send();
    final op = s.unresolved.single.opId;
    remote.loseNextCancel = TimeoutException('cancel answer lost');
    expect((await s.cancel(op)).result, ToolSettleResult.unknown);
    expect(s.byOp(op), isNotNull, reason: 'not settled on the phone without the server\'s word');
    expect((await s.check(op)).result, ToolSettleResult.cancelled);
    expect(s.unresolved, isEmpty);
  });

  test('Send again of a cancelled id is refused OP_CANCELLED — settled, nothing recorded', () async {
    remote.failNextWrite = TimeoutException('lost');
    await send();
    final op = s.unresolved.single.opId;
    remote.loseNextCancel = TimeoutException('cancel answer lost');
    await s.cancel(op);
    final o = await s.retry(op);
    expect([o.result, o.failure], [ToolSendResult.refused, ToolFailure.opCancelled]);
    expect([remote.writes.length, s.unresolved.length], [0, 0]);
  });

  test('no signal for a check or a cancel: nothing known, nothing changed', () async {
    remote.failNextWrite = TimeoutException('lost');
    await send();
    remote.failReads = const SocketException('offline');
    expect((await s.check(s.unresolved.single.opId)).result, ToolSettleResult.unknown);
    expect((await s.cancel(s.unresolved.single.opId)).result, ToolSettleResult.unknown);
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
    final t = ToolSubmitter(remote: remote, store: store, now: () => clock.add(const Duration(hours: 5)));
    await t.load('u1');
    await t.checkAll();
    expect([remote.attempts.length, remote.cancels, t.unresolved.length], [1, 0, 1]);
  });

  test('tools and stock keep separate lists: the settings file has its own key', () {
    expect(PrefsToolPendingStore.key, 'tools.unresolved.v1');
  });

  test('the settings file keeps it word for word across a fresh read (a restart)', () async {
    SharedPreferences.setMockInitialValues({});
    final p1 = PrefsToolPendingStore(await SharedPreferences.getInstance());
    final a = ToolSubmitter(remote: remote, store: p1, now: () => clock);
    await a.load('u1');
    remote.failNextWrite = TimeoutException('lost');
    await a.submit(write: ToolWrite.report, params: (op) => payloadFor(ToolWrite.report, op), summary: 'TOOL-0001 · It\'s broken');
    final raw = (await SharedPreferences.getInstance()).getString(PrefsToolPendingStore.key)!;
    // ignore: invalid_use_of_visible_for_testing_member
    SharedPreferences.resetStatic();
    SharedPreferences.setMockInitialValues({PrefsToolPendingStore.key: raw});
    final b = ToolSubmitter(remote: remote, store: PrefsToolPendingStore(await SharedPreferences.getInstance()), now: () => clock);
    await b.load('u1');
    final kept = b.unresolved.single;
    expect([kept.write, kept.summary, kept.sends, kept.payload], [ToolWrite.report, 'TOOL-0001 · It\'s broken', 1, a.unresolved.single.payload]);
    await b.retry(kept.opId);
    expect(remote.attempts[1], remote.attempts[0]);
  });

  group('every tool action: a lost answer is kept, sent again unchanged, checked or cancelled — never twice', () {
    for (final w in ToolWrite.values) {
      Future<ToolSendOutcome> sendIt() => s.submit(write: w, params: (op) => payloadFor(w, op), summary: w.name);

      test('${w.fn}: recorded but the answer lost → Send again is answered, recorded once', () async {
        remote.loseNextAnswer = TimeoutException('lost after commit');
        expect((await sendIt()).result, ToolSendResult.unsure);
        final kept = s.unresolved.single;
        expect(kept.params, payloadFor(w, kept.opId), reason: 'its exact payload, under its own id');
        final o = await s.retry(kept.opId);
        expect([o.result, o.answer?['replayed']], [ToolSendResult.recorded, true]);
        expect(remote.attempts.map((a) => a.$2).toSet(), {jsonEncode(kept.params)}, reason: 'byte for byte');
        expect(remote.writes.where((x) => x.$1 == w.fn), hasLength(1));
      });

      test('${w.fn}: Check after a lost answer — recorded → it goes; nothing sent', () async {
        remote.loseNextAnswer = TimeoutException('lost after commit');
        await sendIt();
        final before = remote.attempts.length;
        expect((await s.check(s.unresolved.single.opId)).result, ToolSettleResult.recorded);
        expect([s.unresolved.length, remote.attempts.length], [0, before]);
      });

      test('${w.fn}: lost before it arrived → Check says not yet; Cancel settles it for good; a late copy is refused', () async {
        remote.failNextWrite = TimeoutException('lost on the way');
        await sendIt();
        final kept = s.unresolved.single;
        expect((await s.check(kept.opId)).result, ToolSettleResult.pending);
        expect(s.blocked, isTrue, reason: 'no new tool record meanwhile');
        expect((await s.cancel(kept.opId)).result, ToolSettleResult.cancelled);
        expect(s.unresolved, isEmpty);
        await expectLater(remote.write(w, kept.params, userId: 'u1'), throwsA(isA<Exception>()));
        expect(remote.writes, isEmpty, reason: 'nothing recorded');
      });
    }
  });

  group('saved data the phone cannot read', () {
    const a = 'aaaaaaaa-0000-4000-8000-000000000001';
    const b = 'bbbbbbbb-0000-4000-8000-000000000002';
    const op1 = '11111111-0000-4000-8000-000000000001';
    String bad(String op, String user) =>
        '{"op_id":"$op","user_id":"$user","fn":"tl_team_issue","payload":"not json","created_at":"2026-11-06T02:00:00Z"}';
    late SharedPreferences prefs;

    Future<ToolSubmitter> stored(String raw, String user) async {
      // ignore: invalid_use_of_visible_for_testing_member
      SharedPreferences.resetStatic();
      SharedPreferences.setMockInitialValues({PrefsToolPendingStore.key: raw});
      prefs = await SharedPreferences.getInstance();
      final t = ToolSubmitter(remote: remote, store: PrefsToolPendingStore(prefs), now: () => clock);
      await t.load(user);
      return t;
    }

    List<dynamic> entries() => jsonDecode(prefs.getString(PrefsToolPendingStore.key)!) as List<dynamic>;

    test('a damaged entry of this account blocks new sends; Check and Cancel settle it by its id, never its payload', () async {
      final t = await stored('[${bad(op1, a)}]', a);
      expect([t.unresolved.length, t.unreadable.single.opId, t.blocked, t.recoveryNeeded], [0, op1, true, false]);
      expect((await t.submit(write: ToolWrite.issue, params: (op) => issue(op), summary: 'x')).result, ToolSendResult.blocked);
      expect((await t.check(op1)).result, ToolSettleResult.pending);
      expect((await t.cancel(op1)).result, ToolSettleResult.cancelled);
      expect([t.blocked, entries()], [false, isEmpty]);
      expect(remote.attempts, isEmpty, reason: 'its payload was never rebuilt or sent');
    });

    test('another account\'s damaged entry does not hold this one back, and survives every save', () async {
      final t = await stored('[${bad(op1, b)}]', a);
      expect(t.blocked, isFalse);
      remote.failNextWrite = TimeoutException('lost');
      await t.submit(write: ToolWrite.issue, params: (op) => issue(op), summary: 'x');
      expect(entries().first, jsonDecode(bad(op1, b)));
      await t.load(b);
      expect([t.blocked, t.unreadable.single.opId], [true, op1]);
    });

    test('storage that is not a list at all: everything blocked, and nothing ever overwrites it', () async {
      final t = await stored('not json', a);
      expect([t.blocked, t.recoveryNeeded], [true, true]);
      expect((await t.submit(write: ToolWrite.issue, params: (op) => issue(op), summary: 'x')).result, ToolSendResult.blocked);
      await expectLater(PrefsToolPendingStore(prefs).save(const []), throwsStateError);
      expect(prefs.getString(PrefsToolPendingStore.key), 'not json');
      expect(remote.attempts, isEmpty);
    });
  });
}

/// Holds a write until [gate] opens, running [during] while it is out.
class _SlowRemote extends FakeToolsRemote {
  _SlowRemote(this.inner, this.during, this.gate);
  final FakeToolsRemote inner;
  final Future<void> Function() during;
  final Future<void> gate;

  @override
  Future<Map<String, dynamic>> write(ToolWrite w, Map<String, dynamic> params, {required String userId}) async {
    await during();
    await gate;
    return inner.write(w, params, userId: userId);
  }
}
