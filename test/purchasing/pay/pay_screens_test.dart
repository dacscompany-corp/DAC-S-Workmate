import 'dart:async';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:workmate/purchasing/data/purchasing_api.dart';
import 'package:workmate/purchasing/domain/pay_models.dart';
import 'package:workmate/purchasing/domain/pur_failure.dart';
import 'package:workmate/purchasing/domain/pur_models.dart';
import 'package:workmate/purchasing/domain/pur_op.dart';
import 'package:workmate/purchasing/domain/purchase_draft.dart';
import 'package:workmate/purchasing/mine/my_purchases_controller.dart';
import 'package:workmate/purchasing/mine/my_purchases_screen.dart';
import 'package:workmate/purchasing/mine/purchase_detail_screen.dart';
import 'package:workmate/purchasing/pay/my_cash_screen.dart';
import 'package:workmate/purchasing/pay/record_payment_screen.dart';
import 'package:workmate/purchasing/pay/report_return_screen.dart';
import 'package:workmate/purchasing/purchasing_services.dart';
import 'package:workmate/purchasing/record/record_controller.dart';
import 'package:workmate/purchasing/record/record_screen.dart';
import 'package:workmate/purchasing/ui/purchasing_copy.dart' show sentLabel;
import 'package:workmate/ui/theme.dart';

import '../../attendance/fakes.dart' show useTallPhone;
import '../purchasing_api_fake.dart';

