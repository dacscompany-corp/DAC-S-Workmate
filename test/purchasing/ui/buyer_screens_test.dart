import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:workmate/auth/worker_profile.dart';
import 'package:workmate/profile/account_services.dart';
import 'package:workmate/purchasing/data/purchasing_api.dart';
import 'package:workmate/purchasing/domain/purchase_draft.dart';
import 'package:workmate/purchasing/purchasing_services.dart';
import 'package:workmate/purchasing/ui/buyer_shell.dart';
import 'package:workmate/purchasing/ui/buying_off_screen.dart';
import 'package:workmate/ui/gate_unavailable_screen.dart';
import 'package:workmate/ui/theme.dart';

import '../../attendance/fakes.dart' show useTallPhone;
import '../purchasing_api_fake.dart';
import '../purchasing_fakes.dart';

Widget wrap(Widget w) => MaterialApp(theme: workMateTheme(), home: w);

const staff = WorkerProfile(id: 's1', email: 'staff@dacsbuilding.com', displayName: 'Ana Reyes', role: 'staff', status: 'active');

final account = AccountServices(changePassword: (_) async {}, termsAcceptedAt: () async => null);

void main() {
  testWidgets('a buyer\'s Profile: Buyer, no worker ID, no Attendance Terms (Q23), Log out', (tester) async {
    var signedOut = 0;
    await tester.pumpWidget(wrap(BuyerShell(
      buyer: staff,
      versionName: '0.7.0',
      onSignOut: () async => signedOut++,
      account: account,
    )));
    expect(find.text('Ana Reyes'), findsOneWidget);
    expect(find.text('Buyer'), findsWidgets);
    expect(find.text('Worker ID'), findsNothing);
    expect(find.text('Terms & Conditions'), findsNothing);
    expect(find.text('Change password'), findsOneWidget);
    await tester.tap(find.text('Log out'));
    expect(signedOut, 1);
  });

  testWidgets('with buying available: Shopping list first, then Profile', (tester) async {
    await tester.pumpWidget(wrap(BuyerShell(
      buyer: staff,
      versionName: '0.7.0',
      onSignOut: () async {},
      account: account,
      purchasing: PurchasingServices(api: FakePurchasingApi()),
    )));
    await tester.pumpAndSettle();
    expect(find.text('Shopping list'), findsWidgets);
    expect(find.text('My purchases'), findsOneWidget);
    expect(find.text('Profile'), findsOneWidget);
    expect(find.text('Time In'), findsNothing);
    expect(find.text('Requests'), findsNothing);
    expect(find.text('My Work'), findsNothing);
    expect(find.byKey(const Key('record-unplanned')), findsOneWidget);
    await tester.tap(find.text('Profile'));
    await tester.pumpAndSettle();
    expect(find.text('Change password'), findsOneWidget);
  });

  testWidgets('Buying is turned off: said in both languages, with TRY AGAIN and Log out (R2)', (tester) async {
    var retried = 0;
    await tester.pumpWidget(wrap(BuyingOffScreen(onRetry: () => retried++, onSignOut: () {}, unsent: 2)));
    expect(find.text('Buying is turned off for your account. Ask the owner if this is a mistake.'), findsOneWidget);
    expect(find.text('Naka-off ang pagbili sa account mo. Tanungin ang may-ari kung mali ito.'), findsOneWidget);
    expect(find.byKey(const Key('buying-off-unsent')), findsOneWidget);
    expect(find.textContaining('2 purchases not sent yet stay on this phone'), findsOneWidget);
    await tester.tap(find.text('TRY AGAIN'));
    expect(retried, 1);
  });

  testWidgets('one unsent purchase is said in the singular (pilot F4)', (tester) async {
    await tester.pumpWidget(wrap(BuyingOffScreen(onRetry: () {}, onSignOut: () {}, unsent: 1)));
    expect(find.text('1 purchase not sent yet stays on this phone. It can be sent if buying is turned on again.'), findsOneWidget);
  });

  testWidgets('opening the buying screens reads the projects and suppliers at once (pilot F1)', (tester) async {
    final api = FakePurchasingApi();
    await tester.pumpWidget(wrap(BuyerShell(
      buyer: staff,
      versionName: '0.7.1',
      onSignOut: () async {},
      account: account,
      purchasing: PurchasingServices(api: api),
    )));
    await tester.pumpAndSettle();
    expect(api.calls, contains('choices'), reason: 'so Record purchase has them later with no signal');
  });

  testWidgets('with no signal, opening the buying screens still works', (tester) async {
    final api = FakePurchasingApi()..error = StateError('offline');
    await tester.pumpWidget(wrap(BuyerShell(
      buyer: staff,
      versionName: '0.7.1',
      onSignOut: () async {},
      account: account,
      purchasing: PurchasingServices(api: api),
    )));
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);
    expect(find.text('My purchases'), findsOneWidget);
  });

  group('ticked items', () {
    late FakePurchasingApi api;

    setUp(() {
      api = FakePurchasingApi()
        ..shopping = ShoppingView(lines: [cement(portions: [portion('p1', buyer: 'u1', mine: true)])], batches: [thisWeek], fetchedAt: wednesday);
    });

    Future<void> open(WidgetTester tester) async {
      useTallPhone(tester);
      await tester.pumpWidget(wrap(BuyerShell(
        buyer: staff,
        versionName: '0.7.1',
        onSignOut: () async {},
        account: account,
        purchasing: PurchasingServices(api: api),
      )));
      await tester.pumpAndSettle();
    }

    testWidgets('hide the round Record purchase button while ticked (pilot F2)', (tester) async {
      await open(tester);
      expect(find.byKey(const Key('record-unplanned')), findsOneWidget);
      await tester.tap(find.byKey(const Key('pick-p1')));
      await tester.pumpAndSettle();
      expect(find.byKey(const Key('record-selected')), findsOneWidget);
      expect(find.byKey(const Key('record-unplanned')), findsNothing);
      await tester.tap(find.byKey(const Key('pick-p1')));
      await tester.pumpAndSettle();
      expect(find.byKey(const Key('record-unplanned')), findsOneWidget);
    });

    PurchaseDraft earlier() => PurchaseDraft(
          id: 'old',
          createdAt: wednesday,
          purchaseDate: '2026-10-21',
          supplierName: 'ZZ Hardware',
          lines: const [DraftPurchaseLine(key: 'k0', itemName: 'Cement', requestLineId: 'l1', quantity: '10')],
        );

    String supplierTyped(WidgetTester tester) => tester
        .widget<EditableText>(find.descendant(of: find.byKey(const Key('supplier-name')), matching: find.byType(EditableText)))
        .controller
        .text;

    Future<void> recordTicked(WidgetTester tester) async {
      await tester.tap(find.byKey(const Key('pick-p1')));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const Key('record-selected')));
      await tester.pumpAndSettle();
    }

    testWidgets('no earlier draft with the item: straight to a new purchase', (tester) async {
      await open(tester);
      await recordTicked(tester);
      expect(find.byKey(const Key('same-items-dialog')), findsNothing);
      expect(find.byKey(const Key('record-form')), findsOneWidget);
    });

    testWidgets('an earlier draft has the item: Continue it opens that draft (pilot F3)', (tester) async {
      api.draftList = [earlier()];
      await open(tester);
      await recordTicked(tester);
      expect(find.byKey(const Key('same-items-dialog')), findsOneWidget);
      expect(find.textContaining('ZZ Hardware · 1 item · not sent.'), findsOneWidget);
      await tester.tap(find.byKey(const Key('same-items-continue')));
      await tester.pumpAndSettle();
      expect(find.byKey(const Key('record-form')), findsOneWidget);
      expect(supplierTyped(tester), 'ZZ Hardware', reason: 'the earlier draft, supplier and all');
    });

    testWidgets('Start a new one opens a new purchase; closing the question opens nothing', (tester) async {
      api.draftList = [earlier()];
      await open(tester);
      await recordTicked(tester);
      await tester.tap(find.byKey(const Key('same-items-new')));
      await tester.pumpAndSettle();
      expect(find.byKey(const Key('record-form')), findsOneWidget);
      expect(supplierTyped(tester), '');
      await tester.pageBack();
      await tester.pumpAndSettle();

      await recordTicked(tester);
      await tester.tapAt(const Offset(5, 5)); // outside the question
      await tester.pumpAndSettle();
      expect(find.byKey(const Key('same-items-dialog')), findsNothing);
      expect(find.byKey(const Key('record-form')), findsNothing);
    });
  });

  testWidgets('with nothing unsent, no unsent line', (tester) async {
    await tester.pumpWidget(wrap(BuyingOffScreen(onRetry: () {}, onSignOut: () {})));
    expect(find.byKey(const Key('buying-off-unsent')), findsNothing);
  });

  testWidgets('the gate screen keeps its Terms words by default and takes the buying ones', (tester) async {
    await tester.pumpWidget(wrap(GateUnavailableScreen(onRetry: () {}, onSignOut: () {})));
    expect(find.text('Connect to the internet once so WorkMate can check your Terms.'), findsOneWidget);
    await tester.pumpWidget(wrap(GateUnavailableScreen(
      onRetry: () {},
      onSignOut: () {},
      title: 'Buying',
      english: 'Connect to the internet once so WorkMate can check your account.',
      tagalog: 'Kumonekta muna sa internet para ma-check ng WorkMate ang account mo.',
    )));
    expect(find.text('Buying'), findsOneWidget);
    expect(find.text('Connect to the internet once so WorkMate can check your account.'), findsOneWidget);
  });
}
