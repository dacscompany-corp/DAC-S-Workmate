import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import 'package:workmate/attendance/sync/submission_sync.dart' show SyncResult;
import 'package:workmate/purchasing/data/purchasing_api.dart';
import 'package:workmate/purchasing/data/purchasing_db.dart';
import 'package:workmate/purchasing/data/purchasing_repository.dart';
import 'package:workmate/purchasing/domain/pay_models.dart';
import 'package:workmate/purchasing/domain/pur_failure.dart';
import 'package:workmate/purchasing/domain/purchase_draft.dart';
import 'package:workmate/purchasing/sync/purchasing_sync.dart';

import '../../attendance/fakes.dart';
import '../domain/purchase_draft_test.dart' show unplanned;
import '../purchasing_fakes.dart';

/// 0102 on the phone: later payments and returns are queued and sent once
/// (Q6), "Paid now?" rides with its purchase (Q3), the buyer's own cash is
/// read fresh or from the saved copy, and voids / withdrawals / "I did not
/// receive this" need signal.
void main() {
  late PurchasingDb db;
  late FakePurchasingRemote remote;
  late Directory dir;
  late PurchasingRepository repo;
  late PurchasingSync sync;
  var user = 'u1';
  var ids = 0;
  var kicks = 0;
  var turnedOff = 0;

  setUpAll(sqfliteFfiInit);
  setUp(() async {
    db = await PurchasingDb.open(databaseFactoryFfi, inMemoryDatabasePath, singleInstance: false);
    remote = FakePurchasingRemote();
    dir = await Directory.systemTemp.createTemp('pur-pay');
    user = 'u1';
    ids = 0;
    kicks = 0;
    turnedOff = 0;
    repo = PurchasingRepository(
      db: db,
      remote: remote,
      device: FakeDevice(),
      scheduler: FakeScheduler(),
      currentUserId: () => user,
      companyOf: (_) => 'o1',
      photoDir: () async => dir,
      sendNow: () async => kicks++,
      onBuyingOff: () async => turnedOff++,
      now: () => wednesday,
      newId: () => 'id${++ids}',
    );
    sync = PurchasingSync(db: db, remote: remote, now: () => wednesday);
  });
  tearDown(() async {
    await db.close();
    await dir.delete(recursive: true);
  });

  Future<String> photo(String name) async {
    final f = File('${dir.path}/$name');
    await f.writeAsBytes([1, 2, 3]);
    return f.path;
  }

  final today = repoToday();

  PaymentInput pay({String amount = '300', String source = 'petty_cash', String method = 'gcash', String? creditId, String? paidOn}) =>
      PaymentInput(amount: amount, paidOn: paidOn ?? today, method: method, source: source, creditId: creditId);

  group('"My cash": the buyer\'s own, fresh or saved', () {
    test('read and saved; with no signal the saved copy, saying so', () async {
      remote.creditRows = [{'id': 'c1', 'supplier_id': 's1', 'supplier': 'ZZ Hardware', 'amount': 200, 'left': 80}];
      final fresh = await repo.myCash();
      expect([fresh.cash!.held, fresh.fromCache, fresh.credits.single.left], [1470, false, 80]);
      remote.readError = const SocketException('down');
      final saved = await repo.myCash();
      expect([saved.cash!.held, saved.fromCache, saved.credits.single.left], [1470, true, 80]);
      expect(saved.error, isA<SocketException>());
    });

    test('never read and no signal: nothing to show, and why', () async {
      remote.readError = const SocketException('down');
      final v = await repo.myCash();
      expect([v.cash, v.figures], [null, null]);
      expect(v.error, isA<SocketException>());
    });

    test('BUYER_REQUIRED wipes the saved copy and says buying is off (R26)', () async {
      await repo.myCash();
      remote.readError = Exception('BUYER_REQUIRED');
      await expectLater(repo.myCash(), throwsA(anything));
      expect(turnedOff, 1);
      remote.readError = const SocketException('down');
      expect((await repo.myCash()).cash, isNull, reason: 'the saved copy is gone');
    });

    test('Q16: payments still on the phone lower cash held as shown, never below zero; refused ones do not', () async {
      await repo.myCash();
      remote.readError = const SocketException('down');
      await repo.pay('pu1', pay(amount: '2000'));
      final v = await repo.myCash();
      expect(v.unsentPettyCash, 2000);
      expect(v.figures, (held: 0.0, shortfall: 530.0));
      await repo.pay('pu1', pay(amount: '100', source: 'company'));
      expect((await repo.myCash()).unsentPettyCash, 2000, reason: 'company money is not petty cash');
    });
  });

  group('a later payment (Q6): queued, sent once', () {
    test('refused before queueing where the server would refuse it: nothing queued', () async {
      await expectLater(repo.pay('pu1', pay(paidOn: '2099-01-01')), throwsA(isA<PaymentInvalid>()));
      await expectLater(repo.pay('pu1', pay(amount: '0')), throwsA(isA<PaymentInvalid>()));
      remote.creditRows = [{'id': 'c1', 'supplier_id': 's1', 'left': 80}];
      await repo.myCash();
      await expectLater(
          repo.pay('pu1', pay(source: 'credit', creditId: 'c1', amount: '120')),
          throwsA(isA<PaymentInvalid>().having((e) => e.problems, 'problems', [PayProblem.overCredit])),
          reason: 'what the credit had left when last read');
      expect(await db.ops('u1'), isEmpty);
    });

    test('waiting shows on My purchases and counts in what is left; the proof goes first, under purchases/', () async {
      final proof = await photo('gcash.jpg');
      await repo.pay('pu1', pay(amount: '300'), proofPhoto: proof);
      expect(kicks, 1);
      final mine = await repo.myPurchases();
      expect(mine.queuedPayments.single.state, QueuedState.waiting);
      expect([mine.unsentFor('pu1'), mine.unsentFor('pu2')], [300, 0]);
      expect(await repo.unsentFor('u1'), 1, reason: 'Buying is turned off counts it');

      expect(await sync.drain('u1'), SyncResult.done);
      expect(remote.uploads.single, startsWith('purchases/o1/'));
      expect(remote.uploadKinds, ['purchase']);
      final sent = remote.paid.single;
      expect([sent['op'], sent['purchase_id'], sent['amount'], sent['source'], sent['method']], ['id1', 'pu1', '300.00', 'petty_cash', 'gcash']);
      expect(sent['proof_url'], endsWith(remote.uploads.single));
      expect(sent.containsKey('person_id'), isFalse, reason: 'the server fills in the buyer (R2)');
      expect(await db.ops('u1'), isEmpty);
      expect(File(proof).existsSync(), isFalse, reason: 'the proof is safe to delete only once recorded');
    });

    test('no signal: the uploaded proof is not uploaded again, and the same op id retries', () async {
      await repo.pay('pu1', pay(), proofPhoto: await photo('p.jpg'));
      remote.writeError = const SocketException('down');
      expect(await sync.drain('u1'), SyncResult.retry);
      expect(await sync.drain('u1'), SyncResult.done);
      expect(remote.uploads, hasLength(1));
      expect(remote.calls.where((c) => c.startsWith('pay:')), ['pay:id1:pu1', 'pay:id1:pu1']);
      expect(remote.paid, hasLength(1));
    });

    test('refused: kept as Needs attention with the reason, not counted in what is left; thrown away with its proof', () async {
      final proof = await photo('p.jpg');
      await repo.pay('pu1', pay(), proofPhoto: proof);
      remote.writeError = Exception('BAD_STATE');
      await sync.drain('u1');
      final q = (await repo.myPurchases()).queuedPayments.single;
      expect([q.state, q.failure], [QueuedState.needsAttention, PurFailure.alreadyVoided]);
      expect((await repo.myPurchases()).unsentFor('pu1'), 0);
      expect((await repo.myCash()).unsentPettyCash, 0);
      await repo.discardAction(q.opId);
      expect(await db.ops('u1'), isEmpty);
      expect(File(proof).existsSync(), isFalse);
    });

    test('R38: accepted, the answer lost, then a refresh — counted once, finished on the phone, never sent again', () async {
      final proof = await photo('p.jpg');
      await repo.myCash();
      await repo.pay('pu1', pay(amount: '300'), proofPhoto: proof);
      remote.loseNextAnswer = true;
      expect(await sync.drain('u1'), SyncResult.retry, reason: 'no answer: the phone still holds it');
      expect([remote.paid.length, (await db.ops('u1')).length], [1, 1]);
      // The fresh balance already counts the ₱300 (the server has it).
      final mine = await repo.myPurchases();
      expect([mine.queuedPayments, mine.unsentFor('pu1')], [isEmpty, 0]);
      expect((await repo.myCash()).unsentPettyCash, 0);
      expect(await db.ops('u1'), isEmpty);
      expect(File(proof).existsSync(), isFalse);
      expect(await sync.drain('u1'), SyncResult.done);
      expect(remote.paid, hasLength(1), reason: 'never a second send');
    });

    test('R38: only what the server has is finished; with no signal nothing is', () async {
      await repo.pay('pu1', pay(amount: '100'));
      await repo.pay('pu1', pay(amount: '200'));
      remote.accepted.add('id1');
      final mine = await repo.myPurchases();
      expect([for (final q in mine.queuedPayments) q.opId], ['id2']);
      expect(mine.unsentFor('pu1'), 200);
      remote.accepted.add('id2');
      remote.readError = const SocketException('down');
      expect((await repo.myPurchases()).queuedPayments, hasLength(1), reason: 'no signal: nothing is finished on a guess');
    });

    test('R38: the answer lost, the check finds it, then the list read fails — the saved list still counts it (My purchases)', () async {
      await repo.myPurchases();
      await repo.pay('pu1', pay(amount: '300'));
      remote.loseNextAnswer = true;
      await sync.drain('u1');
      remote.balanceError = const SocketException('down');
      final v = await repo.myPurchases();
      expect([v.fromCache, v.unsentFor('pu1'), v.sentFor('pu1'), v.queuedPayments.single.state], [true, 300, true, QueuedState.sent],
          reason: 'the saved list was read before the payment went');
      expect(await db.ops('u1'), isEmpty, reason: 'marked sent: never sent again');
      expect(await sync.drain('u1'), SyncResult.done);
      expect(remote.paid, hasLength(1));
      remote.balanceError = null;
      final fresh = await repo.myPurchases();
      expect([fresh.fromCache, fresh.queuedPayments, fresh.unsentFor('pu1')], [false, isEmpty, 0], reason: 'the fresh list counts it');
    });

    test('R38: the answer lost, the check finds it, then the cash read fails — the saved cash held still counts it (My cash)', () async {
      await repo.myCash();
      await repo.pay('pu1', pay(amount: '300'));
      remote.loseNextAnswer = true;
      await sync.drain('u1');
      remote.balanceError = const SocketException('down');
      final v = await repo.myCash();
      expect([v.fromCache, v.unsentPettyCash, v.figures!.held], [true, 300, 1170]);
      remote.balanceError = null;
      remote.cash = {...remote.cash, 'recorded': 1170, 'held': 1170};
      final fresh = await repo.myCash();
      expect([fresh.fromCache, fresh.unsentPettyCash, fresh.figures!.held], [false, 0, 1170]);
    });

    test('R38: sent normally, then no signal — each saved copy counts it until that copy is read fresh; then it is forgotten', () async {
      await repo.myPurchases();
      await repo.myCash();
      await repo.pay('pu1', pay(amount: '300'));
      await sync.drain('u1');
      remote.readError = const SocketException('down');
      expect((await repo.myPurchases()).unsentFor('pu1'), 300);
      expect((await repo.myCash()).unsentPettyCash, 300);
      remote.readError = null;
      await repo.myPurchases();
      expect(await db.sentOps('u1'), hasLength(1), reason: 'the saved My cash does not count it yet');
      remote.readError = const SocketException('down');
      expect((await repo.myCash()).unsentPettyCash, 300);
      expect((await repo.myPurchases()).unsentFor('pu1'), 0, reason: 'the saved list now counts it');
      remote.readError = null;
      await repo.myCash();
      expect(await db.sentOps('u1'), isEmpty, reason: 'both copies count it');
      remote.readError = const SocketException('down');
      expect([(await repo.myCash()).unsentPettyCash, (await repo.myPurchases()).unsentFor('pu1')], [0, 0]);
    });

    test('R38: a saved My cash that counts a sent payment never lowers cash held by it again', () async {
      await repo.myPurchases();
      await repo.myCash();
      await repo.pay('pu1', pay(amount: '300'));
      await sync.drain('u1');
      remote.cash = {...remote.cash, 'recorded': 1170, 'held': 1170};
      await repo.myCash();
      expect(await db.sentOps('u1'), hasLength(1), reason: 'the saved list does not count it yet');
      remote.readError = const SocketException('down');
      final v = await repo.myCash();
      expect([v.fromCache, v.unsentPettyCash, v.figures!.held], [true, 0, 1170]);
      expect((await repo.myPurchases()).unsentFor('pu1'), 300);
    });

    test('R38: sent while the cash is being read — read again, so it is counted exactly once', () async {
      await repo.pay('pu1', pay(amount: '300'));
      remote.duringRead = () async {
        await sync.drain('u1');
        remote.cash = {...remote.cash, 'recorded': 1170, 'held': 1170};
      };
      final v = await repo.myCash();
      expect([v.fromCache, v.unsentPettyCash, v.figures!.held], [false, 0, 1170]);
      expect(remote.calls.where((c) => c == 'myCash'), hasLength(2));
    });

    test('R38: still moving after three reads, or no signal for the check after the read — the saved copy, not a guess', () async {
      await repo.myCash();
      remote.duringRead = () async {
        await repo.pay('pu1', pay(amount: '10'));
        await sync.drain('u1');
      };
      final busy = await repo.myCash();
      expect([busy.fromCache, busy.unsentPettyCash, remote.calls.where((c) => c == 'myCash').length], [true, 30, 4]);
      // A payment still waiting, so the check after the read asks the server.
      remote.duringRead = null;
      remote.writeError = const SocketException('no signal');
      remote.writeErrorSticky = true;
      await repo.pay('pu1', pay(amount: '300'));
      await sync.drain('u1');
      remote.duringRead = () async {
        remote.cash = {...remote.cash, 'held': 999};
        remote.opsDoneError = const SocketException('lost');
      };
      final lost = await repo.myCash();
      expect([lost.fromCache, lost.cash!.held], [true, 1470], reason: 'the read cannot be placed: not used');
    });

    test('R38: a purchase\'s payments and what the phone still holds come from one read', () async {
      await repo.myPurchases();
      await repo.myCash();
      await repo.pay('pu1', pay(amount: '100'));
      expect([for (final q in (await repo.purchasePayments('pu1')).queued) q.state], [QueuedState.waiting]);
      remote.duringRead = () => sync.drain('u1');
      final v = await repo.purchasePayments('pu1');
      expect([v.queued, remote.calls.where((c) => c == 'payments:pu1').length], [isEmpty, 3], reason: 'sent during the read: read again');
      remote.duringRead = null;
      remote.readError = const SocketException('down');
      expect([for (final q in await repo.queuedPayments('pu1')) q.state], [QueuedState.sent], reason: 'the saved list does not count it');
      remote.readError = null;
      await repo.myPurchases();
      expect(await db.sentOps('u1'), hasLength(1), reason: 'the saved My cash does not count it yet');
      expect(await repo.queuedPayments('pu1'), isEmpty, reason: 'the saved list counts it now');
    });

    test('a purchase\'s own payments still on the phone (for its detail screen)', () async {
      await repo.pay('pu1', pay(amount: '100'));
      await repo.pay('pu2', pay(amount: '50'));
      expect([for (final q in await repo.queuedPayments('pu1')) q.amount], [100]);
    });

    test('a payment still waiting cannot be thrown away (it may already be recorded)', () async {
      await repo.pay('pu1', pay());
      await repo.discardAction('id1');
      expect(await db.ops('u1'), hasLength(1));
    });
  });

  group('a return of petty cash (Q17): queued, its photo in the private pettyCash/ folder', () {
    test('refused before queueing: no amount, a future day', () async {
      await expectLater(repo.reportReturn(ReturnInput(amount: '', handedOn: today)), throwsA(isA<ReturnInvalid>()));
      await expectLater(repo.reportReturn(const ReturnInput(amount: '100', handedOn: '2099-01-01')), throwsA(isA<ReturnInvalid>()));
      expect(await db.ops('u1'), isEmpty);
    });

    test('waits on "My cash", then is sent with its photo as a petty_cash upload; never lowers cash held itself', () async {
      final ph = await photo('ret.jpg');
      await repo.reportReturn(ReturnInput(amount: '1,000', handedOn: today, handedTo: ' the owner ', note: 'ZZ'), photo: ph);
      final v = await repo.myCash();
      expect([v.queuedReturns.single.amount, v.unsentPettyCash], [1000, 0], reason: 'Q17: only the owner\'s confirmation lowers the balance');
      await sync.drain('u1');
      expect(remote.uploads.single, startsWith('pettyCash/o1/'));
      expect(remote.uploadKinds, ['petty_cash']);
      final r = remote.returned.single;
      expect([r['op'], r['amount'], r['handed_on'], r['handed_to'], r['note']], ['id1', '1000.00', today, 'the owner', 'ZZ']);
      expect(r['photo_url'], endsWith(remote.uploads.single));
      expect((await repo.myCash()).queued, isEmpty);
    });

    test('no photo: sent with none', () async {
      await repo.reportReturn(ReturnInput(amount: '50', handedOn: today));
      await sync.drain('u1');
      expect([remote.uploads, remote.returned.single['photo_url']], [isEmpty, '']);
    });
  });

  group('"Paid now?" rides with its purchase (Q3)', () {
    Future<PurchaseDraft> ready({String paidNow = 'full', String paidFrom = 'petty_cash', String? credit}) async => repo
        .newDraft(lines: [unplanned()])
        .copyWith(receiptTotal: '500', photos: {'supplier_invoice_url': await photo('r.jpg')}, paidNow: paidNow, paidFrom: paidFrom, paidCredit: credit);

    test('one pur_record with the payment inside it; its petty cash counts on "My cash" until sent', () async {
      await repo.myCash();
      remote.readError = const SocketException('down');
      await repo.send(await ready());
      expect((await repo.myCash()).unsentPettyCash, 500);
      remote.readError = null;
      await sync.drain('u1');
      expect(remote.recorded.single['payments'], [
        {'amount': '500.00', 'paid_on': '2026-10-21', 'source': 'petty_cash', 'method': 'cash', 'note': ''},
      ]);
      expect(remote.paid, isEmpty, reason: 'never a second call: both or neither');
    });

    test('petty cash from an account this phone knows is not a staff buyer: refused before sending (R2)', () async {
      remote.cash = {'holder': false};
      await repo.myCash();
      await expectLater(repo.send(await ready()),
          throwsA(isA<PurchaseInvalid>().having((e) => e.problems.map((p) => p.kind), 'kinds', [ProblemKind.personRequired])));
    });

    test('a credit: never more than it had left when last read (R10)', () async {
      remote.creditRows = [{'id': 'c1', 'supplier_id': 's1', 'left': 80}];
      await repo.myCash();
      await expectLater(repo.send(await ready(paidFrom: 'credit', credit: 'c1')),
          throwsA(isA<PurchaseInvalid>().having((e) => e.problems.map((p) => p.kind), 'kinds', [ProblemKind.overCredit])));
    });

    test('never read: petty cash is sent, and the server decides', () async {
      await repo.send(await ready());
      expect(await db.ops('u1'), hasLength(1));
    });
  });

  group('online only: voiding a payment, withdrawing a return, "I did not receive this"', () {
    test('a void needs a reason; each sends its form\'s op id', () async {
      await expectLater(repo.voidPayment('p1', '  ', opId: 'op1'), throwsA(isA<PurFailureException>()));
      await repo.voidPayment('p1', ' paid twice ', opId: 'op1');
      await repo.withdrawReturn('r1', opId: 'op2');
      await repo.dispute('i1', ' never got it ', opId: 'op3');
      expect(remote.calls.where((c) => !c.startsWith('my')),
          ['voidPayment:op1:p1:paid twice', 'withdraw:op2:r1', 'dispute:op3:i1:never got it']);
    });

    test('BUYER_REQUIRED on any of them turns buying off (R26)', () async {
      remote.writeError = Exception('BUYER_REQUIRED');
      await expectLater(repo.dispute('i1', 'x', opId: 'op1'), throwsA(anything));
      expect(turnedOff, 1);
    });

    test('a purchase\'s payments, read online', () async {
      remote.payments = {
        'pay': {'state': 'partial', 'tracked': true, 'due': 1000, 'paid': 300, 'balance': 700},
        'payments': [{'id': 'p1', 'amount': 300, 'source': 'petty_cash', 'can_void': true}],
        'open_credits': [], 'me': {'holder': true, 'own_money': true, 'cash_held': 700},
      };
      final pp = (await repo.purchasePayments('pu1')).pay;
      expect([pp.pay.balance, pp.payments.single.canVoid, pp.ownMoney, pp.cashHeld], [700, true, true, 700]);
    });
  });

  test('only the signed-in account\'s payments and returns are sent', () async {
    await repo.pay('pu1', pay());
    user = 'u2';
    await repo.reportReturn(ReturnInput(amount: '10', handedOn: today));
    await sync.drain('u1');
    expect([remote.paid.length, remote.returned.length], [1, 0]);
    await sync.drain('u2');
    expect(remote.returned.length, 1);
  });
}

/// Manila's date at the harness's [wednesday] — what [PurchasingRepository.today] answers.
String repoToday() => '2026-10-21';
