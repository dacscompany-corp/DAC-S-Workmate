import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:workmate/purchasing/domain/purchase_draft.dart';
import 'package:workmate/purchasing/purchasing_services.dart';
import 'package:workmate/purchasing/record/record_controller.dart';
import 'package:workmate/purchasing/record/record_screen.dart';
import 'package:workmate/ui/theme.dart';

import '../../attendance/fakes.dart' show useTallPhone;
import '../domain/purchase_draft_test.dart' show linked;
import '../purchasing_api_fake.dart';

void main() {
  late FakePurchasingApi api;
  late PurchasingServices services;
  var shots = 0;

  setUp(() {
    api = FakePurchasingApi();
    shots = 0;
    services = PurchasingServices(
      api: api,
      takePhoto: (_) async => 'shot${++shots}.jpg',
      pickPhoto: (_) async => 'gallery.jpg',
    );
  });

  Future<bool?> open(WidgetTester tester, {List<DraftPurchaseLine>? lines}) async {
    useTallPhone(tester);
    bool? result;
    await tester.pumpWidget(MaterialApp(
      theme: workMateTheme(),
      home: Builder(
        builder: (context) => Scaffold(
          body: TextButton(
            onPressed: () async => result = await openRecord(context, services, lines: lines),
            child: const Text('open'),
          ),
        ),
      ),
    ));
    await tester.tap(find.text('open'));
    await tester.pumpAndSettle();
    return result;
  }

  // The form's own list (every text field has a Scrollable of its own), then
  // all of the widget on screen: scrollUntilVisible stops at its first pixel.
  Future<void> scrollTo(WidgetTester tester, Finder f, {double step = 200}) async {
    await tester.scrollUntilVisible(f, step,
        scrollable: find.descendant(of: find.byKey(const Key('record-form')), matching: find.byType(Scrollable)).first);
    await tester.ensureVisible(f);
    await tester.pumpAndSettle();
  }

  testWidgets('an unplanned purchase, start to finish: item, place, reason, receipt, total (Q7–Q11)', (tester) async {
    await open(tester);
    expect(find.text('Record purchase'), findsWidgets);
    expect(find.text('Itala ang binili'), findsWidgets);
    await tester.enterText(find.byKey(const Key('supplier-name')), 'ZZ Hardware');
    await tester.enterText(find.byKey(const Key('item-1')), 'ZZ wire');
    await tester.enterText(find.byKey(const Key('qty-1')), '2');
    await tester.enterText(find.byKey(const Key('unit-1')), 'roll');
    await tester.enterText(find.byKey(const Key('amount-1')), '500');
    await tester.tap(find.byKey(const Key('place-1')));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Barlin Residence').last);
    await tester.pumpAndSettle();
    await tester.enterText(find.byKey(const Key('unplanned-1')), 'Site ran out');
    await scrollTo(tester, find.byKey(const Key('camera-supplier_invoice_url')));
    await tester.tap(find.byKey(const Key('camera-supplier_invoice_url')));
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('photo-supplier_invoice_url')), findsOneWidget);
    await scrollTo(tester, find.byKey(const Key('receipt-total')));
    await tester.enterText(find.byKey(const Key('receipt-total')), '500');
    await tester.pump();
    expect(find.text('Items + fees − discounts: ₱500.00'), findsOneWidget);
    await scrollTo(tester, find.byKey(const Key('record-send')));
    await tester.tap(find.byKey(const Key('record-send')));
    await tester.pumpAndSettle();
    final sent = api.sent.single;
    expect(sent.lines.single.folderId, 'f1');
    expect(sent.lines.single.unplannedReason, 'Site ran out');
    expect(sent.photos.keys, ['supplier_invoice_url']);
    expect(sent.supplierName, 'ZZ Hardware');
    expect(find.text('open'), findsOneWidget, reason: 'back where it was opened from');
  });

  testWidgets('sending something incomplete names each problem, in both languages, next to its field', (tester) async {
    await open(tester);
    await scrollTo(tester, find.byKey(const Key('record-send')));
    await tester.tap(find.byKey(const Key('record-send')));
    await tester.pumpAndSettle();
    expect(api.sent, isEmpty);
    // The item card grew its own problems above: scroll to the general ones.
    await scrollTo(tester, find.byKey(const Key('problem-badTotal-0')));
    expect(find.text('Add a receipt photo, or tap No receipt and say why.'), findsOneWidget);
    expect(find.text('Ilagay ang total na nakasulat sa resibo.'), findsOneWidget);
    await scrollTo(tester, find.byKey(const Key('problem-unplannedReasonRequired-1')), step: -200);
    expect(find.byKey(const Key('problem-unplannedReasonRequired-1')), findsOneWidget);
  });

  testWidgets('a line from the shopping list asks "Is this the same item?" (Q10)', (tester) async {
    await open(tester, lines: [linked()]);
    expect(find.text('For the request: Cement · Barlin Residence'), findsOneWidget);
    expect(find.text('Is this the same item?'), findsOneWidget);
    expect(find.text('Ito ba ang parehong item?'), findsOneWidget);
    expect(find.byKey(const Key('place-1')), findsNothing, reason: 'a request line goes where its request is');
    await tester.tap(find.text('Substitute'));
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('substitute-1')), findsOneWidget);
  });

  testWidgets('a different unit asks how much it covers; an extra asks why and where (Q10, Q11)', (tester) async {
    await open(tester, lines: [linked()]);
    await tester.enterText(find.byKey(const Key('unit-1')), 'box');
    await tester.pump();
    expect(find.byKey(const Key('unit-note-1')), findsOneWidget);
    await tester.enterText(find.byKey(const Key('unit-1')), 'bag');
    await tester.enterText(find.byKey(const Key('qty-1')), '12');
    await tester.pump();
    expect(find.byKey(const Key('unit-note-1')), findsNothing);
    expect(find.text('2 bag more than still needed: an extra.'), findsOneWidget);
    expect(find.byKey(const Key('extra-1')), findsOneWidget);
    await scrollTo(tester, find.text('To the warehouse'));
    await tester.tap(find.text('To the warehouse'));
    await tester.pump();
    expect(api.saved.last.lines.single.extraLocation, 'warehouse');
  });

  testWidgets('No receipt asks why (Q8)', (tester) async {
    await open(tester);
    await scrollTo(tester, find.byKey(const Key('no-receipt')));
    await tester.tap(find.byKey(const Key('no-receipt')));
    await tester.pump();
    expect(find.byKey(const Key('no-receipt-reason')), findsOneWidget);
    expect(find.byKey(const Key('camera-supplier_invoice_url')), findsNothing);
  });

  testWidgets('a photo from the gallery fills a slot (Q8)', (tester) async {
    await open(tester);
    await scrollTo(tester, find.byKey(const Key('gallery-payment_receipt_url')));
    await tester.tap(find.byKey(const Key('gallery-payment_receipt_url')));
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('photo-payment_receipt_url')), findsOneWidget);
  });

  testWidgets('a delivery fee joins the total; its split can be adjusted per item (Q9)', (tester) async {
    await open(tester);
    await tester.enterText(find.byKey(const Key('amount-1')), '500');
    await scrollTo(tester, find.byKey(const Key('add-fee')));
    await tester.tap(find.byKey(const Key('add-fee')));
    await tester.pumpAndSettle();
    await tester.enterText(find.byKey(const Key('charge-amount-1')), '50');
    await tester.pump();
    await scrollTo(tester, find.byKey(const Key('computed-total')));
    expect(find.text('Items + fees − discounts: ₱550.00'), findsOneWidget);
    await scrollTo(tester, find.byKey(const Key('adjust-1')));
    await tester.tap(find.byKey(const Key('adjust-1')));
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('share-1-1')), findsOneWidget);
  });

  test('openRecord\'s blank purchase has one item to fill', () {
    final c = RecordController(api: api, draft: api.newDraft(lines: [const DraftPurchaseLine(key: 'k', quantity: '1', category: 'Materials')]));
    expect(c.draft.lines.single.category, 'Materials');
  });
}
