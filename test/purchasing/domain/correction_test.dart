import 'package:flutter_test/flutter_test.dart';
import 'package:workmate/purchasing/domain/correction.dart';
import 'package:workmate/purchasing/domain/pur_models.dart';

/// A recorded phone purchase: two lines, one fee split 30/10 by hand.
final stored = PurchaseDetail.fromJson(const {
  'id': 'pu1',
  'status': 'recorded',
  'source': 'workmate',
  'purchase_date': '2026-10-20',
  'date_time': '2026-10-20T09:30:00',
  'supplier': 'ZZ Hardware · Malolos',
  'supplier_id': 's1',
  'payment_method': 'Cash',
  'notes': 'Rush',
  'receipt_total': 440,
  'docs': {'supplier_invoice_url': 'https://x/a.jpg'},
  'lines': [
    {'line': 1, 'destination': 'project', 'folder_id': 'f1', 'folder_name': 'Barlin Residence', 'item_name': 'Cement', 'category': 'Materials',
      'quantity': 10, 'unit': 'bag', 'amount': 300, 'request_line_id': 'l1', 'in_inventory': false, 'min_stock': 0},
    {'line': 2, 'destination': 'warehouse', 'folder_id': null, 'folder_name': '', 'item_name': 'Wire', 'category': 'Materials',
      'quantity': 2, 'unit': 'roll', 'amount': 100, 'in_inventory': true, 'min_stock': 5},
  ],
  'charges': [
    {'kind': 'delivery_fee', 'amount': 40, 'shares': [{'line': 1, 'amount': 30}, {'line': 2, 'amount': 10}]},
  ],
});

void main() {
  test('starts from the purchase as stored', () {
    final c = CorrectionDraft.of(stored);
    expect(c.purchaseDate, '2026-10-20');
    expect(c.quantities, ['10', '2']);
    expect(c.amounts, ['300.00', '100.00']);
    expect(c.receiptTotal, '440.00');
    expect(c.computedTotal(stored), 440);
  });

  test('a reason is required, and something must change (Q13)', () {
    final c = CorrectionDraft.of(stored);
    expect(correctionProblems(stored, c).map((x) => x.$1), [CorrectionProblem.reasonRequired]);
    expect(correctionProblems(stored, c.copyWith(reason: 'x')).map((x) => x.$1), [CorrectionProblem.nothingChanged]);
    expect(correctionProblems(stored, c.copyWith(reason: 'Typo', purchaseDate: '2026-10-19')), isEmpty);
  });

  test('quantities, amounts and the total are checked; the stored fees count', () {
    final c = CorrectionDraft.of(stored).copyWith(reason: 'Price', amounts: ['320', '100']);
    expect(correctionProblems(stored, c), [(CorrectionProblem.totalMismatch, null)]);
    expect(correctionProblems(stored, c.copyWith(receiptTotal: '460')), isEmpty);
    expect(correctionProblems(stored, c.copyWith(quantities: ['0', '2'], receiptTotal: '460')), [(CorrectionProblem.badQuantity, 1)]);
  });

  test('the body keeps request links, reasons and the picked supplier by leaving them out (pur_inherit)', () {
    final b = correctionBody(stored, CorrectionDraft.of(stored).copyWith(quantities: ['12', '2'], reason: 'Count'));
    final lines = b['lines'] as List;
    expect((lines[0] as Map).containsKey('request_line_id'), isFalse);
    expect((lines[0] as Map).containsKey('portion_picks'), isFalse);
    expect(b.containsKey('supplier_id'), isFalse);
    expect((lines[0] as Map)['quantity'], 12);
    expect((lines[1] as Map)['folder_id'], isNull);
    expect((lines[1] as Map)['in_inventory'], isTrue, reason: 'stock settings stay as stored');
    expect((lines[1] as Map)['min_stock'], 5);
    expect(b['source'], 'workmate');
    expect(b['notes'], 'Rush');
    expect(b['payment_method'], 'Cash');
  });

  test('the time of day stays while the date is unchanged', () {
    expect(correctionBody(stored, CorrectionDraft.of(stored))['date_time'], '2026-10-20T09:30:00');
    expect(correctionBody(stored, CorrectionDraft.of(stored).copyWith(purchaseDate: '2026-10-19'))['date_time'], '2026-10-19');
  });

  test('a typed supplier drops the picked one', () {
    final b = correctionBody(stored, CorrectionDraft.of(stored).copyWith(supplier: 'Wilcon', supplierChanged: true));
    expect(b['supplier'], 'Wilcon');
    expect(b.containsKey('supplier_id'), isTrue);
    expect(b['supplier_id'], isNull);
  });

  test('fees keep their split while no amount changed; otherwise the server splits them again', () {
    final same = correctionBody(stored, CorrectionDraft.of(stored).copyWith(quantities: ['12', '2']));
    expect(((same['charges'] as List).single as Map)['shares'], [
      {'line': 1, 'amount': 30},
      {'line': 2, 'amount': 10},
    ]);
    final priced = correctionBody(stored, CorrectionDraft.of(stored).copyWith(amounts: ['320', '100']));
    expect(((priced['charges'] as List).single as Map).containsKey('shares'), isFalse);
  });

  test('new photos alone are a change', () {
    expect(changed(stored, CorrectionDraft.of(stored).copyWith(photos: {'payment_receipt_url': '/p.jpg'})), isTrue);
  });
}
