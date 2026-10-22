import 'package:flutter_test/flutter_test.dart';
import 'package:workmate/purchasing/domain/purchase_draft.dart';
import 'package:workmate/purchasing/record/record_controller.dart';

import '../domain/purchase_draft_test.dart' show unplanned;
import '../purchasing_api_fake.dart';
import '../purchasing_fakes.dart';

void main() {
  late FakePurchasingApi api;
  late RecordController c;

  setUp(() async {
    api = FakePurchasingApi();
    c = RecordController(api: api, draft: api.newDraft(lines: [unplanned(amount: '300')]));
    await c.load();
  });

  test('every change is saved on the phone at once (Q7)', () {
    c.setTotal('300');
    c.setNotes('Rush');
    expect(api.saved.map((d) => d.notes), ['', 'Rush']);
    expect(api.saved.last.receiptTotal, '300');
  });

  test('places: every open project and job, then the warehouse (Q11)', () {
    expect(c.places.map((p) => p.label), ['Barlin Residence', 'Barlin Residence · AW-02 Fence', 'Warehouse']);
    c.setPlace(0, c.places[1]);
    expect(c.draft.lines.single.folderId, 'f9');
    expect(c.draft.lines.single.destination, 'project');
    c.setPlace(0, c.places.last);
    expect(c.draft.lines.single.destination, 'warehouse');
    expect(c.draft.lines.single.folderId, isNull);
  });

  test('a supplier from the list, or typed', () {
    c.setSupplier(zzHardware);
    expect(c.draft.supplierId, 's1');
    expect(c.draft.supplierName, 'ZZ Hardware · Malolos');
    c.setSupplierName('Sari-sari');
    expect(c.draft.supplierId, isNull);
    expect(c.draft.supplierName, 'Sari-sari');
  });

  test('adjusting a split starts from the server\'s default one; a new item resets it (Q9)', () {
    c.addLine();
    c.updateLine(1, c.draft.lines[1].copyWith(amount: '100'));
    c.addCharge('delivery_fee');
    c.updateCharge(0, c.draft.charges[0].copyWith(amount: '40'));
    c.adjustSplit(0, true);
    expect(c.draft.charges[0].shares, ['30.00', '10.00']);
    c.addLine();
    expect(c.draft.charges[0].shares, isNull);
    c.adjustSplit(0, false);
    expect(c.draft.charges[0].shares, isNull);
  });

  test('a new photo replaces the old one in its slot, and the old file goes (Q8)', () async {
    await c.addPhoto('supplier_invoice_url', 'a.jpg');
    await c.addPhoto('supplier_invoice_url', 'b.jpg');
    expect(c.draft.photos, {'supplier_invoice_url': '/kept/b.jpg'});
    expect(api.calls, contains('discardPhoto:/kept/a.jpg'));
    await c.removePhoto('supplier_invoice_url');
    expect(c.draft.photos, isEmpty);
  });

  test('a photo turns "No receipt" off', () async {
    c.setNoReceipt(true);
    await c.addPhoto('po_image_url', 'a.jpg');
    expect(c.draft.noReceipt, isFalse);
  });

  test('problems show only after trying to send; a complete purchase is queued', () async {
    expect(c.problems, isEmpty);
    expect(await c.send(), isFalse);
    expect(c.problems.map((p) => p.kind), containsAll([ProblemKind.noReceipt, ProblemKind.badTotal]));
    await c.addPhoto('supplier_invoice_url', 'a.jpg');
    c.setTotal('300');
    expect(await c.send(), isTrue);
    expect(api.sent.single.id, c.draft.id);
  });

  test('a phone failure while queueing is said in both languages', () async {
    await c.addPhoto('supplier_invoice_url', 'a.jpg');
    c.setTotal('300');
    api.error = Exception('disk full');
    expect(await c.send(), isFalse);
    expect(c.notice!.english, 'Something went wrong. Try again.');
  });

  test('throwing away deletes the draft', () async {
    await c.discard();
    expect(api.calls.last, startsWith('deleteDraft:'));
  });

  test('the computed total is shown as typed amounts add up', () {
    c.addCharge('discount');
    c.updateCharge(0, c.draft.charges[0].copyWith(amount: '50'));
    expect(c.draft.computedTotal, 250);
  });
}
