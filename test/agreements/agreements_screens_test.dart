import 'dart:async';
import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:workmate/agreements/domain/my_agreement.dart';
import 'package:workmate/agreements/ui/agreements_controller.dart';
import 'package:workmate/agreements/ui/agreements_copy.dart';
import 'package:workmate/agreements/ui/agreements_screen.dart';
import 'package:workmate/ui/theme.dart';

import '../attendance/fakes.dart' show useTallPhone;
import 'agreement_fakes.dart';

Widget wrap(Widget w) => MaterialApp(theme: workMateTheme(), home: w);
List<MyAgreement> all() => [
      for (final a in (jsonDecode(myAgreementsJson)['agreements'] as List)) MyAgreement.fromJson(Map<String, dynamic>.from(a as Map)),
    ];

MyAgreement one(Map<String, dynamic> over) => MyAgreement.fromJson({
      'id': 'x',
      'project': 'Delta House',
      'main_project': null,
      'project_completed': false,
      'progress_pct': null,
      'scope': 'Roofing',
      'trade': '',
      'pay_basis': 'fixed',
      'works': <String>[],
      'agreed': 1000,
      'paid': 0,
      'balance': 1000,
      'ended': false,
      'ended_at': null,
      ...over,
    });

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

  Future<void> openTab(WidgetTester tester, String id) async {
    final tab = find.byKey(Key('agreement-tab-$id'));
    await tester.ensureVisible(tab);
    await tester.pumpAndSettle();
    await tester.tap(tab);
    await tester.pumpAndSettle();
  }

  Finder inView(String id, Finder f) => find.descendant(of: find.byKey(Key('agreement-$id')), matching: f);

  /// The 0115 sample with works on the main agreement too.
  List<MyAgreement> withMainWorks() => [
        for (final a in (jsonDecode(myAgreementsJson)['agreements'] as List))
          MyAgreement.fromJson({
            ...Map<String, dynamic>.from(a as Map),
            if (a['id'] == 'a-main') 'works': ['Footing'],
          }),
      ];

  testWidgets('one tab per agreement; the first is open; Agreed, Paid so far, Balance and the paid ring', (tester) async {
    remote.answers.add(all());
    await c.refresh();
    await openSheet(tester);
    for (final id in ['a-main', 'a-aw', 'a-daily', 'a-over']) {
      expect(find.byKey(Key('agreement-tab-$id')), findsOneWidget);
    }
    expect(find.byKey(const Key('agreement-a-main')), findsOneWidget, reason: 'the first agreement is open');
    expect(find.byKey(const Key('agreement-a-aw')), findsNothing, reason: 'one agreement at a time');
    expect(inView('a-main', find.text('₱50,000.00')), findsOneWidget);
    expect(inView('a-main', find.text('₱20,000.00')), findsOneWidget);
    expect(inView('a-main', find.text('Balance')), findsOneWidget);
    expect(inView('a-main', find.text('₱30,000.00')), findsOneWidget);
    expect(inView('a-main', find.text('40%')), findsOneWidget);
    expect(inView('a-main', find.text('Overall project progress: 25.0%')), findsOneWidget);
    // The footnote closes the list, under the agreement.
    await tester.scrollUntilVisible(find.textContaining('Payments are the company’s records'), 300,
        scrollable: inView('a-main', find.byType(Scrollable)).first);
    expect(find.textContaining('Payments are the company’s records'), findsOneWidget);
    expect(find.text('Updated 10:30 AM'), findsOneWidget);
  });

  testWidgets('Additional Works names its main project and shows its OWN progress', (tester) async {
    remote.answers.add(all());
    await c.refresh();
    await openSheet(tester);
    await openTab(tester, 'a-aw');
    expect(inView('a-aw', find.text('Additional Works of Alpha House')), findsOneWidget);
    expect(inView('a-aw', find.text('Overall project progress: 80.0%')), findsOneWidget);
  });

  testWidgets('daily: Paid so far only, no agreed total, ring or balance; ended and completed are shown', (tester) async {
    remote.answers.add(all());
    await c.refresh();
    await openSheet(tester);
    await openTab(tester, 'a-daily');
    expect(inView('a-daily', find.text('Paid so far')), findsOneWidget);
    expect(inView('a-daily', find.text('₱700.00')), findsOneWidget);
    expect(inView('a-daily', find.text('No agreed total — paid by the day.')), findsOneWidget);
    expect(inView('a-daily', find.text('Agreed')), findsNothing);
    expect(inView('a-daily', find.text('Balance')), findsNothing);
    expect(inView('a-daily', find.byKey(const Key('agreement-ring'))), findsNothing);
    expect(inView('a-daily', find.text('Daily basis')), findsOneWidget);
    expect(inView('a-daily', find.text('Ended 3 Nov 2026')), findsOneWidget);
    expect(inView('a-daily', find.text('Project completed')), findsOneWidget);
    expect(inView('a-daily', find.textContaining('Progress not recorded yet')), findsOneWidget);
  });

  testWidgets('paid over the agreed amount reads "Over by" with the note, and no progress is never 100%', (tester) async {
    remote.answers.add(all());
    await c.refresh();
    await openSheet(tester);
    await openTab(tester, 'a-over');
    expect(inView('a-over', find.text('Over by')), findsOneWidget);
    expect(inView('a-over', find.text('₱500.00')), findsOneWidget);
    expect(inView('a-over', find.text('150%')), findsOneWidget);
    expect(inView('a-over', find.byKey(const Key('agreement-over-note'))), findsOneWidget);
    expect(inView('a-over', find.textContaining('Paid more than the agreed amount')), findsOneWidget);
    expect(inView('a-over', find.textContaining('100')), findsNothing);
    await openTab(tester, 'a-main');
    expect(find.byKey(const Key('agreement-over-note')), findsNothing, reason: 'only an overpaid agreement has the note');
  });

  /// No payment list in any tab (owner decision 17 Nov 2026).
  void expectNoPaymentList() {
    expect(find.text('Payments'), findsNothing);
    expect(find.textContaining('No payments recorded'), findsNothing);
    expect(find.textContaining('GCash'), findsNothing);
    expect(find.textContaining('Bank'), findsNothing);
    expect(find.textContaining(' · Cash'), findsNothing);
    expect(find.textContaining('Oct 2026 ·'), findsNothing);
  }

  testWidgets('no payment list in any tab; the works covered are listed', (tester) async {
    remote.answers.add(all());
    await c.refresh();
    await openSheet(tester);
    for (final id in ['a-main', 'a-aw', 'a-daily', 'a-over']) {
      await openTab(tester, id);
      expectNoPaymentList();
    }
    await openTab(tester, 'a-aw');
    final works = find.byKey(const Key('agreement-works'));
    expect(find.descendant(of: works, matching: find.text('WORKS COVERED')), findsOneWidget); // drawn in capitals
    expect(find.descendant(of: works, matching: find.text('1.')), findsOneWidget);
    expect(find.descendant(of: works, matching: find.text('Wall')), findsOneWidget);
    expect(find.descendant(of: works, matching: find.text('2.')), findsOneWidget);
    expect(find.descendant(of: works, matching: find.text('Coping')), findsOneWidget);
  });

  testWidgets('an agreement with no works shows no works card', (tester) async {
    remote.answers.add(all());
    await c.refresh();
    await openSheet(tester);
    for (final id in ['a-main', 'a-daily', 'a-over']) {
      await openTab(tester, id);
      expect(find.byKey(const Key('agreement-works')), findsNothing, reason: '$id has no works');
    }
  });

  testWidgets('a 0113 answer that still carries payments draws no list', (tester) async {
    remote.answers.add([
      for (final a in (jsonDecode(legacyAgreementsJson)['agreements'] as List))
        MyAgreement.fromJson({
          ...Map<String, dynamic>.from(a as Map),
          if (a['id'] == 'a-main') 'works': ['Footing'], // works AND a payment list
        }),
    ]);
    await c.refresh();
    await openSheet(tester);
    expect(inView('a-main', find.text('Footing')), findsOneWidget, reason: 'the agreement is open');
    expectNoPaymentList();
    expect(find.text('₱10,000.00'), findsNothing); // a single payment's amount
    expect(inView('a-main', find.text('₱20,000.00')), findsOneWidget); // Paid so far stays
  });

  testWidgets('paid in full reads Balance ₱0.00 and 100% paid', (tester) async {
    remote.answers.add([
      one({'id': 'a-full', 'progress_pct': 100, 'agreed': 2000, 'paid': 2000, 'balance': 0}),
    ]);
    await c.refresh();
    await openSheet(tester);
    expect(inView('a-full', find.text('Balance')), findsOneWidget);
    expect(inView('a-full', find.text('₱0.00')), findsOneWidget);
    expect(inView('a-full', find.text('100%')), findsOneWidget);
    expect(inView('a-full', find.text('Over by')), findsNothing);
  });

  testWidgets('no signal on refresh: every amount and tab leaves the screen, it says why, and Try again asks again', (tester) async {
    remote.answers.add(all());
    await c.refresh();
    await openSheet(tester);
    expect(find.textContaining('₱'), findsWidgets);
    remote.answers.add(noSignal);
    await c.refresh();
    await tester.pumpAndSettle();
    expect(find.textContaining('₱'), findsNothing);
    expect(find.byKey(const Key('agreement-tab-a-main')), findsNothing);
    expect(find.textContaining('Needs signal to show your agreements'), findsOneWidget);
    expect(find.text('Nothing is saved on this phone.'), findsOneWidget);
    remote.answers.add(all());
    await tester.tap(find.byKey(const Key('agreements-retry')));
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('agreement-a-main')), findsOneWidget, reason: 'the read came back');
  });

  testWidgets('an open agreement that is unlinked shows no amount any more; the other tabs stay, none open', (tester) async {
    remote.answers.add(withMainWorks());
    await c.refresh();
    await openSheet(tester);
    expect(find.text('₱50,000.00'), findsOneWidget);
    remote.answers.add(withMainWorks().where((a) => a.id != 'a-main').toList());
    await c.refresh();
    await tester.pumpAndSettle();
    expect(find.text('₱50,000.00'), findsNothing, reason: 'the unlinked agreement’s figures are gone');
    expect(find.text('₱30,000.00'), findsNothing);
    expect(find.textContaining('₱'), findsNothing, reason: 'no agreement is open');
    expect(find.byKey(const Key('agreement-a-main')), findsNothing);
    expect(find.byKey(const Key('agreement-tab-a-main')), findsNothing);
    expect(find.byKey(const Key('agreement-gone')), findsOneWidget);
    expect(find.textContaining('isn’t shown to you any more'), findsOneWidget);
    for (final id in ['a-aw', 'a-daily', 'a-over']) {
      expect(find.byKey(Key('agreement-tab-$id')), findsOneWidget, reason: 'the other tabs stay');
    }
    await openTab(tester, 'a-aw');
    expect(find.byKey(const Key('agreement-a-aw')), findsOneWidget, reason: 'another tab opens');
    expect(find.textContaining('isn’t shown to you any more'), findsNothing);
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
    expect(find.byKey(const Key('agreements-checking')), findsOneWidget);
    expect(find.textContaining('Checking your agreements'), findsOneWidget);
    remote.gate!.complete();
    await pending;
    await tester.pumpAndSettle();
    expect(find.textContaining('₱'), findsNothing);
    expect(find.textContaining('Needs signal to show your agreements'), findsOneWidget);
  });

  testWidgets('an open agreement shows no figure while checking, and says so when it was unlinked', (tester) async {
    remote.answers.add(withMainWorks());
    await c.refresh();
    await openSheet(tester);
    await openTab(tester, 'a-main');
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
    expect(find.byKey(const Key('agreement-a-main')), findsNothing);
    expect(find.textContaining('isn’t shown to you any more'), findsOneWidget);
  });

  testWidgets('another open tab survives a refresh that still has it', (tester) async {
    remote.answers.add(all());
    await c.refresh();
    await openSheet(tester);
    await openTab(tester, 'a-over');
    remote.answers.add(all());
    await c.refresh();
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('agreement-a-over')), findsOneWidget);
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

  testWidgets('an app too old to be answered says to update, with no Try again', (tester) async {
    remote.answers.add(Exception('PostgrestException(message: APP_UPDATE_REQUIRED, code: P0001)'));
    await openSheet(tester);
    expect(find.text('Update WorkMate to see your agreements.'), findsOneWidget);
    expect(find.byKey(const Key('agreements-retry')), findsNothing);
    expect(find.textContaining('₱'), findsNothing);
  });

  testWidgets('no agreement linked: says so, with no tab and no amount', (tester) async {
    remote.answers.add(const <MyAgreement>[]);
    await openSheet(tester);
    expect(find.byKey(const Key('agreements-none')), findsOneWidget);
    expect(find.text('No agreements are linked to your account yet.'), findsOneWidget);
    expect(find.byKey(const Key('agreement-tabs')), findsNothing);
    expect(find.textContaining('₱'), findsNothing);
  });

  testWidgets('the sheet is the one place: key, title, Tagalog subtitle, and it closes with its ×', (tester) async {
    remote.answers.add(all());
    await c.refresh();
    await openSheet(tester);
    expect(find.byKey(const Key('agreements-sheet')), findsOneWidget);
    expect(find.text('My agreements'), findsOneWidget);
    expect(find.text('Mga kasunduan ko'), findsOneWidget);
    expect(find.byKey(const Key('wm-sheet-close')), findsOneWidget);
    await tester.tap(find.byKey(const Key('wm-sheet-close')));
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('agreements-sheet')), findsNothing);
  });

  testWidgets('a tab opens its agreement in place; the one before closes', (tester) async {
    remote.answers.add(withMainWorks());
    await c.refresh();
    await openSheet(tester);
    expect(find.text('Footing'), findsOneWidget, reason: 'the first agreement is open');
    await openTab(tester, 'a-aw');
    expect(find.byKey(const Key('agreements-sheet')), findsOneWidget, reason: 'still the sheet, no second page');
    expect(find.text('Footing'), findsNothing, reason: 'the first agreement closed');
    expect(find.text('Wall'), findsOneWidget);
    expect(tester.getSemantics(find.byKey(const Key('agreement-tab-a-aw'))), containsSemantics(isButton: true, isSelected: true));
    expect(tester.getSemantics(find.byKey(const Key('agreement-tab-a-main'))), containsSemantics(isButton: true, isSelected: false));
  });

  testWidgets('an open agreement that disappears collapses without an error and says so', (tester) async {
    remote.answers.add(withMainWorks());
    await c.refresh();
    await openSheet(tester);
    expect(find.text('Footing'), findsOneWidget);
    remote.answers.add(withMainWorks().where((a) => a.id != 'a-main').toList());
    await c.refresh();
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);
    expect(find.byKey(const Key('agreement-a-main')), findsNothing);
    expect(find.text('Footing'), findsNothing);
    expect(find.textContaining('isn’t shown to you any more'), findsOneWidget);
    expect(find.byKey(const Key('agreement-tab-a-aw')), findsOneWidget, reason: 'the others stay');
  });

  testWidgets('the read failing at open: no amount, the notice and its retry', (tester) async {
    remote.answers.add(noSignal);
    await openSheet(tester);
    expect(find.textContaining('₱'), findsNothing);
    expect(find.byKey(const Key('agreements-notice')), findsOneWidget);
    expect(find.textContaining('Needs signal to show your agreements'), findsOneWidget);
    expect(find.byKey(const Key('agreements-retry')), findsOneWidget);
  });

  group('tab labels', () {
    test('a project with one agreement is named alone', () {
      expect(agreementTabLabels(all()), {
        'a-main': 'Alpha House',
        'a-aw': 'Alpha Additional Works',
        'a-daily': 'Beta House',
        'a-over': 'Gamma House',
      });
    });

    test('two on one project add the trade, or the job without one', () {
      final labels = agreementTabLabels([
        one({'id': 't', 'project': 'De Leon Residence', 'scope': 'Tiling Works', 'trade': 'Tiling'}),
        one({'id': 'p', 'project': 'De Leon Residence', 'scope': 'Painting Works', 'trade': ''}),
      ]);
      expect(labels, {'t': 'De Leon Residence · Tiling', 'p': 'De Leon Residence · Painting Works'});
    });

    test('alike trades fall back to the job, and anything still alike is numbered', () {
      final labels = agreementTabLabels([
        one({'id': 'a', 'project': 'Crossroad', 'scope': 'Walls', 'trade': 'Masonry'}),
        one({'id': 'b', 'project': 'Crossroad', 'scope': 'Fence', 'trade': 'Masonry'}),
        one({'id': 'c', 'project': 'Crossroad', 'scope': 'Fence', 'trade': 'Masonry'}),
      ]);
      expect(labels['a'], 'Crossroad · Walls');
      expect(labels['b'], 'Crossroad · Fence (1)');
      expect(labels['c'], 'Crossroad · Fence (2)');
      expect(labels.values.toSet().length, 3);
    });
  });

  group('paid ring percent', () {
    test('reads 100% only when paid equals agreed', () {
      expect(agreementPaidPercent(one({'agreed': 1000, 'paid': 999.9, 'balance': 0.1})), 99);
      expect(agreementPaidPercent(one({'agreed': 1000, 'paid': 1000, 'balance': 0})), 100);
      expect(agreementPaidPercent(one({'agreed': 1000, 'paid': 1000.1, 'balance': -0.1})), 101);
      expect(agreementPaidPercent(one({'agreed': 30000, 'paid': 43500, 'balance': -13500})), 145);
    });

    test('none for daily or with no agreed amount', () {
      expect(agreementPaidPercent(one({'pay_basis': 'daily', 'agreed': null, 'paid': 700, 'balance': null})), isNull);
      expect(agreementPaidPercent(one({'agreed': 0, 'paid': 0, 'balance': 0})), isNull);
      expect(agreementPaidPercent(one({'agreed': null, 'paid': 10, 'balance': null})), isNull);
    });
  });
}
