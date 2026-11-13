import 'dart:ui' show CheckedState;

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
    expect(find.text('MINE'), findsOneWidget);
    expect(find.text(' · Akin'), findsOneWidget);
    expect(find.text('UNASSIGNED'), findsOneWidget);
    expect(find.text('Still to buy'), findsWidgets);
    expect(find.text('Kulang pang bilhin'), findsWidgets);
    expect(find.text('Cement · 40 kg'), findsWidgets);
    expect(find.byKey(const Key('urgent-p1')), findsOneWidget);
    expect(find.text('Urgent · needed by 2026-10-23'), findsWidgets);
    expect(find.byKey(const Key('changed-p2')), findsOneWidget);
    expect(find.text('6 bag'), findsOneWidget);
    expect(find.textContaining('₱'), findsNothing, reason: 'no prices on the list (Q4)');
    // The filter row scrolls sideways too: scroll the page itself.
    await tester.scrollUntilVisible(find.text('Buying: Ben'), 300, scrollable: find.byType(Scrollable).first);
    expect(find.text('OTHER BUYERS'), findsOneWidget);
    expect(find.text(' · Ibang bibili'), findsOneWidget);
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

  group('Phase 6a layout', () {
    Future<void> show(WidgetTester tester, {void Function(List<DraftPurchaseLine>)? onRecord}) async {
      useTallPhone(tester);
      await c.refresh();
      await tester.pumpWidget(wrap(ShoppingListScreen(controller: c, onRecord: onRecord ?? (_) {})));
    }

    CheckedState checked(WidgetTester tester) =>
        tester.getSemantics(find.byKey(const Key('pick-p2'))).getSemanticsData().flagsCollection.isChecked;

    testWidgets('the tick box picks and unpicks, and is a checkbox to a screen reader', (tester) async {
      final handle = tester.ensureSemantics();
      await show(tester);
      expect(checked(tester), CheckedState.isFalse);
      await tester.tap(find.byKey(const Key('pick-p2')));
      await tester.pump();
      expect(c.selected, {'p2'});
      expect(checked(tester), CheckedState.isTrue);
      await tester.tap(find.byKey(const Key('pick-p2')));
      await tester.pump();
      expect(c.selected, isEmpty);
      expect(checked(tester), CheckedState.isFalse);
      handle.dispose();
    });

    testWidgets('a ticked card has a green border and the floating bar counts and hands over the lines', (tester) async {
      List<DraftPurchaseLine>? opened;
      await show(tester, onRecord: (lines) => opened = lines);
      Color border() => ((tester.widget<Container>(find.byKey(const Key('entry-p2'))).decoration! as BoxDecoration).border! as Border).top.color;
      expect(border(), WmColors.border);
      await tester.tap(find.byKey(const Key('pick-p2')));
      await tester.pump();
      expect(border(), WmColors.green);
      expect(find.descendant(of: find.byKey(const Key('record-selected')), matching: find.text('Record purchase (1)')), findsOneWidget);
      await tester.tap(find.byKey(const Key('record-selected')));
      await tester.pump();
      expect(opened!.single.picks.single.portionId, 'p2');
      expect(c.selected, isEmpty, reason: 'the ticks clear when the lines are handed over');
    });

    testWidgets('the project pill offers every project and All projects, and choosing one filters', (tester) async {
      api.shopping = ShoppingView(batches: [thisWeek, nextWeek], fetchedAt: wednesday, lines: [
        ...api.shopping.lines,
        ShoppingLine(
          lineId: 'l2',
          requestId: 'r2',
          description: 'Hollow blocks',
          spec: '',
          unit: 'pc',
          projectId: 'f2',
          projectName: 'Cruz House',
          workId: 'f2',
          workName: 'Main Contract',
          requesterName: 'Maria',
          needed: 50,
          bought: 0,
          stillToBuy: 50,
          portions: [portion('p9', still: 50)],
        ),
      ]);
      await show(tester);
      expect(find.byKey(const Key('entry-p9')), findsOneWidget);
      expect(find.byKey(const Key('entry-p1')), findsOneWidget);
      await tester.ensureVisible(find.byKey(const Key('project-filter')));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const Key('project-filter')));
      await tester.pumpAndSettle();
      expect(find.text('All projects'), findsWidgets);
      expect(find.text('Barlin Residence'), findsOneWidget);
      expect(find.text('Cruz House'), findsOneWidget);
      await tester.tap(find.text('Cruz House'));
      await tester.pumpAndSettle();
      expect(c.project, 'f2');
      expect(find.byKey(const Key('entry-p9')), findsOneWidget);
      expect(find.byKey(const Key('entry-p1')), findsNothing);
      expect(find.descendant(of: find.byKey(const Key('project-filter')), matching: find.text('Cruz House')), findsOneWidget);
      await tester.ensureVisible(find.byKey(const Key('project-filter')));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const Key('project-filter')));
      await tester.pumpAndSettle();
      await tester.tap(find.text('All projects').last);
      await tester.pumpAndSettle();
      expect(c.project, isNull);
      expect(find.byKey(const Key('entry-p1')), findsOneWidget);
    });

    testWidgets('no peso anywhere, with every kind of line on the list', (tester) async {
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
          notes: 'Gate B',
          needed: 10,
          bought: 2,
          fromStock: 1,
          inWarehouse: 3,
          inWarehouseUnit: 'bag',
          stillToBuy: 7,
          portions: [
            portion('p1', still: 3),
            const PurPortion(id: 'p2', batchId: 'b1', stillToBuy: 2, buyerId: 'u1', mine: true, changed: true, arranged: true),
            const PurPortion(id: 'p3', batchId: 'b1', stillToBuy: 2, buyerId: 'u9', buyerName: 'Ben'),
          ],
        ),
      ]);
      await show(tester);
      await tester.tap(find.byKey(const Key('pick-p2')));
      await tester.pump();
      expect(find.byKey(const Key('in-warehouse-p1')), findsOneWidget);
      expect(find.byKey(const Key('from-stock-p1')), findsOneWidget);
      expect(find.textContaining('₱'), findsNothing);
    });

    testWidgets('Still to buy comes before Needed on a card', (tester) async {
      await show(tester);
      final card = find.byKey(const Key('entry-p1'));
      final still = tester.getTopLeft(find.descendant(of: card, matching: find.text('Still to buy')));
      final needed = tester.getTopLeft(find.descendant(of: card, matching: find.text('Needed')));
      expect(still.dx, lessThan(needed.dx));
    });

    testWidgets('at 320 x 568 with large text nothing overflows, ticked or not', (tester) async {
      tester.view.physicalSize = const Size(320, 568);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.reset);
      await c.refresh();
      await tester.pumpWidget(MaterialApp(
        theme: workMateTheme(),
        builder: (context, child) => MediaQuery(data: MediaQuery.of(context).copyWith(textScaler: const TextScaler.linear(1.3)), child: child!),
        home: Scaffold(body: ShoppingListScreen(controller: c, onRecord: (_) {})),
      ));
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull);
      c.toggle(c.sections.mine.single);
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull);
    });

    testWidgets('the claim sheet keeps its field and Claim button above the keyboard', (tester) async {
      await show(tester);
      await tester.tap(find.byKey(const Key('claim-p1')));
      await tester.pumpAndSettle();
      expect(find.byKey(const Key('wm-sheet-close')), findsOneWidget);
      tester.view.viewInsets = const FakeViewPadding(bottom: 900);
      addTearDown(tester.view.resetViewInsets);
      await tester.pumpAndSettle();
      final top = tester.getTopLeft(find.byKey(const Key('claim-qty'))).dy;
      final bottom = tester.getBottomLeft(find.byKey(const Key('claim-confirm'))).dy;
      final screen = tester.view.physicalSize.height / tester.view.devicePixelRatio;
      expect(top, greaterThan(0));
      expect(bottom, lessThanOrEqualTo(screen - 900 / tester.view.devicePixelRatio));
    });
  });

  testWidgets('nothing to buy says so', (tester) async {
    api.shopping = ShoppingView(batches: [thisWeek]);
    await c.refresh();
    await tester.pumpWidget(wrap(ShoppingListScreen(controller: c)));
    expect(find.text('Nothing left to buy here.'), findsOneWidget);
  });
}
