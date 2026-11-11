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

  Future<void> show(WidgetTester tester, Widget w) async {
    useTallPhone(tester);
    await tester.pumpWidget(wrap(w));
    await tester.pumpAndSettle();
  }

  testWidgets('fixed: Agreed, Paid so far, Balance; project progress, labelled as the project’s', (tester) async {
    remote.answers.add(all());
    await c.refresh();
    await show(tester, AgreementsScreen(controller: c));
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
    await show(tester, AgreementsScreen(controller: c));
    final tile = find.byKey(const Key('agreement-a-aw'));
    expect(find.descendant(of: tile, matching: find.text('Additional Works of Alpha House')), findsOneWidget);
    expect(find.descendant(of: tile, matching: find.text('Overall project progress: 80.0%')), findsOneWidget);
  });

  testWidgets('daily: Paid so far only, no agreed total and no balance; ended and completed are shown', (tester) async {
    remote.answers.add(all());
    await c.refresh();
    await show(tester, AgreementsScreen(controller: c));
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
    await show(tester, AgreementsScreen(controller: c));
    final tile = find.byKey(const Key('agreement-a-over'));
    expect(find.descendant(of: tile, matching: find.text('Over by')), findsOneWidget);
    expect(find.descendant(of: tile, matching: find.text('₱500.00')), findsOneWidget);
    expect(find.descendant(of: tile, matching: find.textContaining('100')), findsNothing);
  });

  testWidgets('the detail lists the works and each payment as date · method · amount', (tester) async {
    remote.answers.add(all());
    await c.refresh();
    await show(tester, AgreementDetailScreen(controller: c, agreementId: 'a-main'));
    expect(find.text('8 Oct 2026 · GCash'), findsOneWidget);
    expect(find.text('1 Oct 2026 · Cash'), findsOneWidget);
    await show(tester, AgreementDetailScreen(controller: c, agreementId: 'a-aw'));
    expect(find.text('1. Wall'), findsOneWidget);
    expect(find.text('2. Coping'), findsOneWidget);
    expect(find.text('No payments recorded yet.'), findsOneWidget);
  });

  testWidgets('a payment date saved with its time (or with none) still reads as its day', (tester) async {
    // Project Control saves a payment's date with the time, "2026-11-09T13:07"
    // (Manila wall-clock): 241 of 243 real contract payments on 10 Nov 2026.
    // The pilot's detail showed that raw text. A late-evening time keeps its own
    // day, and an empty date reads as a dash.
    remote.answers.add([
      MyAgreement.fromJson(Map<String, dynamic>.from(jsonDecode('''
        {"id": "a-time", "project": "Alpha House", "main_project": null, "project_completed": false, "progress_pct": null,
         "scope": "Glass", "trade": "", "pay_basis": "fixed", "works": [], "agreed": 1000, "paid": 300, "balance": 700,
         "ended": false, "ended_at": null,
         "payments": [{"date": "2026-11-09T13:07", "amount": 100, "method": "gcash"},
                      {"date": "2026-11-08T23:45", "amount": 100, "method": "cash"},
                      {"date": "", "amount": 100, "method": "gcash"}]}''') as Map)),
    ]);
    await c.refresh();
    await show(tester, AgreementDetailScreen(controller: c, agreementId: 'a-time'));
    expect(find.text('9 Nov 2026 · GCash'), findsOneWidget);
    expect(find.text('8 Nov 2026 · Cash'), findsOneWidget);
    expect(find.text('— · GCash'), findsOneWidget);
    expect(find.textContaining('T13:07'), findsNothing);
    expect(find.textContaining('T23:45'), findsNothing);
  });

  testWidgets('no signal on refresh: every amount leaves the screen, and it says it needs signal', (tester) async {
    remote.answers.add(all());
    await c.refresh();
    await show(tester, AgreementsScreen(controller: c));
    expect(find.textContaining('₱'), findsWidgets);
    remote.answers.add(noSignal);
    await c.refresh();
    await tester.pumpAndSettle();
    expect(find.textContaining('₱'), findsNothing);
    expect(find.textContaining('Needs signal to show your agreements'), findsOneWidget);
  });

  testWidgets('an open agreement that is unlinked shows no amount any more', (tester) async {
    remote.answers.add(all());
    await c.refresh();
    await show(tester, AgreementDetailScreen(controller: c, agreementId: 'a-main'));
    expect(find.text('₱50,000.00'), findsOneWidget);
    remote.answers.add(all().where((a) => a.id != 'a-main').toList());
    await c.refresh();
    await tester.pumpAndSettle();
    expect(find.textContaining('₱'), findsNothing);
    expect(find.textContaining('isn’t shown to you any more'), findsOneWidget);
  });

  testWidgets('reopened with no signal: no old figure while checking, and none after', (tester) async {
    remote.answers.add(all());
    await c.refresh();
    await show(tester, AgreementsScreen(controller: c));
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
    remote.answers.add(all());
    await c.refresh();
    await show(tester, AgreementDetailScreen(controller: c, agreementId: 'a-main'));
    expect(find.text('₱50,000.00'), findsOneWidget);
    remote.gate = Completer<void>();
    remote.answers.add(all().where((a) => a.id != 'a-main').toList());
    final pending = c.refresh();
    await tester.pump();
    expect(find.textContaining('₱'), findsNothing);
    expect(find.textContaining('Checking your agreements'), findsOneWidget);
    expect(find.textContaining('isn’t shown to you any more'), findsNothing, reason: 'not before the answer');
    remote.gate!.complete();
    await pending;
    await tester.pumpAndSettle();
    expect(find.textContaining('₱'), findsNothing);
    expect(find.textContaining('isn’t shown to you any more'), findsOneWidget);
  });

  testWidgets('a switched-off account sees why, and no amount', (tester) async {
    remote.answers.addAll([all(), notRequester]);
    await c.refresh();
    await show(tester, AgreementsScreen(controller: c));
    await c.refresh();
    await tester.pumpAndSettle();
    expect(find.textContaining('₱'), findsNothing);
    expect(find.textContaining('for workers and team leaders'), findsOneWidget);
  });
}
