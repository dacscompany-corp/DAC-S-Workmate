import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:workmate/purchasing/domain/purchase_draft.dart';
import 'package:workmate/purchasing/purchasing_services.dart';
import 'package:workmate/purchasing/record/record_controller.dart';
import 'package:workmate/purchasing/record/record_screen.dart';
import 'package:workmate/ui/theme.dart';
import 'package:workmate/ui/wm_sheet.dart';

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

  // What openRecord returned once the sheet closed (null while it is still open).
  bool? closedWith;

  Future<bool?> open(WidgetTester tester, {List<DraftPurchaseLine>? lines, PurchaseDraft? draft, bool tall = true}) async {
    if (tall) useTallPhone(tester);
    bool? result;
    closedWith = null;
    await tester.pumpWidget(MaterialApp(
      theme: workMateTheme(),
      home: Builder(
        builder: (context) => Scaffold(
          body: TextButton(
            onPressed: () async => closedWith = result = await openRecord(context, services, lines: lines, draft: draft),
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
  // A target already built (above the screen as well as below) is brought into view directly.
  Future<void> scrollTo(WidgetTester tester, Finder f, {double step = 200}) async {
    if (f.evaluate().isEmpty) {
      final list = find.descendant(of: find.byKey(const Key('record-form')), matching: find.byType(Scrollable)).first;
      try {
        await tester.scrollUntilVisible(f, step, scrollable: list);
      } on StateError {
        await tester.scrollUntilVisible(f, -step, scrollable: list); // it is above
      }
    }
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
    await tester.pumpAndSettle(); // the focused field has scrolled into view inside the sheet
    await tester.ensureVisible(find.byKey(const Key('place-1')));
    await tester.pumpAndSettle();
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

  group('Record purchase is a swipe-down sheet (redesign 6b)', () {
    PurchaseDraft complete() => api
        .newDraft(lines: const [DraftPurchaseLine(key: 'k', itemName: 'ZZ cement', quantity: '1', amount: '1250', folderId: 'f1', unplannedReason: 'ZZ')])
        .copyWith(receiptTotal: '1250', photos: {'supplier_invoice_url': '/p/r.jpg'}, supplierId: 's1', supplierName: 'ZZ Hardware');

    testWidgets('it is a sheet: a close button and no app bar', (tester) async {
      await open(tester);
      expect(find.byKey(const Key('wm-sheet-close')), findsOneWidget);
      expect(find.byType(AppBar), findsNothing);
      expect(find.byKey(const Key('record-form')), findsOneWidget);
      expect(find.text('Itala ang binili'), findsWidgets, reason: 'the Tagalog subtitle');
    });

    testWidgets('the section titles run ITEMS, SUPPLIER AND DATE, DELIVERY, RECEIPT, NOTES, PAID NOW?', (tester) async {
      await open(tester);
      double top(String t) => tester.getTopLeft(find.text(t)).dy;
      // Everything is laid out lazily: list the titles top to bottom as they come.
      final titles = ['ITEMS (1)', 'SUPPLIER AND DATE', 'DELIVERY FEES AND DISCOUNTS', 'RECEIPT', 'NOTES', 'PAID NOW?'];
      final seen = <String, double>{};
      var scrolled = 0.0;
      final list = find.descendant(of: find.byKey(const Key('record-form')), matching: find.byType(Scrollable)).first;
      for (var i = 0; i < 60 && seen.length < titles.length; i++) {
        for (final t in titles) {
          if (find.text(t).evaluate().isNotEmpty) seen[t] = top(t) + scrolled;
        }
        await tester.drag(list, const Offset(0, -150));
        await tester.pumpAndSettle();
        scrolled += 150;
      }
      expect(seen.keys, containsAll(titles));
      for (var i = 1; i < titles.length; i++) {
        expect(seen[titles[i]]!, greaterThan(seen[titles[i - 1]]!), reason: '${titles[i]} sits below ${titles[i - 1]}');
      }
      expect(find.textContaining('1 The purchase'), findsNothing);
      expect(find.text('Receipt total'), findsNothing, reason: 'the numbered headings are gone');
    });

    testWidgets('the bin asks first; Throw away discards and closes with false', (tester) async {
      await open(tester);
      await tester.tap(find.byKey(const Key('record-discard')));
      await tester.pumpAndSettle();
      expect(find.text('Throw this purchase away?'), findsOneWidget);
      await tester.tap(find.text('Keep'));
      await tester.pumpAndSettle();
      expect(find.byKey(const Key('record-form')), findsOneWidget, reason: 'Keep leaves it open');
      expect(api.calls.where((c) => c.startsWith('deleteDraft')), isEmpty);
      await tester.tap(find.byKey(const Key('record-discard')));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Throw away'));
      await tester.pumpAndSettle();
      expect(api.calls.where((c) => c.startsWith('deleteDraft')), hasLength(1));
      expect(find.byKey(const Key('record-form')), findsNothing);
      expect(closedWith, false);
    });

    testWidgets('the bin sits left of the close button', (tester) async {
      await open(tester);
      final bin = tester.getRect(find.byKey(const Key('record-discard')));
      final close = tester.getRect(find.byKey(const Key('wm-sheet-close')));
      expect(bin.right, lessThanOrEqualTo(close.left + 0.01));
    });

    testWidgets('the close button keeps the draft and returns false', (tester) async {
      await open(tester);
      await tester.enterText(find.byKey(const Key('item-1')), 'ZZ wire');
      await tester.pump();
      await tester.tap(find.byKey(const Key('wm-sheet-close')));
      await tester.pumpAndSettle();
      expect(find.byKey(const Key('record-form')), findsNothing);
      expect(closedWith, false);
      expect(api.calls.where((c) => c.startsWith('deleteDraft')), isEmpty, reason: 'the draft stays on the phone');
      expect(api.saved.last.lines.single.itemName, 'ZZ wire');
    });

    testWidgets('dragging the header down closes it and keeps the draft', (tester) async {
      await open(tester);
      await tester.timedDrag(find.byKey(const Key('wm-sheet-handle')), const Offset(0, 200), const Duration(milliseconds: 800));
      await tester.pumpAndSettle();
      expect(find.byKey(const Key('record-form')), findsNothing);
      expect(closedWith, false);
      expect(api.calls.where((c) => c.startsWith('deleteDraft')), isEmpty);
    });

    testWidgets('Record purchase is pinned in the footer and queues the same body; nothing is paid unless chosen', (tester) async {
      await open(tester, draft: complete());
      final send = find.byKey(const Key('record-send'));
      expect(send, findsOneWidget);
      expect(find.ancestor(of: send, matching: find.byType(ListView)), findsNothing, reason: 'not part of the scrolling body');
      expect(find.descendant(of: find.byType(WmSheetFrame), matching: send), findsOneWidget);
      expect(find.descendant(of: send, matching: find.text('Record purchase')), findsOneWidget);
      expect(find.descendant(of: send, matching: find.text('Itala ang binili')), findsOneWidget);
      await tester.tap(send);
      await tester.pumpAndSettle();
      final sent = api.sent.single;
      expect(sent.receiptTotal, '1250');
      expect(sent.supplierId, 's1');
      expect(sent.lines.single.itemName, 'ZZ cement');
      expect(sent.lines.single.folderId, 'f1');
      expect(sent.paidNow, 'none', reason: 'Paid now? is still Not paid yet');
      expect(paidNowPayment(sent), isNull, reason: 'no payment in what is sent');
      expect(closedWith, true);
    });

    testWidgets('a line\'s problem shows inside that line\'s card', (tester) async {
      await open(tester);
      await tester.tap(find.byKey(const Key('record-send')));
      await tester.pumpAndSettle();
      expect(api.sent, isEmpty);
      final problem = find.byKey(const Key('problem-unplannedReasonRequired-1'));
      await scrollTo(tester, problem, step: -200);
      expect(find.descendant(of: find.byKey(const Key('line-1')), matching: problem), findsOneWidget);
    });

    testWidgets('a new item shows no place until the buyer picks one: never Warehouse by accident', (tester) async {
      await open(tester);
      final box = find.byKey(const Key('place-1'));
      await scrollTo(tester, box);
      Finder shown(String label) => find.descendant(of: box, matching: find.text(label));
      expect(shown('Warehouse'), findsNothing, reason: 'nothing is chosen yet');
      expect(shown('Barlin Residence'), findsNothing);
      // The form agrees with the box: it asks for the place.
      await tester.tap(find.byKey(const Key('record-send')));
      await tester.pumpAndSettle();
      await scrollTo(tester, find.byKey(const Key('problem-noProject-1')), step: -200);
      expect(find.byKey(const Key('problem-noProject-1')), findsOneWidget);
      expect(api.sent, isEmpty);
      // Picked: the box says Warehouse, the draft holds it, and the form stops asking.
      await scrollTo(tester, box);
      await tester.tap(box);
      await tester.pumpAndSettle();
      await tester.tap(find.text('Warehouse').last);
      await tester.pumpAndSettle();
      expect(shown('Warehouse'), findsOneWidget);
      expect(api.saved.last.lines.single.destination, 'warehouse');
      expect(find.byKey(const Key('problem-noProject-1')), findsNothing);
    });

    testWidgets('an item already set to the warehouse, or to a project, shows that place', (tester) async {
      await open(tester, lines: const [
        DraftPurchaseLine(key: 'k1', quantity: '1', category: 'Materials', destination: 'warehouse'),
        DraftPurchaseLine(key: 'k2', quantity: '1', category: 'Materials', folderId: 'f1', folderLabel: 'Barlin Residence'),
      ]);
      await scrollTo(tester, find.byKey(const Key('place-1')));
      expect(find.descendant(of: find.byKey(const Key('place-1')), matching: find.text('Warehouse')), findsOneWidget);
      await scrollTo(tester, find.byKey(const Key('place-2')));
      expect(find.descendant(of: find.byKey(const Key('place-2')), matching: find.text('Barlin Residence')), findsOneWidget);
      expect(find.descendant(of: find.byKey(const Key('place-2')), matching: find.text('Warehouse')), findsNothing);
    });

    testWidgets('the item card and a fee card are flat: a border and no shadow', (tester) async {
      await open(tester);
      final item = tester.widget<Card>(find.byKey(const Key('line-1')));
      expect(item.elevation, 0);
      expect((item.shape! as RoundedRectangleBorder).side.color, WmColors.border);
      await scrollTo(tester, find.byKey(const Key('add-fee')));
      await tester.tap(find.byKey(const Key('add-fee')));
      await tester.pumpAndSettle();
      await scrollTo(tester, find.byKey(const Key('charge-1')));
      final fee = tester.widget<Card>(find.byKey(const Key('charge-1')));
      expect(fee.elevation, 0);
      expect((fee.shape! as RoundedRectangleBorder).side.color, WmColors.border);
    });

    testWidgets('a Send that sends nothing says why over the pinned button, in view', (tester) async {
      await open(tester);
      expect(find.byKey(const Key('record-first-problem')), findsNothing, reason: 'nothing before the first Send');
      await tester.tap(find.byKey(const Key('record-send')));
      await tester.pumpAndSettle();
      expect(api.sent, isEmpty);
      final hint = find.byKey(const Key('record-first-problem'));
      expect(hint, findsOneWidget);
      final screen = tester.view.physicalSize / tester.view.devicePixelRatio;
      final r = tester.getRect(hint);
      expect(r.top, greaterThanOrEqualTo(0));
      expect(r.bottom, lessThanOrEqualTo(tester.getRect(find.byKey(const Key('record-send'))).top));
      expect(r.bottom, lessThanOrEqualTo(screen.height));
    });

    testWidgets('text typed in a field survives scrolling it away and back', (tester) async {
      await open(tester);
      await tester.enterText(find.byKey(const Key('item-1')), 'ZZ wire');
      await tester.pump();
      await scrollTo(tester, find.byKey(const Key('paid-now')));
      expect(find.byKey(const Key('item-1')), findsNothing, reason: 'far enough away to be let go');
      await scrollTo(tester, find.byKey(const Key('item-1')), step: -200);
      final typed = tester.widget<EditableText>(find.descendant(of: find.byKey(const Key('item-1')), matching: find.byType(EditableText))).controller.text;
      expect(typed, 'ZZ wire');
    });

    testWidgets('with the keyboard up, the focused Total and Record purchase stay above it', (tester) async {
      await open(tester);
      tester.view.viewInsets = const FakeViewPadding(bottom: 900);
      addTearDown(tester.view.resetViewInsets);
      await tester.pumpAndSettle();
      await scrollTo(tester, find.byKey(const Key('receipt-total')));
      await tester.tap(find.byKey(const Key('receipt-total')));
      await tester.pumpAndSettle();
      final limit = (tester.view.physicalSize.height - 900) / tester.view.devicePixelRatio;
      expect(tester.getBottomLeft(find.byKey(const Key('receipt-total'))).dy, lessThanOrEqualTo(limit));
      expect(tester.getTopLeft(find.byKey(const Key('receipt-total'))).dy, greaterThan(0));
      expect(tester.getBottomLeft(find.byKey(const Key('record-send'))).dy, lessThanOrEqualTo(limit));
    });

    testWidgets('at 320 x 568 with large text nothing overflows', (tester) async {
      tester.view.physicalSize = const Size(320, 568);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.reset);
      tester.platformDispatcher.textScaleFactorTestValue = 1.3;
      addTearDown(tester.platformDispatcher.clearTextScaleFactorTestValue);
      await open(tester, lines: [linked()], tall: false);
      expect(tester.takeException(), isNull);
      await tester.tap(find.byKey(const Key('record-send')));
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull);
      await scrollTo(tester, find.byKey(const Key('add-fee')));
      await tester.tap(find.byKey(const Key('add-fee')));
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull);
    });
  });

  test('openRecord\'s blank purchase has one item to fill', () {
    final c = RecordController(api: api, draft: api.newDraft(lines: [const DraftPurchaseLine(key: 'k', quantity: '1', category: 'Materials')]));
    expect(c.draft.lines.single.category, 'Materials');
  });
}
