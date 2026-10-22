import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:workmate/purchasing/data/purchasing_api.dart';
import 'package:workmate/purchasing/domain/pur_models.dart';
import 'package:workmate/purchasing/domain/purchase_draft.dart';
import 'package:workmate/purchasing/list/shopping_controller.dart';
import 'package:workmate/purchasing/list/shopping_list_screen.dart';
import 'package:workmate/ui/theme.dart';

import '../../attendance/fakes.dart' show useTallPhone;
import '../purchasing_api_fake.dart';
import '../purchasing_fakes.dart';

Widget wrap(Widget w) => MaterialApp(theme: workMateTheme(), home: Scaffold(body: w));

void main() {
  late FakePurchasingApi api;
  late ShoppingController c;

  setUp(() {
    api = FakePurchasingApi();
    api.shopping = ShoppingView(batches: [thisWeek, nextWeek], fetchedAt: wednesday, lines: [
      ShoppingLine(
        lineId: 'l1',
        requestId: 'r1',
        description: 'Cement',
        spec: '40 kg',
        unit: 'bag',
        projectId: 'f1',
        projectName: 'Barlin Residence',
        workId: 'f1',
        workName: 'Main Contract',
        requesterName: 'Juan',
        urgent: true,
        neededBy: '2026-10-23',
        needed: 10,
        bought: 0,
        stillToBuy: 10,
        portions: [
          portion('p1', still: 6),
          const PurPortion(id: 'p2', batchId: 'b1', stillToBuy: 4, buyerId: 'u1', mine: true, changed: true),
          const PurPortion(id: 'p3', batchId: 'b1', stillToBuy: 2, buyerId: 'u9', buyerName: 'Ben'),
        ],
      ),
    ]);
    c = ShoppingController(api: api, now: () => wednesday);
  });

  testWidgets('sections and numbers in English with Tagalog under them (Q4, Q22)', (tester) async {
    useTallPhone(tester);
    await c.refresh();
    await tester.pumpWidget(wrap(ShoppingListScreen(controller: c)));
    expect(find.text('Mine'), findsOneWidget);
    expect(find.text('Akin'), findsOneWidget);
    expect(find.text('Unassigned'), findsOneWidget);
    expect(find.text('Still to buy'), findsWidgets);
    expect(find.text('Kulang pang bilhin'), findsWidgets);
    expect(find.text('Cement · 40 kg'), findsWidgets);
    expect(find.byKey(const Key('urgent-p1')), findsOneWidget);
    expect(find.text('Urgent · needed by 2026-10-23'), findsWidgets);
    expect(find.byKey(const Key('changed-p2')), findsOneWidget);
    expect(find.text('6 bag'), findsOneWidget);
    expect(find.textContaining('₱'), findsNothing, reason: 'no prices on the list (Q4)');
    await tester.scrollUntilVisible(find.text('Buying: Ben'), 300);
    expect(find.text('Other buyers'), findsOneWidget);
    expect(find.text('Ibang bibili'), findsOneWidget);
    expect(find.textContaining('₱'), findsNothing);
  });

  testWidgets('another buyer\'s portion is read-only', (tester) async {
    useTallPhone(tester);
    await c.refresh();
    await tester.pumpWidget(wrap(ShoppingListScreen(controller: c)));
    expect(find.byKey(const Key('claim-p3')), findsNothing);
    expect(find.byKey(const Key('release-p3')), findsNothing);
    expect(find.byKey(const Key('claim-p1')), findsOneWidget);
    expect(find.byKey(const Key('release-p2')), findsOneWidget);
    expect(find.byKey(const Key('arranged-p2')), findsOneWidget);
  });

  testWidgets('"I\'ll buy this": all by default, or part (Q5)', (tester) async {
    useTallPhone(tester);
    await c.refresh();
    await tester.pumpWidget(wrap(ShoppingListScreen(controller: c)));
    await tester.tap(find.byKey(const Key('claim-p1')));
    await tester.pumpAndSettle();
    await tester.enterText(find.byKey(const Key('claim-qty')), '7');
    await tester.tap(find.byKey(const Key('claim-confirm')));
    await tester.pumpAndSettle();
    expect(find.text('Enter up to 6 bag.'), findsOneWidget, reason: 'never more than is still to buy');
    await tester.enterText(find.byKey(const Key('claim-qty')), '4');
    await tester.tap(find.byKey(const Key('claim-confirm')));
    await tester.pumpAndSettle();
    expect(api.calls, contains('claim:p1:4.0'));
  });

  testWidgets('Mark arranged on my own portion (Q6)', (tester) async {
    useTallPhone(tester);
    await c.refresh();
    await tester.pumpWidget(wrap(ShoppingListScreen(controller: c)));
    await tester.tap(find.byKey(const Key('arranged-p2')));
    await tester.pumpAndSettle();
    expect(api.calls, contains('arranged:p2:true'));
  });

  testWidgets('the saved copy says so: claiming needs signal', (tester) async {
    useTallPhone(tester);
    api.shopping = ShoppingView(lines: api.shopping.lines, batches: api.shopping.batches, fetchedAt: wednesday, fromCache: true);
    await c.refresh();
    await tester.pumpWidget(wrap(ShoppingListScreen(controller: c)));
    expect(find.byKey(const Key('shopping-saved-copy')), findsOneWidget);
  });

  testWidgets('picking my portions opens Record purchase with them', (tester) async {
    useTallPhone(tester);
    List<DraftPurchaseLine>? opened;
    await c.refresh();
    await tester.pumpWidget(wrap(ShoppingListScreen(controller: c, onRecord: (lines) => opened = lines)));
    expect(find.byKey(const Key('record-selected')), findsNothing);
    await tester.tap(find.byKey(const Key('pick-p2')));
    await tester.pump();
    await tester.tap(find.byKey(const Key('record-selected')));
    await tester.pump();
    expect(opened!.single.picks.single.portionId, 'p2');
    expect(opened!.single.quantity, '4');
  });

  testWidgets('nothing to buy says so', (tester) async {
    api.shopping = ShoppingView(batches: [thisWeek]);
    await c.refresh();
    await tester.pumpWidget(wrap(ShoppingListScreen(controller: c)));
    expect(find.text('Nothing left to buy here.'), findsOneWidget);
  });
}
