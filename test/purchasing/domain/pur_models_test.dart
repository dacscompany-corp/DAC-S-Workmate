import 'package:flutter_test/flutter_test.dart';
import 'package:workmate/purchasing/domain/pur_failure.dart';
import 'package:workmate/purchasing/domain/pur_models.dart';
import 'package:workmate/purchasing/domain/pur_op.dart';

import '../purchasing_fakes.dart';

void main() {
  test('"this week" is the first batch whose cutoff is still ahead (the Purchasing tab\'s rule)', () {
    expect(PurBatch.current([nextWeek, thisWeek], wednesday)!.id, 'b1');
    expect(PurBatch.current([thisWeek, nextWeek], DateTime.utc(2026, 10, 24, 5))!.id, 'b2');
    expect(PurBatch.current([thisWeek], DateTime.utc(2026, 12)), isNull);
  });

  test('a shopping line reads numbers sent as numbers or numeric text', () {
    final l = ShoppingLine.fromJson({
      'line_id': 'l1',
      'request_id': 'r1',
      'description': 'Cement',
      'unit': 'bag',
      'project_name': 'Barlin Residence',
      'work_name': 'AW-02 Fence',
      'needed': '10.000',
      'bought': 4,
      'still_to_buy': 6,
      'portions': [
        {'id': 'p1', 'batch_id': 'b1', 'quantity': '6', 'still_to_buy': '6', 'buyer_id': null, 'mine': false, 'changed': true},
      ],
    });
    expect(l.needed, 10);
    expect(l.bought, 4);
    expect(l.placeLabel, 'Barlin Residence · AW-02 Fence');
    expect(l.portions.single.unassigned, isTrue);
    expect(l.portions.single.changed, isTrue);
    expect(ShoppingLine.fromJson(l.toJson()).toJson(), l.toJson());
  });

  test('the main contract shows the project alone', () {
    expect(cement().placeLabel, 'Barlin Residence');
  });

  test('a supplier reads as the server writes it on the purchase', () {
    expect(zzHardware.label, 'ZZ Hardware · Malolos');
    expect(const Supplier(id: 's', name: 'Wilcon').label, 'Wilcon');
  });

  test('a purchase keeps only the four receipt slots, and says what it waits for', () {
    final p = PurchaseDetail.fromJson({
      'id': 'pu1',
      'status': 'recorded',
      'receipt_total': '530.00',
      'docs': {'supplier_invoice_url': 'https://x/a.jpg', 'po_image_url': '', 'evil': 'javascript:x'},
      'lines': [
        {'line': 1, 'item_name': 'Cement', 'unit_check': 'pending', 'amount': '500'},
      ],
      'charges': [
        {'kind': 'delivery_fee', 'amount': 30, 'shares': [{'line': 1, 'amount': 30}]},
      ],
      'change_requests': [
        {'kind': 'correct', 'status': 'pending', 'reason': 'Wrong price'},
      ],
    });
    expect(p.receiptTotal, 530);
    expect(p.docs, {'supplier_invoice_url': 'https://x/a.jpg'});
    expect(p.needsOfficeCheck, isTrue);
    expect(p.waitingForOwner, isTrue);
    expect(p.charges.single.shares, {1: 30});
  });

  test('a receipt goes where 0097 lets a buyer put it, in Manila\'s month', () {
    expect(
      receiptPath(companyId: 'O1', manilaNow: DateTime.utc(2026, 11, 1, 1), photoId: 'AB'),
      'purchases/o1/2026-11/ab.jpg',
    );
  });

  group('failures', () {
    test('whole codes only: a longer code is never read as REASON_REQUIRED', () {
      expect(PurFailure.of(refusal('UNPLANNED_REASON_REQUIRED')), PurFailure.unplannedReasonRequired);
      expect(PurFailure.of(refusal('EXTRA_REASON_REQUIRED')), PurFailure.extraReasonRequired);
      expect(PurFailure.of(refusal('SUBSTITUTE_REASON_REQUIRED')), PurFailure.substituteReasonRequired);
      expect(PurFailure.of(refusal('REASON_REQUIRED')), PurFailure.reasonRequired);
    });

    test('the Buyer switch being off is one failure, whatever check found it (R2)', () {
      for (final code in ['BUYER_REQUIRED', 'NOT_OFFICE', 'NOT_ALLOWED', 'OFFICE_ONLY']) {
        expect(PurFailure.of(refusal(code)), PurFailure.buyingOff, reason: code);
      }
    });

    test('a refusal is never retried; signal, session and the unknown are', () {
      expect(PurFailure.of(refusal('LINE_CLOSED')).retryable, isFalse);
      expect(PurFailure.of(refusal('BUYER_REQUIRED')).retryable, isFalse);
      expect(PurFailure.of(StateError('AUTH_REQUIRED')), PurFailure.sessionExpired);
      expect(PurFailure.sessionExpired.retryable, isTrue);
      expect(PurFailure.of(Exception('weird')), PurFailure.unexpected);
      expect(PurFailure.unexpected.retryable, isTrue);
      expect(PurFailure.unexpected.countsTowardCap, isTrue);
      expect(PurFailure.noConnection.countsTowardCap, isFalse);
    });

    test('a stored name reads back; an unknown one is unexpected', () {
      expect(PurFailure.fromStored('lineClosed'), PurFailure.lineClosed);
      expect(PurFailure.fromStored('nope'), PurFailure.unexpected);
    });

    test('every failure has English and Tagalog copy (Q22)', () {
      for (final f in PurFailure.values) {
        final c = purFailureCopy(f);
        expect(c.english, isNotEmpty, reason: f.name);
        expect(c.tagalog, isNotEmpty, reason: f.name);
        expect(c.english, isNot(c.tagalog), reason: f.name);
      }
    });
  });
}
