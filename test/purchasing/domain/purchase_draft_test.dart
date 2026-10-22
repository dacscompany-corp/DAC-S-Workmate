import 'package:flutter_test/flutter_test.dart';
import 'package:workmate/purchasing/domain/purchase_draft.dart';

import '../purchasing_fakes.dart';

PurchaseDraft draft({
  List<DraftPurchaseLine>? lines,
  List<DraftCharge> charges = const [],
  String total = '500',
  Map<String, String> photos = const {'supplier_invoice_url': '/p/a.jpg'},
  bool noReceipt = false,
  String noReceiptReason = '',
}) =>
    PurchaseDraft(
      id: 'd1',
      createdAt: DateTime.utc(2026, 10, 21, 2),
      purchaseDate: '2026-10-21',
      supplierName: 'ZZ Hardware',
      receiptTotal: total,
      lines: lines ?? [unplanned()],
      charges: charges,
      photos: photos,
      noReceipt: noReceipt,
      noReceiptReason: noReceiptReason,
    );

DraftPurchaseLine unplanned({String amount = '500'}) => DraftPurchaseLine(
      key: 'k1',
      itemName: 'ZZ wire',
      quantity: '2',
      unit: 'roll',
      amount: amount,
      folderId: 'f1',
      folderLabel: 'Barlin Residence',
      unplannedReason: 'Site ran out',
    );

DraftPurchaseLine linked({String quantity = '10', String unit = 'bag', String amount = '500'}) =>
    DraftPurchaseLine.fromShopping('k2', cement(), [portion('p1', still: 10)]).copyWith(quantity: quantity, unit: unit, amount: amount);

