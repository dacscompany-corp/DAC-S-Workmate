import 'package:flutter_test/flutter_test.dart';
import 'package:workmate/purchasing/domain/pay_models.dart';
import 'package:workmate/purchasing/domain/pur_failure.dart';
import 'package:workmate/purchasing/domain/pur_models.dart';
import 'package:workmate/purchasing/domain/purchase_draft.dart';

PurchaseDraft draft({String paidNow = 'none', String paidAmount = '', String paidFrom = 'company', String? paidCredit, String total = '1250'}) =>
    PurchaseDraft(
      id: 'd1',
      createdAt: DateTime.utc(2026, 10, 23, 2),
      purchaseDate: '2026-10-23',
      supplierName: 'ZZ Hardware',
      receiptTotal: total,
      lines: const [
        DraftPurchaseLine(key: 'k1', itemName: 'ZZ cement', quantity: '1', unit: 'bag', amount: '1250', folderId: 'f1', unplannedReason: 'ZZ'),
      ],
      photos: const {'supplier_invoice_url': '/p/a.jpg'},
      paidNow: paidNow,
      paidAmount: paidAmount,
      paidFrom: paidFrom,
      paidMethod: 'gcash',
      paidCredit: paidCredit,
    );

void main() {
  group('the server\'s answers as the phone reads them', () {
    test('pay state: numbers as numbers or text; absent = not tracked (Q2)', () {
      final s = PayState.fromJson({'state': 'partial', 'tracked': true, 'due': '1000', 'paid': 300, 'balance': '700.00', 'excess': 0, 'unresolved': 0});
      expect([s.state, s.tracked, s.due, s.paid, s.balance], ['partial', true, 1000, 300, 700]);
      expect(const PayState().state, 'not_tracked');
      expect(PayState.fromJson(null).tracked, isFalse);
      expect(PayState.fromJson(s.toJson()).balance, 700, reason: 'kept for offline as it came');
    });

    test('Q6: what is left counts payments still on the phone, never below zero', () {
      const s = PayState(state: 'partial', tracked: true, due: 1000, paid: 300, balance: 700);
      expect(s.leftAfter(0), 700);
      expect(s.leftAfter(200), 500);
      expect(s.leftAfter(900), 0);
      expect(const PayState(state: 'void_paid').payable, isFalse, reason: 'R12: no new payment on a voided purchase');
      expect([const PayState(state: 'not_tracked').canRecordPayment, s.canRecordPayment, const PayState(state: 'void_paid', tracked: true).canRecordPayment],
          [false, true, false], reason: 'R34: tracked and not voided — the same rule on every screen');
      expect(const PayState(state: 'overpaid').payable, isTrue);
    });

    test('a payment: carried over, own money to review, rejected, void', () {
      final p = PurPayment.fromJson({
        'id': 'p1', 'amount': '200', 'paid_on': '2026-10-23', 'method': 'cash', 'source': 'own_money', 'authorized': false,
        'accepted_at': null, 'rejected_at': null, 'moved': true, 'can_void': true,
      });
      expect([p.toReview, p.moved, p.canVoid, p.voided], [true, true, true, false]);
      expect(PurPayment.fromJson({'id': 'p2', 'source': 'own_money', 'authorized': false, 'rejected_at': '2026-10-23T01:00:00Z'}).toReview, isFalse,
          reason: 'R9: a rejected claim is decided');
      expect(PurPayment.fromJson({'id': 'p3', 'source': 'own_money'}).authorized, isTrue, reason: 'missing = authorized (switch on)');
    });

    test('My cash: the buyer\'s own, with the return photo (0103) and the flags', () {
      final c = MyCash.fromJson({
        'holder': true, 'recorded': '-530', 'held': 0, 'shortfall': 530, 'pending_returns': '1000', 'owes': 50, 'owes_to_review': 100,
        'own_money': false,
        'issues': [
          {'id': 'i1', 'amount': 4500, 'issued_on': '2026-10-22', 'disputed_at': '2026-10-23T00:36:00Z', 'dispute_cleared_at': null},
          {'id': 'i2', 'amount': 500, 'issued_on': '2026-10-22', 'voided_at': '2026-10-23T01:12:00Z'},
          {'id': 'i3', 'amount': 100, 'issued_on': '2026-10-23'},
        ],
        'returns': [
          {'id': 'r1', 'amount': 1000, 'handed_on': '2026-10-23', 'status': 'reported', 'photo_url': 'https://x/pettyCash/a.jpg'},
        ],
        'repayments': [{'id': 'x1', 'amount': 150, 'paid_on': '2026-10-23', 'method': 'cash'}],
      });
      expect([c.holder, c.recorded, c.held, c.shortfall, c.pendingReturns, c.owes, c.owesToReview, c.ownMoney],
          [true, -530, 0, 530, 1000, 50, 100, false]);
      expect([for (final i in c.issues) (i.flagged, i.canDispute)], [(true, false), (false, false), (false, true)],
          reason: 'Q14: one flag per entry; a voided entry is settled');
      expect([c.returns.single.waiting, c.returns.single.photoUrl], [true, 'https://x/pettyCash/a.jpg']);
      expect(c.repayments.single.amount, 150);
      expect(MyCash.fromJson({'holder': false}).holder, isFalse, reason: 'an owner account holds no petty cash (R2)');
    });

    test('supplier credits: usable only when not voided and something is left (Q11)', () {
      final c = SupplierCredit.fromJson({'id': 'c1', 'supplier_id': 's1', 'supplier': 'ZZ Hardware', 'amount': 200, 'left': '80'});
      expect([c.usable, c.left], [true, 80]);
      expect(SupplierCredit.fromJson({'id': 'c2', 'left': 0}).usable, isFalse);
      expect(SupplierCredit.fromJson({'id': 'c3', 'left': 50, 'voided_at': '2026-10-23'}).usable, isFalse);
      expect(SupplierCredit.fromJson(c.toJson()).left, 80, reason: 'kept for offline');
    });

    test('a My purchases row carries its payment state (0102) and its listed supplier (0103)', () {
      final row = MyPurchase.fromJson({
        'id': 'u1', 'status': 'recorded', 'supplier': 'ZZ Hardware', 'supplier_id': 's1', 'receipt_total': 1000,
        'pay': {'state': 'partial', 'tracked': true, 'due': 1000, 'paid': 300, 'balance': 700},
      });
      expect([row.supplierId, row.pay.state, row.pay.balance], ['s1', 'partial', 700]);
      final old = MyPurchase.fromJson({'id': 'u2', 'status': 'recorded'});
      expect([old.supplierId, old.pay.state], [null, 'not_tracked'], reason: 'a saved copy from before 0102/0103 still reads');
    });

    test('a purchase\'s payments with what this account may use', () {
      final pp = PurchasePayments.fromJson({
        'pay': {'state': 'unpaid', 'tracked': true, 'due': 500, 'balance': 500},
        'supplier_id': 's1',
        'payments': [{'id': 'p1', 'amount': 100, 'voided_at': '2026-10-23'}],
        'open_credits': [{'id': 'c1', 'left': 80}],
        'me': {'holder': true, 'own_money': true, 'cash_held': '-20'},
      });
      expect([pp.pay.balance, pp.supplierId, pp.payments.single.voided, pp.openCredits.single.left, pp.holder, pp.ownMoney, pp.cashHeld],
          [500, 's1', true, 80, true, true, -20]);
    });
  });

  group('Q16: cash held is never below zero; overspending warns, never refuses', () {
    test('payments still on the phone lower it; the rest is the shortfall', () {
      const c = MyCash(holder: true, recorded: 1470);
      expect(cashAfter(c), (held: 1470.0, shortfall: 0.0));
      expect(cashAfter(c, unsentPettyCash: 2000), (held: 0.0, shortfall: 530.0));
    });
    test('the warning names what is over; nothing to warn about = null', () {
      expect(overspendBy('2000', 1470), 530);
      expect(overspendBy('100', -530), 100, reason: 'a shortfall holds ₱0');
      expect(overspendBy('1470', 1470), isNull);
      expect(overspendBy('1470.01', 1470), 0.01, reason: 'a centavo over is over');
      expect(overspendBy('', 100), isNull);
      expect(overspendBy('500', null), isNull, reason: 'unknown balance: no warning');
    });
  });

  group('a payment is refused before sending exactly where the server would refuse it', () {
    const today = '2026-10-23';
    PaymentInput pay({String amount = '300', String paidOn = today, String method = 'gcash', String source = 'company', String? creditId}) =>
        PaymentInput(amount: amount, paidOn: paidOn, method: method, source: source, creditId: creditId);

    test('amount, date (Manila today, from 2020), source, method', () {
      expect(paymentProblems(pay(), today: today), isEmpty);
      expect(paymentProblems(pay(amount: '0'), today: today), [PayProblem.badAmount]);
      expect(paymentProblems(pay(amount: '1.005'), today: today), [PayProblem.badAmount], reason: 'two decimals at most');
      expect(paymentProblems(pay(paidOn: '2026-10-24'), today: today), [PayProblem.badDate], reason: 'never in the future');
      expect(paymentProblems(pay(paidOn: '2019-12-31'), today: today), [PayProblem.badDate]);
      expect(paymentProblems(pay(paidOn: '23/10/2026'), today: today), [PayProblem.badDate]);
      expect(paymentProblems(pay(source: 'loan'), today: today), [PayProblem.badSource]);
      expect(paymentProblems(pay(method: 'barter'), today: today), [PayProblem.badMethod]);
    });

    test('a supplier credit: one must be chosen; never more than it has left', () {
      expect(paymentProblems(pay(source: 'credit', method: 'barter'), today: today), [PayProblem.creditRequired],
          reason: 'a credit is not cash: no method is checked');
      expect(paymentProblems(pay(source: 'credit', creditId: 'c1', amount: '120'), today: today, creditLeft: 80), [PayProblem.overCredit]);
      expect(paymentProblems(pay(source: 'credit', creditId: 'c1', amount: '80'), today: today, creditLeft: 80), isEmpty);
      expect(paymentProblems(pay(source: 'credit', creditId: 'c1', amount: '500'), today: today), isEmpty, reason: 'unknown left: the server checks');
    });

    test('the body: two decimals as text; a credit is "other" with its id; no person (the server fills in the buyer); proof only when given', () {
      expect(paymentBody(pay(amount: '1,250.5')),
          {'amount': '1250.50', 'paid_on': today, 'source': 'company', 'method': 'gcash', 'note': ''});
      final c = paymentBody(pay(source: 'credit', creditId: 'c1', method: 'cash'));
      expect([c['method'], c['credit_id'], c.containsKey('person_id')], ['other', 'c1', false]);
      final petty = paymentBody(const PaymentInput(amount: '700', paidOn: today, source: 'petty_cash', proofUrl: 'https://x/p.jpg', note: ' slip '));
      expect([petty['source'], petty['method'], petty.containsKey('person_id'), petty['proof_url'], petty['note']],
          ['petty_cash', 'cash', false, 'https://x/p.jpg', 'slip']);
      expect(PaymentInput.fromJson(pay(source: 'credit', creditId: 'c1').toJson()).creditId, 'c1', reason: 'kept on the phone as typed');
    });

    test('the purchase form\'s "Paid by" word becomes a payment method', () {
      expect([methodOf('GCash'), methodOf('Bank transfer'), methodOf('On account'), methodOf('')], ['gcash', 'bank_transfer', 'cash', 'cash']);
    });
  });

  group('Q3 "Paid now?": sent with the purchase, in the same transaction', () {
    test('Not paid yet sends no payment; older drafts on the phone read Not paid yet', () {
      expect(paidNowPayment(draft()), isNull);
      expect(purchaseBody(draft()).containsKey('payments'), isFalse);
      final old = draft().toJson()..removeWhere((k, _) => k.startsWith('paid_'));
      expect(PurchaseDraft.fromJson(old).paidNow, 'none');
    });

    test('Paid in full sends the receipt total, dated the purchase\'s own day', () {
      final body = purchaseBody(draft(paidNow: 'full', paidFrom: 'petty_cash'));
      expect(body['payments'], [
        {'amount': '1250.00', 'paid_on': '2026-10-23', 'source': 'petty_cash', 'method': 'gcash', 'note': ''},
      ]);
    });

    test('Paid part: the typed amount, less than the total', () {
      expect((purchaseBody(draft(paidNow: 'part', paidAmount: '300'))['payments'] as List).single['amount'], '300.00');
      expect(paidNowProblems(draft(paidNow: 'part', paidAmount: '1250'), holder: true).map((p) => p.kind), [ProblemKind.partNotLess]);
      expect(paidNowProblems(draft(paidNow: 'part', paidAmount: ''), holder: true).map((p) => p.kind), [ProblemKind.paidAmount]);
    });

    test('petty cash and own money need a staff buyer (R2); a credit needs one chosen, within what is left (R10)', () {
      expect(paidNowProblems(draft(paidNow: 'full', paidFrom: 'own_money'), holder: false).map((p) => p.kind), [ProblemKind.personRequired]);
      expect(paidNowProblems(draft(paidNow: 'full', paidFrom: 'petty_cash'), holder: true), isEmpty);
      expect(paidNowProblems(draft(paidNow: 'full', paidFrom: 'credit'), holder: true).map((p) => p.kind), [ProblemKind.creditRequired]);
      expect(paidNowProblems(draft(paidNow: 'full', paidFrom: 'credit', paidCredit: 'c1'), holder: true, creditLeft: 80).map((p) => p.kind),
          [ProblemKind.overCredit]);
      final credit = (purchaseBody(draft(paidNow: 'part', paidAmount: '50', paidFrom: 'credit', paidCredit: 'c1'))['payments'] as List).single;
      expect([credit['source'], credit['credit_id'], credit['method']], ['credit', 'c1', 'other']);
      expect(paidNowProblems(draft(), holder: false), isEmpty, reason: 'Not paid yet asks nothing');
    });

    test('the draft keeps "Paid now?" as typed', () {
      final d = PurchaseDraft.fromJson(draft(paidNow: 'part', paidAmount: '300', paidFrom: 'credit', paidCredit: 'c1').toJson());
      expect([d.paidNow, d.paidAmount, d.paidFrom, d.paidMethod, d.paidCredit], ['part', '300', 'credit', 'gcash', 'c1']);
      expect(d.copyWith(paidCredit: null).paidCredit, isNull);
      expect(d.copyWith(paidNow: 'full').paidCredit, 'c1');
    });
  });

  group('every 0102 refusal a buyer can meet says what to do', () {
    test('whole codes only: BAD_PAY_SOURCE is not BAD_PAY, PERSON_NOT_ALLOWED is not NOT_ALLOWED', () {
      expect(PurFailure.of(Exception('BAD_PAY_SOURCE')), PurFailure.invalid);
      expect(PurFailure.of(Exception('PERSON_NOT_ALLOWED')), PurFailure.notAHolder);
      expect(PurFailure.of(Exception('NOT_ALLOWED')), PurFailure.buyingOff);
      expect(PurFailure.of(Exception('OVER_CREDIT')), PurFailure.overCredit);
      expect(PurFailure.of(Exception('CREDIT_GONE')), PurFailure.creditGone);
      expect(PurFailure.of(Exception('CREDIT_SUPPLIER')), PurFailure.creditSupplier);
      expect(PurFailure.of(Exception('RESOLVED_FIRST')), PurFailure.resolvedFirst);
      expect(PurFailure.of(Exception('NOT_YOURS')), PurFailure.notYours);
      expect(PurFailure.of(Exception('ALREADY_DISPUTED')), PurFailure.alreadyDisputed);
      expect(PurFailure.of(Exception('NOT_A_BUYER')), PurFailure.notAHolder);
      expect(PurFailure.of(Exception('BAD_STATE')), PurFailure.alreadyVoided, reason: 'a payment on a voided purchase (R12)');
    });
    test('none of them is retried: the content would be refused again', () {
      for (final f in [PurFailure.overCredit, PurFailure.creditGone, PurFailure.creditSupplier, PurFailure.resolvedFirst, PurFailure.notYours,
          PurFailure.alreadyDisputed, PurFailure.notAHolder]) {
        expect(f.retryable, isFalse, reason: f.name);
        expect(purFailureCopy(f).english, isNotEmpty);
        expect(purFailureCopy(f).tagalog, isNotEmpty);
      }
    });
  });
}