/// 2A-4b on the phone's screens: "Paid now?" (Q3), Record payment (Q6),
/// My purchases' payment line and the "My cash" card (Q23), My cash
/// (Q14, Q17), a purchase's Payments with Void (Q7).
void main() {
  late FakePurchasingApi api;
  late PurchasingServices services;
  var shots = 0;

  setUp(() {
    api = FakePurchasingApi();
    shots = 0;
    services = PurchasingServices(api: api, takePhoto: (_) async => 'shot${++shots}.jpg', pickPhoto: (_) async => 'gallery.jpg');
  });

  Future<void> show(WidgetTester tester, Widget screen) async {
    useTallPhone(tester);
    await tester.pumpWidget(MaterialApp(theme: workMateTheme(), home: screen));
    await tester.pumpAndSettle();
  }

  /// Scrolls the screen's list to [f], down or up.
  Future<void> reach(WidgetTester tester, Finder f, {required Key list}) async {
    if (f.evaluate().isEmpty) {
      final scroll = find.descendant(of: find.byKey(list), matching: find.byType(Scrollable)).first;
      try {
        await tester.scrollUntilVisible(f, 200, scrollable: scroll);
      } on StateError {
        await tester.scrollUntilVisible(f, -200, scrollable: scroll);
      }
    }
    await tester.ensureVisible(f);
    await tester.pumpAndSettle();
  }

  Future<void> choose(WidgetTester tester, Key dropdown, String item, {required Key list}) async {
    await reach(tester, find.byKey(dropdown), list: list);
    await tester.tap(find.byKey(dropdown));
    await tester.pumpAndSettle();
    await tester.tap(find.text(item).last);
    await tester.pumpAndSettle();
  }

  group('"Paid now?" on Record purchase (Q3)', () {
    const form = Key('record-form');
    PurchaseDraft draft({String total = '1250'}) => api
        .newDraft(lines: const [DraftPurchaseLine(key: 'k', itemName: 'ZZ cement', quantity: '1', amount: '1250', folderId: 'f1', unplannedReason: 'ZZ')])
        .copyWith(receiptTotal: total, photos: {'supplier_invoice_url': '/p/r.jpg'}, supplierId: 's1', supplierName: 'ZZ Hardware');

    Future<RecordController> open(WidgetTester tester, {PurchaseDraft? d}) async {
      final c = RecordController(api: api, draft: d ?? draft());
      await c.load();
      await show(tester, RecordScreen(controller: c, services: services));
      return c;
    }

    testWidgets('Not paid yet by default: nothing more is asked, nothing is paid', (tester) async {
      final c = await open(tester);
      await reach(tester, find.byKey(const Key('paid-now')), list: form);
      expect(find.text('Not paid yet · Hindi pa bayad'), findsOneWidget);
      expect(find.byKey(const Key('paid-method')), findsNothing);
      expect(paidNowPayment(c.draft), isNull);
    });

    testWidgets('Paid in full from petty cash: offered first to a staff buyer; sent with the purchase', (tester) async {
      final c = await open(tester);
      await choose(tester, const Key('paid-now'), 'Paid in full · Bayad nang buo', list: form);
      expect(c.draft.paidFrom, 'petty_cash');
      expect(find.byKey(const Key('paid-amount')), findsNothing, reason: 'in full: the receipt total');
      await reach(tester, find.byKey(const Key('record-send')), list: form);
      await tester.tap(find.byKey(const Key('record-send')));
      await tester.pumpAndSettle();
      expect(paymentBody(paidNowPayment(api.sent.single)!)['amount'], '1250.00');
    });

    testWidgets('Q16: paying more petty cash than held warns, never blocks', (tester) async {
      api.cash = const MyCashView(cash: MyCash(holder: true, recorded: 1000, held: 1000));
      final c = await open(tester);
      await choose(tester, const Key('paid-now'), 'Paid in full · Bayad nang buo', list: form);
      await reach(tester, find.byKey(const Key('paid-overspend')), list: form);
      expect(find.textContaining('You hold ₱1,000.00 of petty cash on record. This payment is ₱1,250.00.'), findsOneWidget);
      expect(c.overspend, (held: 1000.0, amount: 1250.0));
      await reach(tester, find.byKey(const Key('record-send')), list: form);
      await tester.tap(find.byKey(const Key('record-send')));
      await tester.pumpAndSettle();
      expect(api.sent, hasLength(1));
    });

    testWidgets('Paid part: the amount must be less than the total', (tester) async {
      final c = await open(tester);
      await choose(tester, const Key('paid-now'), 'Paid part (deposit) · Bahagyang bayad (deposito)', list: form);
      await reach(tester, find.byKey(const Key('paid-amount')), list: form);
      await tester.enterText(find.byKey(const Key('paid-amount')), '1250');
      await reach(tester, find.byKey(const Key('record-send')), list: form);
      await tester.tap(find.byKey(const Key('record-send')));
      await tester.pumpAndSettle();
      expect(api.sent, isEmpty);
      expect(c.problems.map((p) => p.kind), contains(ProblemKind.partNotLess));
      await reach(tester, find.byKey(const Key('problem-partNotLess-0')), list: form);
      expect(find.text('Ang bahagyang bayad ay mas mababa sa total ng resibo. Piliin ang Bayad nang buo.'), findsOneWidget);
    });

    testWidgets('own money only while allowed (Q21); a credit only for this supplier, within what is left (R10)', (tester) async {
      api.cash = const MyCashView(
        cash: MyCash(holder: true, recorded: 5000, held: 5000, ownMoney: true),
        credits: [
          SupplierCredit(id: 'c1', supplierId: 's1', supplier: 'ZZ Hardware', amount: 200, left: 80),
          SupplierCredit(id: 'c9', supplierId: 's9', supplier: 'Other', amount: 500, left: 500),
        ],
      );
      final c = await open(tester);
      expect(c.paySources, ['petty_cash', 'own_money', 'company', 'credit']);
      expect(c.credits.map((x) => x.id), ['c1'], reason: 'another supplier\'s credit is not offered');
      await choose(tester, const Key('paid-now'), 'Paid in full · Bayad nang buo', list: form);
      c.setPaidFrom('credit');
      await tester.pumpAndSettle();
      expect(c.draft.paidCredit, 'c1');
      await reach(tester, find.byKey(const Key('paid-credit')), list: form);
      expect(find.text('ZZ Hardware — ₱80.00 left'), findsOneWidget);
      expect(await c.send(), isFalse);
      expect(c.problems.map((p) => p.kind), contains(ProblemKind.overCredit));
      c.setSupplier(null);
      expect([c.draft.paidFrom, c.draft.paidCredit], ['petty_cash', null], reason: 'a typed supplier has no credit');
    });

    testWidgets('a staff buyer while "May use own money" is off: no own money (Q21)', (tester) async {
      api.cash = const MyCashView(cash: MyCash(holder: true, recorded: 500, held: 500, ownMoney: false));
      final c = await open(tester);
      expect(c.paySources, ['petty_cash', 'company']);
    });

    testWidgets('an owner account (not a staff buyer) is offered company money only (R2)', (tester) async {
      api.cash = const MyCashView(cash: MyCash(holder: false));
      final c = await open(tester);
      expect(c.paySources, ['company']);
      c.setPaidNow('full');
      expect(c.draft.paidFrom, 'company');
    });
  });

  group('Record payment (Q6)', () {
    const list = Key('pay-form');
    Future<void> open(WidgetTester tester, {double left = 700, String? supplierId = 's1'}) => show(
        tester, RecordPaymentScreen(services: services, purchaseId: 'pu1', supplier: 'ZZ Hardware', supplierId: supplierId, left: left));

    testWidgets('starts from what is left, petty cash for a staff buyer; queued with its proof', (tester) async {
      await open(tester);
      expect(find.text('₱700.00 left to pay'), findsOneWidget);
      expect((tester.widget(find.byKey(const Key('pay-amount'))) as TextField).controller!.text, '700.00');
      await reach(tester, find.byKey(const Key('pay-proof-camera')), list: list);
      await tester.tap(find.byKey(const Key('pay-proof-camera')));
      await tester.pumpAndSettle();
      await reach(tester, find.byKey(const Key('pay-save')), list: list);
      await tester.tap(find.byKey(const Key('pay-save')));
      await tester.pumpAndSettle();
      final (id, input, proof) = api.paid.single;
      expect([id, input.amount, input.source, input.paidOn, proof], ['pu1', '700.00', 'petty_cash', '2026-10-21', '/kept/shot1.jpg']);
    });

    testWidgets('Q16: over the cash held warns; Q6 refusals are shown, nothing queued', (tester) async {
      await open(tester, left: 2000);
      expect(find.byKey(const Key('pay-overspend')), findsOneWidget);
      await tester.enterText(find.byKey(const Key('pay-amount')), '0');
      await tester.pumpAndSettle();
      expect(find.byKey(const Key('pay-overspend')), findsNothing);
      await reach(tester, find.byKey(const Key('pay-save')), list: list);
      await tester.tap(find.byKey(const Key('pay-save')));
      await tester.pumpAndSettle();
      expect(api.paid, isEmpty);
      await reach(tester, find.byKey(const Key('pay-problem-badAmount')), list: list);
      expect(find.text('Ilagay ang halagang ibinayad.'), findsOneWidget);
    });

    testWidgets('a credit is "other", with its own picker and no method', (tester) async {
      api.cash = const MyCashView(
          cash: MyCash(holder: true, recorded: 5000, held: 5000),
          credits: [SupplierCredit(id: 'c1', supplierId: 's1', supplier: 'ZZ Hardware', amount: 200, left: 80)]);
      await open(tester, left: 50);
      await choose(tester, const ValueKey('pay-source-petty_cash,company,credit'), 'Supplier credit', list: list);
      expect(find.byKey(const Key('pay-method')), findsNothing);
      expect(find.text('ZZ Hardware — ₱80.00 left'), findsOneWidget);
      await reach(tester, find.byKey(const Key('pay-save')), list: list);
      await tester.tap(find.byKey(const Key('pay-save')));
      await tester.pumpAndSettle();
      expect([api.paid.single.$2.source, api.paid.single.$2.creditId], ['credit', 'c1']);
    });

    testWidgets('R39: Back during a slow Save waits; the proof handed to the queue is never deleted', (tester) async {
      useTallPhone(tester);
      bool? queued;
      await tester.pumpWidget(MaterialApp(
        theme: workMateTheme(),
        home: Builder(
          builder: (context) => Scaffold(
            body: TextButton(
              onPressed: () async =>
                  queued = await openRecordPayment(context, services, purchaseId: 'pu1', supplier: 'ZZ Hardware', supplierId: 's1', left: 700),
              child: const Text('open'),
            ),
          ),
        ),
      ));
      await tester.tap(find.text('open'));
      await tester.pumpAndSettle();
      await reach(tester, find.byKey(const Key('pay-proof-camera')), list: list);
      await tester.tap(find.byKey(const Key('pay-proof-camera')));
      await tester.pumpAndSettle();
      final gate = Completer<void>();
      api.saveGate = gate;
      await reach(tester, find.byKey(const Key('pay-save')), list: list);
      await tester.tap(find.byKey(const Key('pay-save')));
      await tester.pump();
      await tester.state<NavigatorState>(find.byType(Navigator)).maybePop();
      await tester.pump();
      // A closed screen is still drawn while it slides out: ask whether it is still the current one.
      expect(ModalRoute.of(tester.element(find.byType(RecordPaymentScreen)))!.isCurrent, isTrue, reason: 'Back waits for Save');
      gate.complete();
      await tester.pumpAndSettle();
      expect(find.byType(RecordPaymentScreen), findsNothing);
      expect(queued, isTrue);
      expect(api.paid.single.$3, '/kept/shot1.jpg');
      expect(api.calls.where((c) => c.startsWith('discardPhoto')), isEmpty, reason: 'the queue owns the proof now');
    });

    testWidgets('R39: a payment closed by the app during a slow Save keeps its proof for the queue', (tester) async {
      useTallPhone(tester);
      await tester.pumpWidget(MaterialApp(
        theme: workMateTheme(),
        home: RecordPaymentScreen(services: services, purchaseId: 'pu1', supplier: 'ZZ Hardware', supplierId: 's1', left: 700),
      ));
      await tester.pumpAndSettle();
      await reach(tester, find.byKey(const Key('pay-proof-camera')), list: list);
      await tester.tap(find.byKey(const Key('pay-proof-camera')));
      await tester.pumpAndSettle();
      final gate = Completer<void>();
      api.saveGate = gate;
      await reach(tester, find.byKey(const Key('pay-save')), list: list);
      await tester.tap(find.byKey(const Key('pay-save')));
      await tester.pump();
      // The app replaces the screen (e.g. signed out) while the Save is under way.
      await tester.pumpWidget(const SizedBox());
      gate.complete();
      await tester.pump();
      expect(api.paid.single.$3, '/kept/shot1.jpg');
      expect(api.calls.where((c) => c.startsWith('discardPhoto')), isEmpty, reason: 'the queue owns the proof now');
    });

    testWidgets('leaving without saving throws the proof photo away', (tester) async {
      await open(tester);
      await reach(tester, find.byKey(const Key('pay-proof-gallery')), list: list);
      await tester.tap(find.byKey(const Key('pay-proof-gallery')));
      await tester.pumpAndSettle();
      await tester.pumpWidget(const SizedBox());
      expect(api.calls, contains('discardPhoto:/kept/gallery.jpg'));
    });
  });

  group('My purchases: the payment line and the "My cash" card (Q23)', () {
    MyPurchase row(String id, Map<String, dynamic> pay, {String status = 'recorded'}) =>
        MyPurchase.fromJson({'id': id, 'status': status, 'supplier': 'ZZ Hardware', 'supplier_id': 's1', 'receipt_total': 1000, 'pay': pay});

    Future<MyPurchasesController> open(WidgetTester tester) async {
      final c = MyPurchasesController(api: api);
      await c.refresh();
      await show(tester, Scaffold(body: MyPurchasesScreen(controller: c, onOpenDraft: (_) {}, onOpenPurchase: (_) {}, services: services)));
      return c;
    }

    testWidgets('left to pay counts payments still on the phone; one refused shows why and can be thrown away', (tester) async {
      api.mine = MyPurchasesView(
        purchases: [
          row('pu1', {'state': 'partial', 'tracked': true, 'due': 1000, 'paid': 300, 'balance': 700}),
          row('pu2', {'state': 'not_tracked'}),
          row('pu3', {'state': 'overpaid', 'tracked': true, 'due': 1000, 'paid': 1500, 'unresolved': 500}),
        ],
        queuedPayments: const [
          QueuedCashAction(opId: 'op1', kind: opPay, body: {'purchase_id': 'pu1', 'payment': {'amount': '200.00', 'source': 'petty_cash'}}, state: QueuedState.waiting),
          QueuedCashAction(
              opId: 'op2', kind: opPay, body: {'purchase_id': 'pu1', 'payment': {'amount': '50.00', 'source': 'company'}},
              state: QueuedState.needsAttention, failure: PurFailure.alreadyVoided),
        ],
      );
      await open(tester);
      expect(find.text('That purchase is no longer recorded (it was voided or replaced).'), findsOneWidget);
      await tester.ensureVisible(find.byKey(const Key('throw-pay-op2')));
      await tester.tap(find.byKey(const Key('throw-pay-op2')));
      await tester.pumpAndSettle();
      expect(api.calls, contains('discardAction:op2'));
      await tester.scrollUntilVisible(find.text('₱500.00 left · ₱200.00 waiting to send'), 200);
      expect(find.text('₱500.00 left · ₱200.00 waiting to send'), findsOneWidget);
      await tester.scrollUntilVisible(find.text('₱500.00 over — the owner resolves it'), 200);
      expect(find.byKey(const Key('pay-line-pu2')), findsNothing, reason: 'Q2: payment not tracked');
    });

    testWidgets('F1: a voided purchase with nothing paid says "Voided" once — no payment tag; one paid still says what to recover', (tester) async {
      api.mine = MyPurchasesView(purchases: [
        row('pu1', {'state': 'void', 'tracked': true, 'due': 0}, status: 'void'),
        row('pu2', {'state': 'void_paid', 'tracked': true, 'due': 0, 'paid': 50, 'unresolved': 50}, status: 'void'),
      ]);
      await open(tester);
      expect(find.byKey(const Key('pay-line-pu1')), findsNothing);
      expect(find.text('Void'), findsNothing);
      expect(find.byKey(const Key('pay-line-pu2')), findsOneWidget);
      expect(find.text('Voided — paid, to recover'), findsOneWidget);
    });

    testWidgets('rev 2: the saved list and card show at once while the network stays blocked', (tester) async {
      api.savedMine = MyPurchasesView(purchases: [row('pu9', {'state': 'paid', 'tracked': true, 'due': 1000, 'paid': 1000})], fromCache: true);
      api.savedCash = const MyCashView(cash: MyCash(holder: true, recorded: 7, held: 7), fromCache: true);
      final blocked = Completer<void>();
      api.refreshGates.add(blocked);
      final c = MyPurchasesController(api: api);
      final pending = c.refresh();
      useTallPhone(tester);
      await tester.pumpWidget(MaterialApp(
        theme: workMateTheme(),
        home: Scaffold(body: MyPurchasesScreen(controller: c, onOpenDraft: (_) {}, onOpenPurchase: (_) {}, services: services)),
      ));
      await tester.pump();
      expect(find.byKey(const Key('pay-line-pu9')), findsOneWidget, reason: 'the saved purchase, before the network answers');
      expect(find.text('₱7.00'), findsOneWidget, reason: 'the saved card');
      expect(c.loading, isTrue);
      blocked.complete();
      await pending;
      await tester.pump();
      expect(find.byKey(const Key('pay-line-pu9')), findsNothing, reason: 'the fresh answer replaces it');
    });

    testWidgets('F3: a refresh that finishes after a newer one changes nothing', (tester) async {
      final c = MyPurchasesController(api: api);
      final slow = Completer<void>();
      api.refreshGates.add(slow);
      api.cash = const MyCashView(cash: MyCash(holder: true, recorded: 1, held: 1));
      final older = c.refresh();
      // Let the older refresh ask (and so take the old answer) before the cash changes.
      while (!api.calls.contains('myPurchasesAndCash')) {
        await tester.pump();
      }
      api.cash = const MyCashView(cash: MyCash(holder: true, recorded: 2, held: 2));
      await c.refresh();
      expect([c.cash.cash!.held, c.loading], [2, false]);
      slow.complete();
      await older;
      expect([c.cash.cash!.held, c.loading], [2, false], reason: 'the older answer is dropped');
    });

    testWidgets('R38: on My purchases a sent payment is "not in this list yet", never "waiting to send"', (tester) async {
      api.mine = MyPurchasesView(
        purchases: [row('pu1', {'state': 'partial', 'tracked': true, 'due': 1000, 'paid': 300, 'balance': 700})],
        queuedPayments: const [
          QueuedCashAction(opId: 'op1', kind: opPay, body: {'purchase_id': 'pu1', 'payment': {'amount': '200.00', 'source': 'petty_cash'}}, state: QueuedState.sent),
        ],
        fromCache: true,
      );
      await open(tester);
      expect(find.text(sentLabel.english), findsOneWidget);
      await tester.scrollUntilVisible(find.text('₱500.00 left · ₱200.00 not in this list yet'), 200);
      expect(find.text('₱500.00 left · ₱200.00 not in this list yet'), findsOneWidget);
    });

    testWidgets('the card: cash held never below zero, the shortfall said; a waiting return beside it', (tester) async {
      api.cash = const MyCashView(
        cash: MyCash(holder: true, recorded: 470, held: 470, owes: 50),
        unsentPettyCash: 1000,
        queued: [QueuedCashAction(opId: 'r1', kind: opCashReturn, body: {'amount': '100.00'}, state: QueuedState.waiting)],
      );
      await open(tester);
      expect(find.descendant(of: find.byKey(const Key('cash-held')), matching: find.text('₱0.00')), findsOneWidget);
      expect(find.byKey(const Key('cash-shortfall')), findsOneWidget);
      expect(find.textContaining('Shortfall ₱530.00'), findsOneWidget);
      expect(find.descendant(of: find.byKey(const Key('cash-waiting')), matching: find.text('₱100.00')), findsOneWidget);
      expect(find.descendant(of: find.byKey(const Key('cash-owes')), matching: find.text('₱50.00')), findsOneWidget);
    });

    testWidgets('an owner account has no card (no petty cash, R2)', (tester) async {
      api.cash = const MyCashView(cash: MyCash(holder: false));
      await open(tester);
      expect(find.byKey(const Key('my-cash-card')), findsNothing);
    });

    testWidgets('Record payment opens from the row', (tester) async {
      api.mine = MyPurchasesView(purchases: [row('pu1', {'state': 'unpaid', 'tracked': true, 'due': 1000, 'balance': 1000})]);
      await open(tester);
      await tester.tap(find.byKey(const Key('pay-pu1')));
      await tester.pumpAndSettle();
      expect(find.byType(RecordPaymentScreen), findsOneWidget);
      expect(find.text('₱1,000.00 left to pay'), findsOneWidget);
    });
  });

  group('My cash (Q14, Q17)', () {
    const list = Key('my-cash');
    testWidgets('"I did not receive this" needs a note and needs signal; a waiting return can be taken back', (tester) async {
      api.cash = const MyCashView(
        cash: MyCash(
          holder: true,
          recorded: 1470,
          held: 1470,
          issues: [CashIssue(id: 'i1', amount: 4500, issuedOn: '2026-10-22', method: 'cash'), CashIssue(id: 'i2', amount: 500, issuedOn: '2026-10-22', disputedAt: 'x')],
          returns: [CashReturn(id: 'r1', amount: 1000, handedOn: '2026-10-23', status: 'reported')],
        ),
      );
      await show(tester, MyCashScreen(services: services));
      expect(find.byKey(const Key('dispute-i2')), findsNothing, reason: 'one flag per entry');
      await tester.tap(find.byKey(const Key('dispute-i1')));
      await tester.pumpAndSettle();
      expect(tester.widget<TextButton>(find.byKey(const Key('note-send'))).onPressed, isNull, reason: 'a note is required');
      await tester.enterText(find.byKey(const Key('note-field')), 'never got it');
      await tester.pump();
      await tester.tap(find.byKey(const Key('note-send')));
      await tester.pumpAndSettle();
      expect(api.calls, contains('dispute:i1:never got it'));
      await reach(tester, find.byKey(const Key('withdraw-r1')), list: list);
      await tester.tap(find.byKey(const Key('withdraw-r1')));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const Key('withdraw-yes')));
      await tester.pumpAndSettle();
      expect(api.calls, contains('withdraw:r1'));
    });

    testWidgets('no signal: the online action says so; nothing changes', (tester) async {
      api.cash = const MyCashView(cash: MyCash(holder: true, issues: [CashIssue(id: 'i1', amount: 100, issuedOn: '2026-10-22')]));
      await show(tester, MyCashScreen(services: services));
      await tester.tap(find.byKey(const Key('dispute-i1')));
      await tester.pumpAndSettle();
      await tester.enterText(find.byKey(const Key('note-field')), 'x');
      await tester.pump();
      api.error = const SocketException('down');
      await tester.tap(find.byKey(const Key('note-send')));
      await tester.pumpAndSettle();
      expect(find.text('Kailangan ng signal. Subukan ulit kapag online ka na.'), findsOneWidget);
    });

    testWidgets('report a return: amount, day, to whom, a photo — queued (Q17)', (tester) async {
      await show(tester, MyCashScreen(services: services));
      await tester.tap(find.byKey(const Key('report-return')));
      await tester.pumpAndSettle();
      await tester.enterText(find.byKey(const Key('return-amount')), '1000');
      await tester.enterText(find.byKey(const Key('return-to')), 'the owner');
      await tester.tap(find.byKey(const Key('return-photo-camera')));
      await tester.pumpAndSettle();
      await tester.ensureVisible(find.byKey(const Key('return-save')));
      await tester.tap(find.byKey(const Key('return-save')));
      await tester.pumpAndSettle();
      final (r, photo) = api.returned.single;
      expect([r.amount, r.handedOn, r.handedTo, photo], ['1000', '2026-10-21', 'the owner', '/kept/shot1.jpg']);
    });

    testWidgets('R39: a return\'s photo survives Back during a slow Save', (tester) async {
      await show(tester, MyCashScreen(services: services));
      await tester.tap(find.byKey(const Key('report-return')));
      await tester.pumpAndSettle();
      await tester.enterText(find.byKey(const Key('return-amount')), '200');
      await tester.tap(find.byKey(const Key('return-photo-camera')));
      await tester.pumpAndSettle();
      final gate = Completer<void>();
      api.saveGate = gate;
      await tester.ensureVisible(find.byKey(const Key('return-save')));
      await tester.tap(find.byKey(const Key('return-save')));
      await tester.pump();
      await tester.state<NavigatorState>(find.byType(Navigator)).maybePop();
      await tester.pump();
      // A closed screen is still drawn while it slides out: ask whether it is still the current one.
      expect(ModalRoute.of(tester.element(find.byKey(const Key('return-save'))))!.isCurrent, isTrue, reason: 'Back waits for Save');
      gate.complete();
      await tester.pumpAndSettle();
      expect(api.returned.single.$2, '/kept/shot1.jpg');
      expect(api.calls.where((c) => c.startsWith('discardPhoto')), isEmpty);
    });

    testWidgets('R39: a return closed by the app during a slow Save keeps its photo for the queue', (tester) async {
      await show(tester, MyCashScreen(services: services));
      await tester.tap(find.byKey(const Key('report-return')));
      await tester.pumpAndSettle();
      await tester.enterText(find.byKey(const Key('return-amount')), '200');
      await tester.tap(find.byKey(const Key('return-photo-camera')));
      await tester.pumpAndSettle();
      final gate = Completer<void>();
      api.saveGate = gate;
      await tester.ensureVisible(find.byKey(const Key('return-save')));
      await tester.tap(find.byKey(const Key('return-save')));
      await tester.pump();
      // The app replaces the screen (e.g. signed out) while the Save is under way.
      await tester.pumpWidget(const SizedBox());
      gate.complete();
      await tester.pump();
      expect(api.returned.single.$2, '/kept/shot1.jpg');
      expect(api.calls.where((c) => c.startsWith('discardPhoto')), isEmpty, reason: 'the queue owns the photo now');
    });

    testWidgets('rev 2: My cash shows its saved cash at once while the network stays blocked', (tester) async {
      final blocked = Completer<void>();
      api.cashGates.add(blocked);
      api.savedCash = const MyCashView(cash: MyCash(holder: true, recorded: 7, held: 7), fromCache: true);
      api.cash = const MyCashView(cash: MyCash(holder: true, recorded: 9, held: 9));
      useTallPhone(tester);
      await tester.pumpWidget(MaterialApp(theme: workMateTheme(), home: MyCashScreen(services: services)));
      await tester.pump();
      await tester.pump();
      expect(find.text('₱7.00'), findsOneWidget);
      blocked.complete();
      await tester.pumpAndSettle();
      expect([find.text('₱9.00').evaluate().length, find.text('₱7.00').evaluate().length], [1, 0]);
    });

    testWidgets('F3: an older load that finishes after a pull to refresh changes nothing', (tester) async {
      final slow = Completer<void>();
      api.cashGates.add(slow);
      api.cash = const MyCashView(cash: MyCash(holder: true, recorded: 1, held: 1));
      useTallPhone(tester);
      await tester.pumpWidget(MaterialApp(theme: workMateTheme(), home: MyCashScreen(services: services)));
      await tester.pump();
      api.cash = const MyCashView(cash: MyCash(holder: true, recorded: 2, held: 2));
      unawaited(tester.state<RefreshIndicatorState>(find.byType(RefreshIndicator)).show());
      await tester.pump();
      await tester.pump(const Duration(seconds: 1));
      await tester.pumpAndSettle();
      expect(find.text('₱2.00'), findsOneWidget);
      slow.complete();
      await tester.pumpAndSettle();
      expect([find.text('₱2.00').evaluate().length, find.text('₱1.00').evaluate().length], [1, 0], reason: 'the older answer is dropped');
    });

    testWidgets('never read and no signal: it says to connect once', (tester) async {
      api.cash = const MyCashView();
      await show(tester, MyCashScreen(services: services));
      expect(find.text('Connect once to see your cash.'), findsOneWidget);
    });
  });

  group('a purchase\'s Payments (Q7)', () {
    testWidgets('each payment with its source and notes; Void needs a reason; Record payment from here', (tester) async {
      api.detail = PurchaseDetail.fromJson(const {'id': 'pu1', 'status': 'recorded', 'supplier': 'ZZ Hardware', 'receipt_total': 1000});
      api.payments = PurchasePayments.fromJson({
        'pay': {'state': 'partial', 'tracked': true, 'due': 1000, 'paid': 300, 'balance': 700},
        'payments': [
          {'id': 'p1', 'amount': 300, 'paid_on': '2026-10-22', 'source': 'petty_cash', 'method': 'cash', 'created_by_name': 'staff', 'can_void': true, 'moved': true},
          {'id': 'p2', 'amount': 100, 'paid_on': '2026-10-22', 'source': 'own_money', 'method': 'cash', 'authorized': false, 'can_void': true,
            'rejected_at': 'x', 'reject_reason': 'ZZ not approved', 'voided_at': 'y', 'void_reason': 'twice'},
        ],
        'me': {'holder': true},
      });
      await show(tester, PurchaseDetailScreen(purchaseId: 'pu1', services: services));
      expect(find.textContaining('carried over from the earlier version'), findsOneWidget);
      expect(find.textContaining('rejected by the owner: ZZ not approved — not owed'), findsOneWidget);
      expect(find.byKey(const Key('void-p2')), findsNothing, reason: 'already void');
      await tester.ensureVisible(find.byKey(const Key('void-p1')));
      await tester.tap(find.byKey(const Key('void-p1')));
      await tester.pumpAndSettle();
      expect(tester.widget<TextButton>(find.byKey(const Key('void-yes'))).onPressed, isNull);
      await tester.enterText(find.byKey(const Key('void-reason')), 'paid twice');
      await tester.pump();
      await tester.tap(find.byKey(const Key('void-yes')));
      await tester.pumpAndSettle();
      expect(api.calls, contains('voidPayment:p1:paid twice'));
      await tester.ensureVisible(find.byKey(const Key('detail-pay')));
      await tester.tap(find.byKey(const Key('detail-pay')));
      await tester.pumpAndSettle();
      expect(find.text('₱700.00 left to pay'), findsOneWidget);
    });

    testWidgets('Phase 6b: the "Saved" snack bar is cleared when Record payment opens again, so it never floats over Save', (tester) async {
      api.detail = PurchaseDetail.fromJson(const {'id': 'pu1', 'status': 'recorded', 'supplier': 'ZZ Hardware', 'receipt_total': 1000});
      api.payments = PurchasePayments.fromJson({
        'pay': {'state': 'partial', 'tracked': true, 'due': 1000, 'paid': 300, 'balance': 700},
        'payments': [],
        'me': {'holder': true},
      });
      await show(tester, PurchaseDetailScreen(purchaseId: 'pu1', services: services));
      await tester.ensureVisible(find.byKey(const Key('detail-pay')));
      await tester.tap(find.byKey(const Key('detail-pay')));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const Key('pay-save')));
      await tester.pumpAndSettle();
      expect(find.textContaining('Saved. It is sent when there is signal.'), findsOneWidget);
      await tester.ensureVisible(find.byKey(const Key('detail-pay')));
      await tester.tap(find.byKey(const Key('detail-pay')));
      await tester.pumpAndSettle();
      expect(find.byType(RecordPaymentScreen), findsOneWidget);
      expect(find.byType(SnackBar), findsNothing);
    });

    testWidgets('payments waiting on the phone show on the purchase and count in what is left — never offered twice', (tester) async {
      api.detail = PurchaseDetail.fromJson(const {'id': 'pu1', 'status': 'recorded', 'supplier': 'ZZ Hardware', 'receipt_total': 1000});
      api.payments = PurchasePayments.fromJson({
        'pay': {'state': 'partial', 'tracked': true, 'due': 1000, 'paid': 300, 'balance': 700},
        'payments': [],
        'me': {'holder': true},
      });
      api.queuedFor = const [
        QueuedCashAction(opId: 'op1', kind: opPay, body: {'purchase_id': 'pu1', 'payment': {'amount': '300.00', 'source': 'petty_cash'}}, state: QueuedState.waiting),
      ];
      await show(tester, PurchaseDetailScreen(purchaseId: 'pu1', services: services));
      expect(find.text('Receipt ₱1,000.00 · paid ₱300.00 · left ₱400.00 · ₱300.00 waiting to send'), findsOneWidget);
      expect(find.byKey(const Key('payment-queued-op1')), findsOneWidget);
      await tester.ensureVisible(find.byKey(const Key('detail-pay')));
      await tester.tap(find.byKey(const Key('detail-pay')));
      await tester.pumpAndSettle();
      expect(find.text('₱400.00 left to pay'), findsOneWidget);
    });

    testWidgets('R38: a payment sent after the list was read says so, and still counts in what is left', (tester) async {
      api.detail = PurchaseDetail.fromJson(const {'id': 'pu1', 'status': 'recorded', 'supplier': 'ZZ Hardware', 'receipt_total': 1000});
      api.payments = PurchasePayments.fromJson({
        'pay': {'state': 'partial', 'tracked': true, 'due': 1000, 'paid': 300, 'balance': 700},
        'payments': [],
        'me': {'holder': true},
      });
      api.queuedFor = const [
        QueuedCashAction(opId: 'op1', kind: opPay, body: {'purchase_id': 'pu1', 'payment': {'amount': '300.00', 'source': 'petty_cash'}}, state: QueuedState.sent),
      ];
      await show(tester, PurchaseDetailScreen(purchaseId: 'pu1', services: services));
      expect(find.text('Receipt ₱1,000.00 · paid ₱300.00 · left ₱400.00 · ₱300.00 not in this list yet'), findsOneWidget);
      expect(find.textContaining(sentLabel.english), findsOneWidget);
    });

    testWidgets('a purchase from before payments were tracked offers no Record payment (Q2, R34)', (tester) async {
      api.detail = PurchaseDetail.fromJson(const {'id': 'pu1', 'status': 'recorded', 'supplier': 'ZZ Hardware', 'receipt_total': 1000});
      api.payments = PurchasePayments.fromJson({'pay': {'state': 'not_tracked', 'tracked': false, 'due': 1000, 'balance': 1000}, 'payments': []});
      await show(tester, PurchaseDetailScreen(purchaseId: 'pu1', services: services));
      expect(find.text('Recorded before payments were tracked.'), findsOneWidget);
      expect(find.byKey(const Key('detail-pay')), findsNothing);
    });

    testWidgets('F2: no signal to open a purchase: it says a payment can still be recorded from the list', (tester) async {
      api.error = const SocketException('down');
      await show(tester, PurchaseDetailScreen(purchaseId: 'pu1', services: services));
      expect(find.text('No signal right now. Try again in a moment.'), findsOneWidget);
      expect(find.byKey(const Key('detail-offline-hint')), findsOneWidget);
      expect(find.textContaining('You can still record a payment from My purchases'), findsOneWidget);
    });

    testWidgets('F3: an older load of a purchase that finishes last changes nothing', (tester) async {
      api.detail = PurchaseDetail.fromJson(const {'id': 'pu1', 'status': 'recorded', 'supplier': 'ZZ Hardware', 'receipt_total': 1000});
      PurchasePayments state(String s, double paid) => PurchasePayments.fromJson({
            'pay': {'state': s, 'tracked': true, 'due': 1000, 'paid': paid, 'balance': 1000 - paid},
            'payments': [],
            'me': {'holder': true},
          });
      api.payments = state('unpaid', 0);
      await show(tester, PurchaseDetailScreen(purchaseId: 'pu1', services: services));
      expect(find.text('Unpaid'), findsOneWidget);
      // Each saved payment reloads the screen: two in a row, the first reload slow.
      Future<void> recordPayment() async {
        await tester.ensureVisible(find.byKey(const Key('detail-pay')));
        await tester.tap(find.byKey(const Key('detail-pay')));
        await tester.pumpAndSettle();
        // The first save's "recorded" snack bar floats over the pinned Save button for a few seconds: clear it, as a person waits it out.
        ScaffoldMessenger.of(tester.element(find.byType(RecordPaymentScreen))).clearSnackBars();
        await tester.pumpAndSettle();
        await reach(tester, find.byKey(const Key('pay-save')), list: const Key('pay-form'));
        await tester.tap(find.byKey(const Key('pay-save')));
        await tester.pump();
        await tester.pump(const Duration(seconds: 1));
      }

      final slow = Completer<void>();
      api.paymentsGates.add(slow);
      api.payments = state('partial', 300);
      await recordPayment();
      api.payments = state('paid', 1000);
      await recordPayment();
      await tester.pumpAndSettle();
      expect(find.text('Paid'), findsOneWidget);
      slow.complete();
      await tester.pumpAndSettle();
      expect([find.text('Paid').evaluate().length, find.text('Partially paid').evaluate().length], [1, 0], reason: 'the older answer is dropped');
    });

    testWidgets('rev 3: a reload whose payments read fails shows "needs signal" — never the earlier balance beside a newer queue', (tester) async {
      api.detail = PurchaseDetail.fromJson(const {'id': 'pu1', 'status': 'recorded', 'supplier': 'ZZ Hardware', 'receipt_total': 1000});
      api.payments = PurchasePayments.fromJson({
        'pay': {'state': 'unpaid', 'tracked': true, 'due': 1000, 'paid': 0, 'balance': 1000},
        'payments': [],
        'me': {'holder': true},
      });
      await show(tester, PurchaseDetailScreen(purchaseId: 'pu1', services: services));
      expect(find.text('Receipt ₱1,000.00 · paid ₱0.00 · left ₱1,000.00'), findsOneWidget);
      // A payment is sent and the saved list now counts it; the next payments read fails.
      await tester.ensureVisible(find.byKey(const Key('detail-pay')));
      await tester.tap(find.byKey(const Key('detail-pay')));
      await tester.pumpAndSettle();
      api.queuedFor = const [
        QueuedCashAction(opId: 'op1', kind: opPay, body: {'purchase_id': 'pu1', 'payment': {'amount': '1000.00', 'source': 'petty_cash'}}, state: QueuedState.sent),
      ];
      api.paymentsError = const SocketException('down');
      await reach(tester, find.byKey(const Key('pay-save')), list: const Key('pay-form'));
      await tester.tap(find.byKey(const Key('pay-save')));
      await tester.pumpAndSettle();
      expect(find.byKey(const Key('payments-offline')), findsOneWidget, reason: 'needs signal');
      expect(find.textContaining('left ₱'), findsNothing, reason: 'no balance from the earlier read');
      expect(find.byKey(const Key('detail-pay')), findsNothing, reason: 'no payment offered on a mismatched balance');
    });

    testWidgets('F2: any other reason it cannot open: no such hint', (tester) async {
      api.error = const PurFailureException(PurFailure.notFound);
      await show(tester, PurchaseDetailScreen(purchaseId: 'pu1', services: services));
      expect(find.byKey(const Key('detail-offline-hint')), findsNothing);
    });

    testWidgets('no signal for the payments: the purchase still shows', (tester) async {
      api.detail = PurchaseDetail.fromJson(const {'id': 'pu1', 'status': 'recorded', 'supplier': 'ZZ Hardware'});
      api.paymentsError = const SocketException('down');
      await show(tester, PurchaseDetailScreen(purchaseId: 'pu1', services: services));
      expect(find.text('ZZ Hardware'), findsOneWidget);
      expect(find.byKey(const Key('payments-offline')), findsOneWidget);
    });
  });

  // Phase 6b: My cash, its card, Record payment and Report a return take the WmPage look (layout only).
  group('Phase 6b: the pay pages in the new look', () {
    Finder inList(Key k) => find.descendant(of: find.byType(ListView), matching: find.byKey(k));
    Finder inFooter(Key k) => find.descendant(of: find.byType(SingleChildScrollView), matching: find.byKey(k));

    void useSmallPhone(WidgetTester tester) {
      tester.view.physicalSize = const Size(320, 568);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.reset);
      tester.platformDispatcher.textScaleFactorTestValue = 1.3;
      addTearDown(tester.platformDispatcher.clearTextScaleFactorTestValue);
    }

    group('Record payment', () {
      Widget screen() => RecordPaymentScreen(services: services, purchaseId: 'pu1', supplier: 'ZZ Hardware', supplierId: 's1', left: 700);

      testWidgets('a round back button, the title, and Save pinned in the footer (not in the scrolling list)', (tester) async {
        await show(tester, screen());
        expect(find.byKey(const Key('wm-page-back')), findsOneWidget);
        expect(find.byType(AppBar), findsNothing);
        expect(find.text('Record payment'), findsWidgets);
        expect(find.text('Itala ang bayad'), findsWidgets);
        expect(inFooter(const Key('pay-save')), findsOneWidget);
        expect(inList(const Key('pay-save')), findsNothing);
        expect(find.text('₱700.00 left to pay'), findsOneWidget);
      });

      testWidgets('Save in the footer queues exactly today\'s body', (tester) async {
        await show(tester, screen());
        await tester.tap(find.byKey(const Key('pay-save')));
        await tester.pumpAndSettle();
        final (id, input, proof) = api.paid.single;
        expect([id, input.amount, input.source, input.paidOn, input.method, input.note, proof], ['pu1', '700.00', 'petty_cash', '2026-10-21', 'cash', '', null]);
      });

      testWidgets('the over-spend warning and a problem sit by their fields', (tester) async {
        await show(tester, RecordPaymentScreen(services: services, purchaseId: 'pu1', supplier: 'ZZ Hardware', supplierId: 's1', left: 2000));
        final warn = tester.getTopLeft(find.byKey(const Key('pay-overspend'))).dy;
        expect(warn, greaterThan(tester.getTopLeft(find.byKey(const Key('pay-method'))).dy));
        expect(warn, lessThan(tester.getTopLeft(find.byKey(const Key('pay-note'))).dy));
        await tester.enterText(find.byKey(const Key('pay-amount')), '0');
        await tester.pumpAndSettle();
        await tester.tap(find.byKey(const Key('pay-save')));
        await tester.pumpAndSettle();
        expect(api.paid, isEmpty);
        expect(find.byKey(const Key('pay-problem-badAmount')), findsOneWidget);
        expect(tester.getTopLeft(find.byKey(const Key('pay-problem-badAmount'))).dy, lessThan(tester.getTopLeft(find.byKey(const Key('pay-date'))).dy));
      });

      testWidgets('the round back button leaves; during a slow Save it does not', (tester) async {
        useTallPhone(tester);
        await tester.pumpWidget(MaterialApp(
          theme: workMateTheme(),
          home: Builder(
            builder: (context) => Scaffold(
              body: TextButton(
                onPressed: () => openRecordPayment(context, services, purchaseId: 'pu1', supplier: 'ZZ Hardware', supplierId: 's1', left: 700),
                child: const Text('open'),
              ),
            ),
          ),
        ));
        await tester.tap(find.text('open'));
        await tester.pumpAndSettle();
        final gate = Completer<void>();
        api.saveGate = gate;
        await tester.tap(find.byKey(const Key('pay-save')));
        await tester.pump();
        await tester.tap(find.byKey(const Key('wm-page-back')));
        await tester.pump();
        expect(ModalRoute.of(tester.element(find.byType(RecordPaymentScreen)))!.isCurrent, isTrue, reason: 'Back waits for Save');
        gate.complete();
        await tester.pumpAndSettle();
        expect(find.byType(RecordPaymentScreen), findsNothing);
        expect(api.paid, hasLength(1));
      });

      testWidgets('back without saving closes the page', (tester) async {
        useTallPhone(tester);
        await tester.pumpWidget(MaterialApp(
          theme: workMateTheme(),
          home: Builder(
            builder: (context) => Scaffold(
              body: TextButton(
                onPressed: () => openRecordPayment(context, services, purchaseId: 'pu1', supplier: 'ZZ Hardware', supplierId: 's1', left: 700),
                child: const Text('open'),
              ),
            ),
          ),
        ));
        await tester.tap(find.text('open'));
        await tester.pumpAndSettle();
        await tester.tap(find.byKey(const Key('wm-page-back')));
        await tester.pumpAndSettle();
        expect(find.byType(RecordPaymentScreen), findsNothing);
        expect(api.paid, isEmpty);
      });

      testWidgets('320 x 568 at text scale 1.3 raises no exception', (tester) async {
        useSmallPhone(tester);
        await tester.pumpWidget(MaterialApp(theme: workMateTheme(), home: screen()));
        await tester.pumpAndSettle();
        expect(tester.takeException(), isNull);
        await tester.tap(find.byKey(const Key('pay-save')));
        await tester.pumpAndSettle();
        expect(tester.takeException(), isNull);
      });
    });

    group('Report a return', () {
      Future<void> openReturn(WidgetTester tester) async {
        api.cash = const MyCashView(cash: MyCash(holder: true, recorded: 1470, held: 1470));
        await show(tester, MyCashScreen(services: services));
        await tester.tap(find.byKey(const Key('report-return')));
        await tester.pumpAndSettle();
      }

      testWidgets('a round back button, the title, Save pinned in the footer; the hold hint stays', (tester) async {
        await openReturn(tester);
        expect(find.byKey(const Key('wm-page-back')), findsOneWidget);
        expect(find.byType(AppBar), findsNothing);
        expect(find.text('Report a return'), findsWidgets);
        expect(inFooter(const Key('return-save')), findsOneWidget);
        expect(inList(const Key('return-save')), findsNothing);
        expect(find.text('You hold ₱1,470.00 on record.'), findsOneWidget);
      });

      testWidgets('Save in the footer queues exactly today\'s body; a problem shows by its field', (tester) async {
        await openReturn(tester);
        await tester.tap(find.byKey(const Key('return-save')));
        await tester.pumpAndSettle();
        expect(api.returned, isEmpty);
        expect(find.byKey(const Key('return-problem-amount')), findsOneWidget);
        expect(tester.getTopLeft(find.byKey(const Key('return-problem-amount'))).dy, lessThan(tester.getTopLeft(find.byKey(const Key('return-date'))).dy));
        await tester.enterText(find.byKey(const Key('return-amount')), '1000');
        await tester.enterText(find.byKey(const Key('return-to')), 'the owner');
        await tester.enterText(find.byKey(const Key('return-note')), 'n');
        await tester.tap(find.byKey(const Key('return-save')));
        await tester.pumpAndSettle();
        final (r, photo) = api.returned.single;
        expect([r.amount, r.handedOn, r.handedTo, r.note, photo], ['1000', '2026-10-21', 'the owner', 'n', null]);
        expect(find.byType(ReportReturnScreen), findsNothing, reason: 'queued: the page closes');
      });

      testWidgets('the round back button leaves; during a slow Save it does not', (tester) async {
        await openReturn(tester);
        await tester.enterText(find.byKey(const Key('return-amount')), '200');
        final gate = Completer<void>();
        api.saveGate = gate;
        await tester.tap(find.byKey(const Key('return-save')));
        await tester.pump();
        await tester.tap(find.byKey(const Key('wm-page-back')));
        await tester.pump();
        expect(ModalRoute.of(tester.element(find.byKey(const Key('return-save'))))!.isCurrent, isTrue, reason: 'Back waits for Save');
        gate.complete();
        await tester.pumpAndSettle();
        expect(api.returned, hasLength(1));
      });

      testWidgets('back without saving closes the page', (tester) async {
        await openReturn(tester);
        await tester.tap(find.byKey(const Key('wm-page-back')));
        await tester.pumpAndSettle();
        expect(find.byType(ReportReturnScreen), findsNothing);
        expect(find.byKey(const Key('my-cash')), findsOneWidget);
      });

      testWidgets('320 x 568 at text scale 1.3 raises no exception', (tester) async {
        useSmallPhone(tester);
        await tester.pumpWidget(MaterialApp(theme: workMateTheme(), home: ReportReturnScreen(services: services, held: 1470)));
        await tester.pumpAndSettle();
        expect(tester.takeException(), isNull);
        await tester.tap(find.byKey(const Key('return-save')));
        await tester.pumpAndSettle();
        expect(tester.takeException(), isNull);
      });
    });

    group('My cash', () {
      const cash = MyCashView(
        cash: MyCash(
          holder: true,
          recorded: 1470,
          held: 1470,
          owes: 50,
          issues: [CashIssue(id: 'i1', amount: 4500, issuedOn: '2026-10-22', method: 'cash')],
          returns: [CashReturn(id: 'r1', amount: 1000, handedOn: '2026-10-23', status: 'reported')],
          repayments: [Repayment(id: 'p1', amount: 250, paidOn: '2026-10-24', method: 'cash')],
        ),
        queued: [QueuedCashAction(opId: 'q1', kind: opCashReturn, body: {'amount': '100.00'}, state: QueuedState.waiting)],
      );

      testWidgets('a round back button, the title with its Tagalog, no AppBar and no footer; report-return stays in the body', (tester) async {
        api.cash = cash;
        await show(tester, MyCashScreen(services: services));
        expect(find.byKey(const Key('wm-page-back')), findsOneWidget);
        expect(find.byType(AppBar), findsNothing);
        expect(find.text('My cash'), findsWidgets);
        expect(find.text('Pera ko'), findsOneWidget);
        expect(inList(const Key('report-return')), findsOneWidget);
        expect(find.byKey(const Key('my-cash')), findsOneWidget);
      });

      const labels = [
        ('NOT SENT YET', 'Hindi pa naipapadala'),
        ('PETTY CASH YOU WERE GIVEN (90 DAYS)', 'Petty cash na ibinigay sa iyo (90 araw)'),
        ('RETURNS', 'Mga ibinalik'),
        ('REPAID TO YOU (90 DAYS)', 'Ibinalik sa iyo (90 araw)'),
      ];

      testWidgets('a group label that fits is one line: English in capitals, then · Tagalog', (tester) async {
        api.cash = cash;
        await show(tester, MyCashScreen(services: services));
        // Wide enough for the longest label on one line.
        tester.view.physicalSize = const Size(3600, 3000);
        await tester.pumpAndSettle();
        for (final (en, tl) in labels) {
          await tester.ensureVisible(find.text(en));
          await tester.pumpAndSettle();
          expect(find.text(en), findsOneWidget, reason: en);
          expect(find.text(' · $tl'), findsOneWidget, reason: tl);
          expect(find.text(tl), findsNothing, reason: '$en: the Tagalog keeps its dot while it fits');
          final english = tester.getRect(find.text(en)), tagalog = tester.getRect(find.text(' · $tl'));
          expect(tagalog.center.dy, closeTo(english.center.dy, 1), reason: '$en: on one line');
          expect(tagalog.left, greaterThanOrEqualTo(english.right - .5), reason: '$en: the Tagalog after the English');
        }
      });

      testWidgets('a group label too long for one line puts the Tagalog on its own line, without the dot', (tester) async {
        api.cash = cash;
        await show(tester, MyCashScreen(services: services));
        for (final (en, tl) in labels.where((l) => l.$1 != 'RETURNS')) {
          await tester.ensureVisible(find.text(en));
          await tester.pumpAndSettle();
          expect(find.text(en), findsOneWidget, reason: en);
          expect(find.text(tl), findsOneWidget, reason: tl);
          expect(find.text(' · $tl'), findsNothing, reason: '$en: no dot left at the start of a line');
          final english = tester.getRect(find.text(en)), tagalog = tester.getRect(find.text(tl));
          expect(tagalog.top, greaterThanOrEqualTo(english.bottom - .5), reason: '$en: the Tagalog under the English');
          expect(tagalog.left, closeTo(english.left, .5), reason: '$en: both start at the left');
        }
        // A short label on the same screen still fits on one line, with its dot.
        await tester.ensureVisible(find.text('RETURNS'));
        await tester.pumpAndSettle();
        expect(find.text(' · Mga ibinalik'), findsOneWidget);
        expect(find.text('Mga ibinalik'), findsNothing);
      });

      testWidgets('the figures and every list row keep their amounts and actions', (tester) async {
        api.cash = cash;
        await show(tester, MyCashScreen(services: services));
        expect(find.descendant(of: find.byKey(const Key('detail-held')), matching: find.text('₱1,470.00')), findsOneWidget);
        expect(find.descendant(of: find.byKey(const Key('detail-owes')), matching: find.text('₱50.00')), findsOneWidget);
        for (final k in ['issue-i1', 'dispute-i1', 'queued-return-q1', 'return-r1', 'withdraw-r1']) {
          await tester.ensureVisible(find.byKey(Key(k)));
          await tester.pumpAndSettle();
          expect(find.byKey(Key(k)), findsOneWidget, reason: k);
        }
        expect(find.textContaining('₱4,500.00'), findsOneWidget);
        expect(find.textContaining('₱1,000.00'), findsOneWidget);
        await tester.ensureVisible(find.textContaining('₱250.00'));
        expect(find.textContaining('₱250.00'), findsOneWidget);
      });

      testWidgets('the round back button leaves My cash', (tester) async {
        api.cash = cash;
        useTallPhone(tester);
        await tester.pumpWidget(MaterialApp(
          theme: workMateTheme(),
          home: Builder(
            builder: (context) => Scaffold(
              body: TextButton(onPressed: () => Navigator.of(context).push(MaterialPageRoute<void>(builder: (_) => MyCashScreen(services: services))), child: const Text('open')),
            ),
          ),
        ));
        await tester.tap(find.text('open'));
        await tester.pumpAndSettle();
        expect(find.byType(MyCashScreen), findsOneWidget);
        await tester.tap(find.byKey(const Key('wm-page-back')));
        await tester.pumpAndSettle();
        expect(find.byType(MyCashScreen), findsNothing);
      });

      testWidgets('320 x 568 at text scale 1.3 raises no exception', (tester) async {
        api.cash = cash;
        useSmallPhone(tester);
        await tester.pumpWidget(MaterialApp(theme: workMateTheme(), home: MyCashScreen(services: services)));
        await tester.pumpAndSettle();
        expect(tester.takeException(), isNull);
      });
    });

    group('the My cash card', () {
      testWidgets('is a white bordered card, radius 16, no shadow, with its figures, a chevron, and opens My cash', (tester) async {
        api.cash = const MyCashView(cash: MyCash(holder: true, recorded: 470, held: 470, owes: 50));
        final c = MyPurchasesController(api: api);
        await c.refresh();
        await show(tester, Scaffold(body: MyPurchasesScreen(controller: c, onOpenDraft: (_) {}, onOpenPurchase: (_) {}, services: services)));
        final card = find.byKey(const Key('my-cash-card'));
        expect(card, findsOneWidget);
        expect(find.byType(Card), findsNothing, reason: 'the 6a card is a bordered container, not a Material card');
        final box = tester.widget<Container>(card);
        final deco = box.decoration! as BoxDecoration;
        expect(deco.color, Colors.white);
        expect(deco.borderRadius, BorderRadius.circular(16));
        expect(deco.border, isNotNull);
        expect(deco.boxShadow, isNull);
        expect(find.descendant(of: card, matching: find.byIcon(Icons.chevron_right)), findsOneWidget);
        expect(find.descendant(of: find.byKey(const Key('cash-held')), matching: find.text('₱470.00')), findsOneWidget);
        expect(find.descendant(of: find.byKey(const Key('cash-owes')), matching: find.text('₱50.00')), findsOneWidget);
        await tester.tap(card);
        await tester.pumpAndSettle();
        expect(find.byType(MyCashScreen), findsOneWidget);
      });

      testWidgets('320 x 568 at text scale 1.3 raises no exception', (tester) async {
        api.cash = const MyCashView(
          cash: MyCash(holder: true, recorded: 470, held: 470, owes: 50),
          unsentPettyCash: 1000,
          queued: [QueuedCashAction(opId: 'r1', kind: opCashReturn, body: {'amount': '100.00'}, state: QueuedState.waiting)],
        );
        useSmallPhone(tester);
        final c = MyPurchasesController(api: api);
        await c.refresh();
        await tester.pumpWidget(MaterialApp(
          theme: workMateTheme(),
          home: Scaffold(body: MyPurchasesScreen(controller: c, onOpenDraft: (_) {}, onOpenPurchase: (_) {}, services: services)),
        ));
        await tester.pumpAndSettle();
        expect(tester.takeException(), isNull);
        expect(find.byKey(const Key('my-cash-card')), findsOneWidget);
      });
    });
  });
}