void main() {
  group('money', () {
    test('two decimals at most, commas allowed while typing', () {
      expect(parseMoney('1,250.50'), 1250.5);
      expect(parseMoney('0'), 0);
      expect(parseMoney('12.345'), isNull);
      expect(parseMoney('-1'), isNull);
      expect(parseMoney(''), isNull);
    });

    test('the default split is the server\'s: centavos down, leftovers to the biggest remainders', () {
      expect(prorate(100, [1, 1, 1]), [33.34, 33.33, 33.33]);
      expect(prorate(10, [300, 100]), [7.5, 2.5]);
      expect(prorate(0.05, [1, 1]), [0.03, 0.02]);
      expect(prorate(10, [0, 0]), [5, 5]);
      for (final split in [prorate(99.99, [3, 7, 11]), prorate(1, [1, 1, 1, 1, 1, 1, 1])]) {
        expect(split.fold<double>(0, (a, b) => a + b), closeTo(split.length == 3 ? 99.99 : 1, 1e-9));
      }
    });
  });

  group('a line from the shopping list', () {
    test('takes the request\'s item, unit and place, and the Still to buy of the picked portions', () {
      final l = DraftPurchaseLine.fromShopping('k', cement(portions: [portion('p1', still: 4), portion('p2', still: 6)]),
          [portion('p1', still: 4), portion('p2', still: 6)]);
      expect(l.itemName, 'Cement');
      expect(l.unit, 'bag');
      expect(l.folderId, 'f1');
      expect(l.requestLineId, 'l1');
      expect(l.quantity, '10');
      expect(l.picks.map((p) => p.portionId), ['p1', 'p2']);
      expect(l.pickedStill, 10);
    });

    test('a portion with nothing left is not picked', () {
      final l = DraftPurchaseLine.fromShopping('k', cement(), [portion('p1', still: 0), portion('p2', still: 3)]);
      expect(l.picks.map((p) => p.portionId), ['p2']);
    });

    test('more than the picks still need is an extra; a different unit or a substitute never is', () {
      expect(linked(quantity: '12').extraQuantity, 2);
      expect(linked(quantity: '10').extraQuantity, 0);
      expect(linked(quantity: '12', unit: 'box').extraQuantity, 0);
      expect(linked(quantity: '12').copyWith(match: LineMatch.substitute).extraQuantity, 0);
    });

    test('same unit and not a substitute counts at once; otherwise it waits for the office check', () {
      expect(linked().countsDirectly, isTrue);
      expect(linked(unit: ' BAG ').countsDirectly, isTrue);
      expect(linked(unit: 'box').countsDirectly, isFalse);
      expect(linked().copyWith(match: LineMatch.substitute).countsDirectly, isFalse);
    });
  });

  group('problems before sending', () {
    test('a complete purchase has none', () {
      expect(purchaseProblems(draft()), isEmpty);
    });

    test('each line needs a name, a quantity, an amount and a place (Q11)', () {
      final d = draft(lines: [
        const DraftPurchaseLine(key: 'k', quantity: '0', amount: 'x', unplannedReason: 'r'),
      ]);
      expect(purchaseProblems(d), containsAll(const [
        PurchaseProblem(ProblemKind.badName, line: 1),
        PurchaseProblem(ProblemKind.badQuantity, line: 1),
        PurchaseProblem(ProblemKind.badAmount, line: 1),
        PurchaseProblem(ProblemKind.noProject, line: 1),
      ]));
    });

    test('the warehouse needs no project', () {
      final d = draft(lines: [unplanned().copyWith(destination: 'warehouse', folderId: null)]);
      expect(purchaseProblems(d), isEmpty);
    });

    test('an item with no request needs a reason (Q11)', () {
      final d = draft(lines: [unplanned().copyWith(unplannedReason: ' ')]);
      expect(purchaseProblems(d), [const PurchaseProblem(ProblemKind.unplannedReasonRequired, line: 1)]);
    });

    test('an extra needs a reason and a location (Q11)', () {
      final d = draft(lines: [linked(quantity: '12')]);
      expect(purchaseProblems(d), [const PurchaseProblem(ProblemKind.extraReasonRequired, line: 1)]);
      final ok = draft(lines: [linked(quantity: '12').copyWith(extraReason: 'Spare', extraLocation: 'warehouse')]);
      expect(purchaseProblems(ok), isEmpty);
    });

    test('a renamed item is either "other words" or a substitute — the buyer says which (Q10)', () {
      final renamed = linked().copyWith(itemName: 'Portland cement');
      expect(purchaseProblems(draft(lines: [renamed])), [const PurchaseProblem(ProblemKind.nameDiffers, line: 1)]);
      expect(purchaseProblems(draft(lines: [renamed.copyWith(match: LineMatch.otherWords)])), isEmpty);
      expect(purchaseProblems(draft(lines: [renamed.copyWith(match: LineMatch.substitute)])),
          [const PurchaseProblem(ProblemKind.substituteReasonRequired, line: 1)]);
      expect(purchaseProblems(draft(lines: [renamed.copyWith(match: LineMatch.substitute, substituteReason: '40 kg out')])), isEmpty);
    });

    test('a different unit needs a note (Q10, phone rule)', () {
      final box = linked(unit: 'box');
      expect(purchaseProblems(draft(lines: [box])), [const PurchaseProblem(ProblemKind.unitNoteRequired, line: 1)]);
      expect(purchaseProblems(draft(lines: [box.copyWith(unitNote: '1 box = 12 bags')])), isEmpty);
    });

    test('a receipt photo, or "No receipt" with a reason (Q8)', () {
      expect(purchaseProblems(draft(photos: const {})), [const PurchaseProblem(ProblemKind.noReceipt)]);
      expect(purchaseProblems(draft(photos: const {}, noReceipt: true)), [const PurchaseProblem(ProblemKind.noReceiptReason)]);
      expect(purchaseProblems(draft(photos: const {}, noReceipt: true, noReceiptReason: 'Sari-sari store')), isEmpty);
    });

    test('lines + fees − discounts must equal the receipt total (Q9)', () {
      final charges = [const DraftCharge(kind: 'delivery_fee', amount: '50'), const DraftCharge(kind: 'discount', amount: '20')];
      expect(purchaseProblems(draft(charges: charges, total: '530')), isEmpty);
      expect(purchaseProblems(draft(charges: charges, total: '500')), [const PurchaseProblem(ProblemKind.totalMismatch)]);
      expect(purchaseProblems(draft(total: '')), [const PurchaseProblem(ProblemKind.badTotal)]);
    });

    test('a fee needs an amount; an adjusted split must add up, one share per line', () {
      expect(purchaseProblems(draft(charges: [const DraftCharge(kind: 'delivery_fee', amount: '0')])),
          contains(const PurchaseProblem(ProblemKind.badChargeAmount, charge: 1)));
      final two = [unplanned(amount: '300'), unplanned(amount: '200')];
      expect(purchaseProblems(draft(lines: two, total: '550', charges: [const DraftCharge(kind: 'delivery_fee', amount: '50', shares: ['30', '10'])])),
          [const PurchaseProblem(ProblemKind.splitMismatch, charge: 1)]);
      expect(purchaseProblems(draft(lines: two, total: '550', charges: [const DraftCharge(kind: 'delivery_fee', amount: '50', shares: ['30', '20'])])),
          isEmpty);
    });

    test('no lines, or more than 50, is refused', () {
      expect(purchaseProblems(draft(lines: const [], total: '0')), contains(const PurchaseProblem(ProblemKind.noLines)));
      expect(purchaseProblems(draft(lines: List.filled(51, unplanned(amount: '1')), total: '51')),
          contains(const PurchaseProblem(ProblemKind.tooManyLines)));
    });
  });

  group('the pur_record body', () {
    test('a phone purchase: source workmate, the actual date, the typed total', () {
      final b = purchaseBody(draft(), docs: const {'supplier_invoice_url': 'https://x/u.jpg'});
      expect(b['source'], 'workmate');
      expect(b['purchase_date'], '2026-10-21');
      expect(b['date_time'], '2026-10-21');
      expect(b['receipt_total'], 500);
      expect(b['supplier'], 'ZZ Hardware');
      expect(b['docs'], {'supplier_invoice_url': 'https://x/u.jpg'});
      expect(b['no_receipt_reason'], '');
    });

    test('an unplanned line carries its reason and no request', () {
      final line = (purchaseBody(draft())['lines'] as List).single as Map;
      expect(line['request_line_id'], isNull);
      expect(line['unplanned_reason'], 'Site ran out');
      expect(line['folder_id'], 'f1');
      expect(line['quantity'], 2);
      expect(line['amount'], 500);
      expect(line.containsKey('portion_picks'), isFalse);
    });

    test('a linked line carries its request, the picked portions and the match', () {
      final line = (purchaseBody(draft(lines: [linked(quantity: '12').copyWith(extraReason: 'Spare', extraLocation: 'warehouse')]))['lines']
          as List)
          .single as Map;
      expect(line['request_line_id'], 'l1');
      expect(line['portion_picks'], [
        {'portion_id': 'p1', 'quantity': 10},
      ]);
      expect(line['extra_reason'], 'Spare');
      expect(line['extra_location'], 'warehouse');
      expect(line['substitute'], isFalse);
      expect(line.containsKey('unplanned_reason'), isFalse);
    });

    test('a warehouse line has no project', () {
      final line = (purchaseBody(draft(lines: [unplanned().copyWith(destination: 'warehouse')]))['lines'] as List).single as Map;
      expect(line['destination'], 'warehouse');
      expect(line['folder_id'], isNull);
    });

    test('an adjusted split goes by line number; a default one is left to the server', () {
      final two = [unplanned(amount: '300'), unplanned(amount: '200')];
      final b = purchaseBody(draft(lines: two, total: '600', charges: [
        const DraftCharge(kind: 'delivery_fee', amount: '50', shares: ['30', '20']),
        const DraftCharge(kind: 'delivery_fee', amount: '50'),
      ]));
      final charges = b['charges'] as List;
      expect((charges[0] as Map)['shares'], [
        {'line': 1, 'amount': 30},
        {'line': 2, 'amount': 20},
      ]);
      expect((charges[1] as Map).containsKey('shares'), isFalse);
    });

    test('No receipt keeps its reason; a different unit\'s note goes into the notes (Q8, Q10)', () {
      final b = purchaseBody(draft(
        photos: const {},
        noReceipt: true,
        noReceiptReason: 'Sari-sari store',
        lines: [linked(unit: 'box').copyWith(unitNote: '1 box = 12 bags')],
      ));
      expect(b['no_receipt_reason'], 'Sari-sari store');
      expect(b['notes'], 'Line 1 (different unit): 1 box = 12 bags');
    });

    test('a draft survives being saved and read back', () {
      final d = draft(lines: [linked(quantity: '12').copyWith(match: LineMatch.otherWords, extraLocation: 'project')]);
      final back = PurchaseDraft.fromJson(d.toJson());
      expect(back.toJson(), d.toJson());
      expect(back.lines.single.match, LineMatch.otherWords);
      expect(back.lines.single.picks.single.still, 10);
    });
  });
  group('ticking an item already in an unsent draft (pilot F3)', () {
    const cementLine = DraftPurchaseLine(key: 'k1', itemName: 'Cement', requestLineId: 'l1', quantity: '4');
    const sandLine = DraftPurchaseLine(key: 'k2', itemName: 'Sand', requestLineId: 'l2', quantity: '1');
    const looseLine = DraftPurchaseLine(key: 'k3', itemName: 'Rope', quantity: '1');
    PurchaseDraft d(String id, List<DraftPurchaseLine> lines, {List<DraftCharge> charges = const []}) =>
        PurchaseDraft(id: id, createdAt: DateTime.utc(2026, 10, 21, 2), purchaseDate: '2026-10-21', lines: lines, charges: charges);

    test('finds the newest draft that has one of the ticked request items', () {
      final newer = d('new', [cementLine]);
      final older = d('old', [cementLine, sandLine]);
      expect(draftWithSameItems([newer, older], [cementLine])?.id, 'new');
      expect(draftWithSameItems([newer, older], [sandLine])?.id, 'old');
    });

    test('no shared request item, or no request at all: none', () {
      expect(draftWithSameItems([d('a', [sandLine])], [cementLine]), isNull);
      expect(draftWithSameItems([d('a', [looseLine])], [looseLine]), isNull, reason: 'unplanned lines are never matched');
      expect(draftWithSameItems(const [], [cementLine]), isNull);
    });

    test('continuing adds only the ticked items the draft does not have, and redoes an adjusted split', () {
      final old = d('old', [cementLine], charges: const [DraftCharge(kind: 'delivery_fee', amount: '50', shares: ['50'])]);
      final merged = withPickedLines(old, [cementLine, sandLine]);
      expect([for (final l in merged.lines) l.requestLineId], ['l1', 'l2']);
      expect(merged.id, 'old');
      expect(merged.charges.single.shares, isNull);
      expect(identical(withPickedLines(old, [cementLine]), old), isTrue, reason: 'nothing new: the draft as it was');
    });
  });
}
