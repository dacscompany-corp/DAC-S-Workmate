import 'dart:async';
import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:workmate/agreements/domain/my_agreement.dart';
import 'package:workmate/agreements/ui/agreements_controller.dart';
import 'package:workmate/agreements/ui/agreements_screen.dart';
import 'package:workmate/ui/theme.dart';

import '../attendance/fakes.dart' show useTallPhone;
import 'agreement_fakes.dart';

Widget wrap(Widget w) => MaterialApp(theme: workMateTheme(), home: w);
List<MyAgreement> all() => [
      for (final a in (jsonDecode(myAgreementsJson)['agreements'] as List)) MyAgreement.fromJson(Map<String, dynamic>.from(a as Map)),
    ];

void main() {
  late FakeAgreementsRemote remote;
  late AgreementsController c;

  setUp(() {
    remote = FakeAgreementsRemote();
    c = AgreementsController(remote: remote, userId: 'w13', now: () => DateTime.utc(2026, 11, 8, 2, 30));
  });

  /// Opens My agreements as a sheet over a plain page (as from Home).
  Future<void> openSheet(WidgetTester tester) async {
    useTallPhone(tester);
    // The sheet reads again as it opens: serve it what is on the controller now.
    if (remote.answers.isEmpty) remote.answers.add(c.agreements);
    await tester.pumpWidget(const SizedBox()); // a fresh app: any earlier sheet is gone
    await tester.pumpWidget(wrap(Builder(
      builder: (context) => Center(
        child: ElevatedButton(
          key: const Key('open-agreements'),
          onPressed: () => showAgreementsSheet(context, c),
          child: const Text('Open'),
        ),
      ),
    )));
    await tester.tap(find.byKey(const Key('open-agreements')));
    await tester.pumpAndSettle();
  }

  Future<void> openCard(WidgetTester tester, String id) async {
    await tester.ensureVisible(find.byKey(Key('agreement-$id'), skipOffstage: false));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(Key('agreement-$id')));
    await tester.pumpAndSettle();
  }

  /// The 0115 sample with works on the main agreement too, so two cards can open.
  List<MyAgreement> withMainWorks() => [
        for (final a in (jsonDecode(myAgreementsJson)['agreements'] as List))
          MyAgreement.fromJson({
            ...Map<String, dynamic>.from(a as Map),
            if (a['id'] == 'a-main') 'works': ['Footing'],
          }),
      ];

  testWidgets('fixed: Agreed, Paid so far, Balance; project progress, labelled as the project’s', (tester) async {
    remote.answers.add(all());
    await c.refresh();
    await openSheet(tester);
    final tile = find.byKey(const Key('agreement-a-main'));
    expect(find.descendant(of: tile, matching: find.text('₱50,000.00')), findsOneWidget);
    expect(find.descendant(of: tile, matching: find.text('₱20,000.00')), findsOneWidget);
    expect(find.descendant(of: tile, matching: find.text('Balance')), findsOneWidget);
    expect(find.descendant(of: tile, matching: find.text('₱30,000.00')), findsOneWidget);
    expect(find.descendant(of: tile, matching: find.text('Overall project progress: 25.0%')), findsOneWidget);
    // The footnote closes the list, under every agreement.
    await tester.scrollUntilVisible(find.textContaining('Payments are the company’s records'), 300);
    expect(find.textContaining('Payments are the company’s records'), findsOneWidget);
  });

  testWidgets('Additional Works names its main project and shows its OWN progress', (tester) async {
    remote.answers.add(all());
    await c.refresh();
    await openSheet(tester);
    final tile = find.byKey(const Key('agreement-a-aw'));
    expect(find.descendant(of: tile, matching: find.text('Additional Works of Alpha House')), findsOneWidget);
    expect(find.descendant(of: tile, matching: find.text('Overall project progress: 80.0%')), findsOneWidget);
  });

  testWidgets('daily: Paid so far only, no agreed total and no balance; ended and completed are shown', (tester) async {
    remote.answers.add(all());
    await c.refresh();
    await openSheet(tester);
    final tile = find.byKey(const Key('agreement-a-daily'));
    expect(find.descendant(of: tile, matching: find.text('Paid so far')), findsOneWidget);
    expect(find.descendant(of: tile, matching: find.text('Agreed')), findsNothing);
    expect(find.descendant(of: tile, matching: find.text('Balance')), findsNothing);
    expect(find.descendant(of: tile, matching: find.text('Daily basis')), findsOneWidget);
    expect(find.descendant(of: tile, matching: find.text('Ended 3 Nov 2026')), findsOneWidget);
    expect(find.descendant(of: tile, matching: find.text('Project completed')), findsOneWidget);
    expect(find.descendant(of: tile, matching: find.textContaining('Progress not recorded yet')), findsOneWidget);
  });

  testWidgets('paid over the agreed amount reads "Over by", and no progress is never 100%', (tester) async {
    remote.answers.add(all());
    await c.refresh();
    await openSheet(tester);
    await tester.scrollUntilVisible(find.byKey(const Key('agreement-a-over')), 200, scrollable: find.byType(Scrollable).first);
    final tile = find.byKey(const Key('agreement-a-over'));
    expect(find.descendant(of: tile, matching: find.text('Over by')), findsOneWidget);
    expect(find.descendant(of: tile, matching: find.text('₱500.00')), findsOneWidget);
    expect(find.descendant(of: tile, matching: find.textContaining('100')), findsNothing);
  });

  /// No payment list on a card, closed or opened (owner decision 17 Nov 2026).
  void expectNoPaymentList() {
    expect(find.text('Payments'), findsNothing);
    expect(find.textContaining('No payments recorded'), findsNothing);
    expect(find.textContaining('GCash'), findsNothing);
    expect(find.textContaining('Bank'), findsNothing);
    expect(find.textContaining(' · Cash'), findsNothing);
    expect(find.textContaining('Oct 2026 ·'), findsNothing);
  }

  testWidgets('no payment list on any card, closed or opened; the works stay', (tester) async {
    remote.answers.add(all());
    await c.refresh();
    await openSheet(tester);
    expectNoPaymentList();
    for (final id in ['a-main', 'a-aw', 'a-daily', 'a-over']) {
      await openSheet(tester);
      await openCard(tester, id);
      expectNoPaymentList();
    }
    await openSheet(tester);
    await openCard(tester, 'a-aw');
    expect(find.text('WORKS COVERED'), findsOneWidget); // the label is drawn in capitals
    expect(find.text('1. Wall'), findsOneWidget);
    expect(find.text('2. Coping'), findsOneWidget);
  });

  testWidgets('a 0113 answer that still carries payments draws no list', (tester) async {
    remote.answers.add([
      for (final a in (jsonDecode(legacyAgreementsJson)['agreements'] as List))
        MyAgreement.fromJson({
          ...Map<String, dynamic>.from(a as Map),
          if (a['id'] == 'a-main') 'works': ['Footing'], // so the card opens: works AND a payment list
        }),
    ]);
    await c.refresh();
    await openSheet(tester);
    await openCard(tester, 'a-main');
    expect(find.text('1. Footing'), findsOneWidget, reason: 'the card is open');
    expectNoPaymentList();
    expect(find.text('₱10,000.00'), findsNothing); // a single payment's amount
    final tile = find.byKey(const Key('agreement-a-main'));
    expect(find.descendant(of: tile, matching: find.text('₱20,000.00')), findsOneWidget); // Paid so far stays
  });

  testWidgets('paid in full reads Balance ₱0.00', (tester) async {
    remote.answers.add([
      MyAgreement.fromJson(Map<String, dynamic>.from(jsonDecode('''
        {"id": "a-full", "project": "Delta House", "main_project": null, "project_completed": false, "progress_pct": 100,
         "scope": "Roofing", "trade": "", "pay_basis": "fixed", "works": [], "agreed": 2000, "paid": 2000, "balance": 0,
         "ended": false, "ended_at": null}''') as Map)),
    ]);
    await c.refresh();
    await openSheet(tester);
    final tile = find.byKey(const Key('agreement-a-full'));
    expect(find.descendant(of: tile, matching: find.text('Balance')), findsOneWidget);
    expect(find.descendant(of: tile, matching: find.text('₱0.00')), findsOneWidget);
    expect(find.descendant(of: tile, matching: find.text('Over by')), findsNothing);
  });

  testWidgets('no signal on refresh: every amount leaves the screen, and it says it needs signal', (tester) async {
    remote.answers.add(all());
    await c.refresh();
    await openSheet(tester);
    expect(find.textContaining('₱'), findsWidgets);
    remote.answers.add(noSignal);
    await c.refresh();
    await tester.pumpAndSettle();
    expect(find.textContaining('₱'), findsNothing);
    expect(find.textContaining('Needs signal to show your agreements'), findsOneWidget);
  });

  testWidgets('an open agreement that is unlinked shows no amount any more', (tester) async {
    remote.answers.add(withMainWorks());
    await c.refresh();
    await openSheet(tester);
    await openCard(tester, 'a-main');
    expect(find.text('1. Footing'), findsOneWidget, reason: 'the card is open');
    expect(find.text('₱50,000.00'), findsOneWidget);
    remote.answers.add(withMainWorks().where((a) => a.id != 'a-main').toList());
    await c.refresh();
    await tester.pumpAndSettle();
    expect(find.text('₱50,000.00'), findsNothing, reason: 'the unlinked agreement’s figures are gone (the others stay listed)');
    expect(find.text('₱30,000.00'), findsNothing);
    expect(find.byKey(const Key('agreement-a-main')), findsNothing, reason: 'its card is gone');
    expect(find.textContaining('isn’t shown to you any more'), findsOneWidget);
  });

  testWidgets('reopened with no signal: no old figure while checking, and none after', (tester) async {
    remote.answers.add(all());
    await c.refresh();
    await openSheet(tester);
    expect(find.textContaining('₱'), findsWidgets);
    remote.gate = Completer<void>();
    remote.answers.add(noSignal);
    final pending = c.refresh(); // what opening the screen again does
    await tester.pump();
    expect(find.textContaining('₱'), findsNothing);
    expect(find.textContaining('Checking your agreements'), findsOneWidget);
    remote.gate!.complete();
    await pending;
    await tester.pumpAndSettle();
    expect(find.textContaining('₱'), findsNothing);
    expect(find.textContaining('Needs signal to show your agreements'), findsOneWidget);
  });

  testWidgets('an open detail shows no figure while checking, and says so when it was unlinked', (tester) async {
    remote.answers.add(withMainWorks());
    await c.refresh();
    await openSheet(tester);
    await openCard(tester, 'a-main');
    expect(find.text('1. Footing'), findsOneWidget, reason: 'the card is open');
    expect(find.text('₱50,000.00'), findsOneWidget);
    remote.gate = Completer<void>();
    remote.answers.add(withMainWorks().where((a) => a.id != 'a-main').toList());
    final pending = c.refresh();
    await tester.pump();
    expect(find.textContaining('₱'), findsNothing);
    expect(find.textContaining('Checking your agreements'), findsOneWidget);
    expect(find.textContaining('isn’t shown to you any more'), findsNothing, reason: 'not before the answer');
    remote.gate!.complete();
    await pending;
    await tester.pumpAndSettle();
    expect(find.text('₱50,000.00'), findsNothing, reason: 'the unlinked agreement’s figures after the answer');
    expect(find.text('₱30,000.00'), findsNothing);
    expect(find.byKey(const Key('agreement-a-main')), findsNothing, reason: 'its card is gone');
    expect(find.textContaining('isn’t shown to you any more'), findsOneWidget);
  });

  testWidgets('a switched-off account sees why, and no amount', (tester) async {
    remote.answers.add(all());
    await c.refresh();
    await openSheet(tester);
    remote.answers.add(notRequester);
    await c.refresh();
    await tester.pumpAndSettle();
    expect(find.textContaining('₱'), findsNothing);
    expect(find.textContaining('for workers and team leaders'), findsOneWidget);
  });

  testWidgets('the sheet is the one place: key, title, Tagalog subtitle, and it opens on Back-able chrome', (tester) async {
    remote.answers.add(all());
    await c.refresh();
    await openSheet(tester);
    expect(find.byKey(const Key('agreements-sheet')), findsOneWidget);
    expect(find.text('My agreements'), findsOneWidget);
    expect(find.byKey(const Key('wm-sheet-close')), findsOneWidget);
    await tester.tap(find.byKey(const Key('wm-sheet-close')));
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('agreements-sheet')), findsNothing);
  });

  testWidgets('a card opens in place; opening a second one closes the first', (tester) async {
    remote.answers.add(withMainWorks());
    await c.refresh();
    await openSheet(tester);
    expect(find.text('1. Footing'), findsNothing, reason: 'closed cards show no works');
    await openCard(tester, 'a-main');
    expect(find.text('1. Footing'), findsOneWidget);
    expect(find.byKey(const Key('agreements-sheet')), findsOneWidget, reason: 'still the sheet, no second page');
    await openCard(tester, 'a-aw');
    expect(find.text('1. Footing'), findsNothing, reason: 'the first card closed');
    expect(find.text('1. Wall'), findsOneWidget);
    await openCard(tester, 'a-aw');
    expect(find.text('1. Wall'), findsNothing, reason: 'tapping the open card closes it');
  });

  testWidgets('a card with no works has no arrow and does not open', (tester) async {
    remote.answers.add(all());
    await c.refresh();
    await openSheet(tester);
    Finder inCard(String id, Finder f) => find.descendant(of: find.byKey(Key('agreement-$id')), matching: f);
    expect(inCard('a-aw', find.byIcon(Icons.expand_more)), findsOneWidget, reason: 'it has works to show');
    for (final id in ['a-main', 'a-daily', 'a-over']) {
      expect(inCard(id, find.byIcon(Icons.expand_more)), findsNothing, reason: '$id has nothing behind it');
      await openCard(tester, id);
      expect(find.byIcon(Icons.expand_less), findsNothing, reason: '$id did not open');
    }
  });

  testWidgets('an open agreement that disappears collapses without an error and says so', (tester) async {
    remote.answers.add(withMainWorks());
    await c.refresh();
    await openSheet(tester);
    await openCard(tester, 'a-main');
    expect(find.text('1. Footing'), findsOneWidget);
    remote.answers.add(withMainWorks().where((a) => a.id != 'a-main').toList());
    await c.refresh();
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);
    expect(find.byKey(const Key('agreement-a-main')), findsNothing);
    expect(find.text('1. Footing'), findsNothing);
    expect(find.textContaining('isn’t shown to you any more'), findsOneWidget);
    expect(find.byKey(const Key('agreement-a-aw')), findsOneWidget, reason: 'the others stay');
  });

  testWidgets('the read failing at open: no amount, the notice and its retry', (tester) async {
    remote.answers.add(noSignal);
    await openSheet(tester);
    expect(find.textContaining('₱'), findsNothing);
    expect(find.byKey(const Key('agreements-notice')), findsOneWidget);
    expect(find.textContaining('Needs signal to show your agreements'), findsOneWidget);
  });
}
