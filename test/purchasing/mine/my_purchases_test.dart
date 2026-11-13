import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:workmate/purchasing/data/purchasing_api.dart';
import 'package:workmate/purchasing/domain/pur_failure.dart';
import 'package:workmate/purchasing/domain/pur_models.dart';
import 'package:workmate/purchasing/domain/purchase_draft.dart';
import 'package:workmate/purchasing/mine/my_purchases_controller.dart';
import 'package:workmate/purchasing/mine/my_purchases_screen.dart';
import 'package:workmate/purchasing/mine/purchase_detail_screen.dart';
import 'package:workmate/purchasing/purchasing_services.dart';
import 'package:workmate/ui/theme.dart';

import '../../attendance/fakes.dart' show useTallPhone;
import '../domain/correction_test.dart' show stored;
import '../purchasing_api_fake.dart';
import '../purchasing_fakes.dart';

Widget wrap(Widget w) => MaterialApp(theme: workMateTheme(), home: Scaffold(body: w));

PurchaseDraft draft(String id, {String supplier = 'ZZ Hardware', String total = '500'}) =>
    PurchaseDraft(id: id, createdAt: wednesday, purchaseDate: '2026-10-21', supplierName: supplier, receiptTotal: total);

void main() {
  late FakePurchasingApi api;
  late MyPurchasesController c;

  setUp(() {
    api = FakePurchasingApi();
    api.mine = MyPurchasesView(
      queued: [
        QueuedPurchase(draft: draft('q1'), state: QueuedState.waiting),
        QueuedPurchase(draft: draft('q2', supplier: 'Sari-sari'), state: QueuedState.needsAttention, failure: PurFailure.lineClosed),
      ],
      purchases: [
        MyPurchase.fromJson(const {'id': 'pu1', 'status': 'recorded', 'supplier': 'ZZ Hardware', 'receipt_total': 440, 'purchase_date': '2026-10-20',
          'projects': ['Barlin Residence'], 'pending_change': true, 'unit_check': true}),
        MyPurchase.fromJson(const {'id': 'pu2', 'status': 'void', 'supplier': 'Wilcon', 'receipt_total': 90, 'purchase_date': '2026-10-19',
          'projects': [], 'warehouse': true, 'no_receipt_reason': 'None given'}),
      ],
      fetchedAt: wednesday,
    );
    api.draftList = [draft('d1', supplier: '')];
    c = MyPurchasesController(api: api);
  });

  test('drafts, what waits on the phone, then the server\'s list; needing attention is counted', () async {
    await c.refresh();
    expect(c.drafts.single.id, 'd1');
    expect(c.view.queued.length, 2);
    expect(c.attention, 1);
  });

  test('a refused purchase goes back to editing, or is thrown away', () async {
    await c.refresh();
    final back = await c.edit(c.view.queued[1]);
    expect(back!.id, 'q2');
    await c.throwAway(c.view.queued[1]);
    expect(api.calls, containsAll(['returnToDrafts:q2', 'discardRefused:q2']));
  });

  testWidgets('the list: not sent yet (with why, in both languages), drafts, recorded with its status (Q7, Q12)', (tester) async {
    useTallPhone(tester);
    PurchaseDraft? opened;
    MyPurchase? shown;
    await c.refresh();
    await tester.pumpWidget(wrap(MyPurchasesScreen(controller: c, onOpenDraft: (d) => opened = d, onOpenPurchase: (p) => shown = p)));
    expect(find.text('Waiting to send'), findsOneWidget);
    expect(find.text('Hinihintay maipadala'), findsOneWidget);
    expect(find.text('Needs attention'), findsOneWidget);
    expect(find.text(purFailureCopy(PurFailure.lineClosed).english), findsOneWidget);
    expect(find.text(purFailureCopy(PurFailure.lineClosed).tagalog), findsOneWidget);
    await tester.tap(find.byKey(const Key('fix-q2')));
    await tester.pumpAndSettle();
    expect(opened!.id, 'q2');
    await tester.scrollUntilVisible(find.byKey(const Key('purchase-pu2')), 200);
    expect(find.text('Waiting for the owner'), findsOneWidget);
    expect(find.text('Needs office check'), findsOneWidget);
    expect(find.text('Voided'), findsOneWidget);
    expect(find.text('No receipt'), findsOneWidget);
    expect(find.textContaining('Warehouse'), findsOneWidget);
    await tester.tap(find.byKey(const Key('purchase-pu1')));
    expect(shown!.id, 'pu1');
  });

  group('the row cards (Phase 6a)', () {
    late PurchasingServices services;
    MyPurchase? shown;
    PurchaseDraft? opened;

    MyPurchase paid() => MyPurchase.fromJson(const {
          'id': 'pu7', 'status': 'recorded', 'supplier': 'ZZ Hardware', 'supplier_id': 's1', 'receipt_total': 1250.5, 'purchase_date': '2026-10-20',
          'projects': ['Barlin Residence'], 'unit_check': true,
          'pay': {'state': 'partial', 'tracked': true, 'due': 1250.5, 'paid': 250.5, 'balance': 1000},
        });

    Future<void> pump(WidgetTester tester, {bool withServices = true, Size? size, double scale = 1}) async {
      shown = null;
      opened = null;
      services = PurchasingServices(api: api, takePhoto: (_) async => 'shot.jpg', pickPhoto: (_) async => 'gallery.jpg');
      if (size != null) {
        tester.view.physicalSize = size;
        tester.view.devicePixelRatio = 1;
        addTearDown(tester.view.reset);
      } else {
        useTallPhone(tester);
      }
      await c.refresh();
      await tester.pumpWidget(MaterialApp(
        theme: workMateTheme(),
        builder: (context, child) => MediaQuery(data: MediaQuery.of(context).copyWith(textScaler: TextScaler.linear(scale)), child: child!),
        home: Scaffold(
          body: MyPurchasesScreen(
              controller: c, onOpenDraft: (d) => opened = d, onOpenPurchase: (p) => shown = p, services: withServices ? services : null),
        ),
      ));
      await tester.pump();
    }

    testWidgets('a recorded row: supplier, date line, total, flags, pay line, a chevron; the card opens the purchase', (tester) async {
      api.mine = MyPurchasesView(purchases: [paid()], fetchedAt: wednesday);
      await pump(tester);
      final card = find.byKey(const Key('purchase-pu7'));
      expect(find.descendant(of: card, matching: find.text('ZZ Hardware')), findsOneWidget);
      expect(find.descendant(of: card, matching: find.text('2026-10-20 · Barlin Residence')), findsOneWidget);
      expect(find.descendant(of: card, matching: find.text('₱1,250.50')), findsOneWidget);
      expect(find.descendant(of: card, matching: find.text('Needs office check')), findsOneWidget);
      expect(find.descendant(of: card, matching: find.byKey(const Key('pay-line-pu7'))), findsOneWidget);
      expect(find.descendant(of: card, matching: find.byKey(const Key('pay-pu7'))), findsOneWidget);
      expect(find.descendant(of: card, matching: find.byIcon(Icons.chevron_right)), findsOneWidget);
      expect(find.descendant(of: card, matching: find.text('₱1,000.00 left')), findsOneWidget);
      await tester.tap(find.descendant(of: card, matching: find.text('ZZ Hardware')));
      expect(shown!.id, 'pu7');
    });

    testWidgets('Record payment does not also open the purchase', (tester) async {
      api.mine = MyPurchasesView(purchases: [paid()], fetchedAt: wednesday);
      await pump(tester);
      await tester.ensureVisible(find.byKey(const Key('pay-pu7')));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const Key('pay-pu7')));
      await tester.pumpAndSettle();
      expect(shown, isNull);
    });

    testWidgets('a needs-attention purchase keeps Fix and Throw away and both languages of its reason', (tester) async {
      await pump(tester);
      final card = find.byKey(const Key('queued-q2'));
      expect(find.descendant(of: card, matching: find.byKey(const Key('fix-q2'))), findsOneWidget);
      expect(find.descendant(of: card, matching: find.byKey(const Key('throw-q2'))), findsOneWidget);
      expect(find.descendant(of: card, matching: find.text(purFailureCopy(PurFailure.lineClosed).english)), findsOneWidget);
      expect(find.descendant(of: card, matching: find.text(purFailureCopy(PurFailure.lineClosed).tagalog)), findsOneWidget);
      expect(find.descendant(of: card, matching: find.text('Needs attention')), findsOneWidget);
      expect(find.descendant(of: card, matching: find.text('Kailangang ayusin')), findsOneWidget);
    });

    testWidgets('a draft row opens the draft and keeps its delete button, which does not open it', (tester) async {
      await pump(tester);
      final card = find.byKey(const Key('draft-d1'));
      expect(find.descendant(of: card, matching: find.text('Purchase on 2026-10-21')), findsOneWidget);
      expect(find.descendant(of: card, matching: find.text('0 items · not sent')), findsOneWidget);
      expect(find.descendant(of: card, matching: find.byKey(const Key('delete-draft-d1'))), findsOneWidget);
      await tester.ensureVisible(find.byKey(const Key('delete-draft-d1')));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const Key('delete-draft-d1')));
      await tester.pumpAndSettle();
      expect(opened, isNull);
      expect(api.calls, contains('deleteDraft:d1'));
    });

    testWidgets('a draft row opens the draft when tapped', (tester) async {
      await pump(tester);
      await tester.ensureVisible(find.byKey(const Key('draft-d1')));
      await tester.pumpAndSettle();
      await tester.tap(find.descendant(of: find.byKey(const Key('draft-d1')), matching: find.text('Purchase on 2026-10-21')));
      expect(opened!.id, 'd1');
    });

    testWidgets('the group labels show only for a group with rows; Recorded always', (tester) async {
      api.mine = const MyPurchasesView(fetchedAt: null);
      api.draftList = const [];
      await pump(tester);
      expect(find.text('NOT SENT YET'), findsNothing);
      expect(find.text('DRAFTS'), findsNothing);
      expect(find.text('RECORDED'), findsOneWidget);
      expect(find.text(' · Naitala na'), findsOneWidget);
    });

    testWidgets('all three group labels show when each group has rows', (tester) async {
      await pump(tester);
      expect(find.text('NOT SENT YET'), findsOneWidget);
      expect(find.text('DRAFTS'), findsOneWidget);
      expect(find.text('RECORDED'), findsOneWidget);
    });

    testWidgets('320 x 568 with large text raises no exception, a long supplier keeps the amount in place', (tester) async {
      api.mine = MyPurchasesView(
        queued: [QueuedPurchase(draft: draft('q9', supplier: 'A Very Long Supplier Name Trading and Construction Supplies Incorporated'), state: QueuedState.waiting)],
        purchases: [
          MyPurchase.fromJson(const {
            'id': 'pu8', 'status': 'recorded', 'supplier': 'A Very Long Supplier Name Trading and Construction Supplies Incorporated',
            'supplier_id': 's1', 'receipt_total': 1234567.89, 'purchase_date': '2026-10-20', 'projects': ['Barlin Residence', 'Another Long Project Name'],
            'pending_change': true, 'unit_check': true, 'no_receipt_reason': 'x', 'unplanned': true, 'extra': true,
            'pay': {'state': 'partial', 'tracked': true, 'due': 1234567.89, 'paid': 250.5, 'balance': 1234317.39},
          }),
        ],
        fetchedAt: wednesday,
      );
      await pump(tester, size: const Size(320, 568), scale: 1.3);
      await tester.scrollUntilVisible(find.byKey(const Key('purchase-pu8')), 200);
      expect(tester.takeException(), isNull);
      expect(find.text('₱1,234,567.89'), findsWidgets);
    });
  });

  group('one purchase', () {
    late PurchasingServices services;
    setUp(() {
      api.detail = stored;
      services = PurchasingServices(api: api, takePhoto: (_) async => 'shot.jpg', pickPhoto: (_) async => 'gallery.jpg');
    });

    Future<void> openDetail(WidgetTester tester) async {
      useTallPhone(tester);
      await tester.pumpWidget(MaterialApp(
        theme: workMateTheme(),
        home: Builder(
          builder: (context) => Scaffold(
            body: TextButton(
              onPressed: () => Navigator.of(context).push(MaterialPageRoute<bool>(builder: (_) => PurchaseDetailScreen(purchaseId: 'pu1', services: services))),
              child: const Text('open'),
            ),
          ),
        ),
      ));
      await tester.tap(find.text('open'));
      await tester.pumpAndSettle();
    }

    Future<void> scrollTo(WidgetTester tester, Finder f) async {
      await tester.scrollUntilVisible(f, 200,
          scrollable: find.descendant(of: find.byKey(const Key('correct-form')), matching: find.byType(Scrollable)).first);
      await tester.ensureVisible(f);
      await tester.pumpAndSettle();
    }

    testWidgets('lines, fees, receipts; Correct for my recorded purchase; never a void (Q12, Q13)', (tester) async {
      await openDetail(tester);
      expect(find.text('Cement'), findsOneWidget);
      expect(find.text('Delivery fee'), findsOneWidget);
      expect(find.byKey(const Key('receipt-supplier_invoice_url')), findsOneWidget);
      expect(find.byKey(const Key('correct')), findsOneWidget);
      expect(find.textContaining('Void'), findsNothing);
      expect(find.text('A purchase is voided on Dacs Web only.'), findsOneWidget);
    });

    testWidgets('waiting for the owner: no second change from the phone', (tester) async {
      api.detail = PurchaseDetail.fromJson({
        ...{'id': 'pu1', 'status': 'recorded', 'lines': const [], 'charges': const []},
        'change_requests': const [{'kind': 'correct', 'status': 'pending', 'reason': 'Price'}],
      });
      await openDetail(tester);
      expect(find.byKey(const Key('waiting-owner')), findsOneWidget);
      expect(find.byKey(const Key('correct')), findsNothing);
    });

    testWidgets('a correction is saved with its reason and new photo (Q13)', (tester) async {
      await openDetail(tester);
      await tester.tap(find.byKey(const Key('correct')));
      await tester.pumpAndSettle();
      await tester.enterText(find.byKey(const Key('correct-qty-1')), '12');
      await scrollTo(tester, find.byKey(const Key('correct-camera-payment_receipt_url')));
      await tester.tap(find.byKey(const Key('correct-camera-payment_receipt_url')));
      await tester.pumpAndSettle();
      await scrollTo(tester, find.byKey(const Key('correct-reason')));
      await tester.enterText(find.byKey(const Key('correct-reason')), 'Counted again');
      await scrollTo(tester, find.byKey(const Key('correct-save')));
      await tester.tap(find.byKey(const Key('correct-save')));
      await tester.pumpAndSettle();
      expect(api.calls, contains('correct:pu1:Counted again:payment_receipt_url'));
      expect(((api.bodies.single['lines'] as List).first as Map)['quantity'], 12);
      expect(find.text('Corrected. · Naitama na.'), findsOneWidget);
    });

    testWidgets('only the owner may: it is offered to the owner, the same change (Q13)', (tester) async {
      api.correctionOutcome = CorrectionOutcome.needsOwner;
      await openDetail(tester);
      await tester.tap(find.byKey(const Key('correct')));
      await tester.pumpAndSettle();
      await tester.enterText(find.byKey(const Key('correct-amount-1')), '320');
      await scrollTo(tester, find.byKey(const Key('correct-total')));
      await tester.enterText(find.byKey(const Key('correct-total')), '460');
      await scrollTo(tester, find.byKey(const Key('correct-reason')));
      await tester.enterText(find.byKey(const Key('correct-reason')), 'Price');
      await scrollTo(tester, find.byKey(const Key('correct-save')));
      await tester.tap(find.byKey(const Key('correct-save')));
      await tester.pumpAndSettle();
      expect(find.text('Send to the owner?'), findsOneWidget);
      await tester.tap(find.byKey(const Key('send-owner')));
      await tester.pumpAndSettle();
      // Then the purchase is read again (now Waiting for the owner).
      expect(api.calls.where((x) => x.startsWith('owner:')), ['owner:pu1:Price']);
      expect(api.bodies.last, same(api.bodies.first));
      expect(find.text('Sent to the owner. · Naipadala sa may-ari.'), findsOneWidget);
    });

    testWidgets('no reason: the form says so and sends nothing', (tester) async {
      await openDetail(tester);
      await tester.tap(find.byKey(const Key('correct')));
      await tester.pumpAndSettle();
      await scrollTo(tester, find.byKey(const Key('correct-save')));
      await tester.tap(find.byKey(const Key('correct-save')));
      await tester.pumpAndSettle();
      expect(find.byKey(const Key('cproblem-reasonRequired-0')), findsOneWidget);
      expect(api.calls.where((x) => x.startsWith('correct:')), isEmpty);
    });
  });
}
