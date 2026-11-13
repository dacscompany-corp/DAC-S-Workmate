import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:workmate/auth/worker_profile.dart';
import 'package:workmate/profile/account_services.dart';
import 'package:workmate/purchasing/data/purchasing_api.dart';
import 'package:workmate/purchasing/domain/pur_models.dart';
import 'package:workmate/purchasing/purchasing_services.dart';
import 'package:workmate/purchasing/ui/buyer_shell.dart';
import 'package:workmate/stock/data/stock_pending_store.dart';
import 'package:workmate/stock/data/stock_submitter.dart';
import 'package:workmate/stock/domain/stock_failure.dart';
import 'package:workmate/stock/domain/stock_models.dart';
import 'package:workmate/stock/domain/stock_submission.dart';
import 'package:workmate/stock/ui/stock_controller.dart';
import 'package:workmate/stock/ui/stock_copy.dart';
import 'package:workmate/stock/ui/stock_screen.dart';
import 'package:workmate/ui/theme.dart';
import 'package:workmate/ui/wm_chips.dart';
import 'package:workmate/ui/wm_sheet.dart';

import '../attendance/fakes.dart' show useTallPhone;
import '../purchasing/purchasing_api_fake.dart';
import '../purchasing/purchasing_fakes.dart' as pf;
import 'stock_fakes.dart';

Widget wrap(Widget w) => MaterialApp(theme: workMateTheme(), home: w);

const staff = WorkerProfile(id: 's1', email: 'staff@dacsbuilding.com', displayName: 'Ana Reyes', role: 'staff', status: 'active');
final account = AccountServices(changePassword: (_) async {}, termsAcceptedAt: () async => null);

/// A Cement line with 6 bags in the warehouse — what 0104 sends once stock is on.
ShoppingLine cementLine({double inWarehouse = 6, double fromStock = 0}) => ShoppingLine(
      lineId: 'l1',
      requestId: 'r1',
      description: 'Cement',
      unit: 'bag',
      projectId: 'f-barlin',
      projectName: 'Barlin Residence',
      workId: 'f-barlin',
      workName: 'Main Contract',
      requesterName: 'Juan',
      needed: 10,
      stillToBuy: 10 - fromStock,
      portions: [pf.portion('p1', buyer: 's1', mine: true, still: 10 - fromStock)],
      catalogItemId: 'item-cement',
      fromStock: fromStock,
      inWarehouse: inWarehouse,
      inWarehouseUnit: 'bag',
    );

const forSlab = StockRequestLine(lineId: 'l1', description: 'Cement', unit: 'bag', catalogItemId: 'item-cement', requesterName: 'Juan', stillToBuy: 10);

/// No peso anywhere: not the cost move's value (400) nor its estimate (412).
void expectNoPesos() {
  expect(find.textContaining('₱'), findsNothing);
  expect(find.textContaining('400'), findsNothing);
  expect(find.textContaining('412'), findsNothing);
}

Future<void> pick(WidgetTester tester, String dropdownKey, String text) async {
  await tester.ensureVisible(find.byKey(Key(dropdownKey)));
  await tester.tap(find.byKey(Key(dropdownKey)));
  await tester.pumpAndSettle();
  await tester.tap(find.text(text).last);
  await tester.pumpAndSettle();
}

/// The forms are lazily built lists: scroll the button into the built range first.
Future<void> press(WidgetTester tester, String key) async {
  final f = find.byKey(Key(key));
  if (f.evaluate().isEmpty) await tester.scrollUntilVisible(f, 300, scrollable: find.byType(Scrollable).first);
  await tester.ensureVisible(f);
  await tester.pumpAndSettle();
  await tester.tap(find.byKey(Key(key)));
  await tester.pumpAndSettle();
}

void main() {
  late FakePurchasingApi api;
  late FakeStockRemote stock;

  setUp(() {
    // This week's cutoff must lie ahead of the real clock the shell reads.
    final liveWeek = PurBatch(id: 'b1', cutoffAt: DateTime.now().toUtc().add(const Duration(days: 3)), purchaseOn: '2026-10-26');
    api = FakePurchasingApi()..shopping = ShoppingView(lines: [cementLine()], batches: [liveWeek], fetchedAt: pf.wednesday);
    stock = FakeStockRemote(overview: sampleOverview(), choices: sampleChoices, requestLines: {'f-barlin': [forSlab]});
  });

  Future<void> openShell(WidgetTester tester) async {
    useTallPhone(tester);
    await tester.pumpWidget(wrap(BuyerShell(
      buyer: staff,
      versionName: '0.9.0',
      onSignOut: () async {},
      account: account,
      purchasing: PurchasingServices(api: api, stock: stock, stockStore: MemoryStockPendingStore()),
    )));
    await tester.pumpAndSettle();
  }

  group('the Stock tab follows the server switch', () {
    testWidgets('stock off: no Stock tab, no Issue from stock, the overview is never read', (tester) async {
      stock.statusAnswer = StockStatus.off;
      await openShell(tester);
      expect(stock.statusCalls, greaterThan(0));
      expect(stock.overviewCalls, 0);
      expect(find.byKey(const Key('tab-stock')), findsNothing);
      expect(find.byKey(const Key('issue-stock-p1')), findsNothing, reason: 'even if a line says something is in the warehouse');
      expect(find.text('Shopping list'), findsWidgets);
    });

    testWidgets('no stock server at all (older services): the shell is as before', (tester) async {
      useTallPhone(tester);
      await tester.pumpWidget(wrap(BuyerShell(
        buyer: staff,
        versionName: '0.9.0',
        onSignOut: () async {},
        account: account,
        purchasing: PurchasingServices(api: api),
      )));
      await tester.pumpAndSettle();
      expect(find.byKey(const Key('tab-stock')), findsNothing);
      expect(find.byKey(const Key('issue-stock-p1')), findsNothing);
    });

    testWidgets('stock on: the tab shows quantities per place, and never a peso', (tester) async {
      await openShell(tester);
      expect(find.byKey(const Key('tab-stock')), findsOneWidget);
      await tester.tap(find.text('Stock').last);
      await tester.pumpAndSettle();
      expect(find.text('Cement · Portland'), findsOneWidget);
      expect(find.text('14 bag'), findsOneWidget);
      expect(find.text('10 bag'), findsOneWidget);
      expect(find.text('4 bag'), findsOneWidget);
      expect(find.byKey(const Key('record-unplanned')), findsNothing, reason: 'Record purchase stays on the buying tabs');
      expectNoPesos();
    });

    testWidgets('switched off while away: on resume the tab goes and the shopping list shows', (tester) async {
      await openShell(tester);
      await tester.tap(find.text('Stock').last);
      await tester.pumpAndSettle();
      stock.statusAnswer = StockStatus.off;
      tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.inactive);
      tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
      await tester.pumpAndSettle();
      expect(find.byKey(const Key('tab-stock')), findsNothing);
      expect(find.text('Mga bibilhin'), findsOneWidget);
    });

    testWidgets('no signal: the notice says so and the last answer stays', (tester) async {
      await openShell(tester);
      await tester.tap(find.text('Stock').last);
      await tester.pumpAndSettle();
      stock.failReads = const SocketException('offline');
      await tester.tap(find.text('Stock').last);
      await tester.pumpAndSettle();
      expect(find.text(stockNeedsSignal.english), findsOneWidget);
      expect(find.text(stockNeedsSignal.tagalog), findsOneWidget);
      expect(find.text('Cement · Portland'), findsOneWidget);
      expect(find.byKey(const Key('tab-stock')), findsOneWidget, reason: 'no signal is not "stock off"');
    });
  });

  group('shopping list', () {
    testWidgets('shows From stock and the warehouse hint', (tester) async {
      api.shopping = ShoppingView(lines: [cementLine(fromStock: 4)], batches: api.shopping.batches, fetchedAt: pf.wednesday);
      await openShell(tester);
      expect(find.byKey(const Key('from-stock-p1')), findsOneWidget);
      expect(find.text('4 bag'), findsOneWidget);
      expect(find.text(fromStockLabel.english), findsOneWidget);
      expect(find.text('In warehouse: 6 bag'), findsOneWidget);
    });

    testWidgets('Issue from stock: item, place and request fixed; starts at the smaller of warehouse and still to buy', (tester) async {
      await openShell(tester);
      final before = api.calls.where((c) => c == 'shoppingList').length;
      await press(tester, 'issue-stock-p1');
      expect(find.text('Issue from stock'), findsOneWidget);
      expect(tester.widget<TextField>(find.byKey(const Key('move-qty'))).controller!.text, '6');
      expect(find.byKey(const Key('move-reason')), findsNothing, reason: 'it fills the request line');
      await press(tester, 'move-send');
      final (fn, params, userId) = stock.writes.single;
      expect(fn, 'stk_move');
      expect(userId, 's1');
      expect(params['p_body'], {
        'item_id': 'item-cement',
        'quantity': '6',
        'on': params['p_body']['on'],
        'note': '',
        'from': 'warehouse',
        'to': 'f-barlin',
        'request_line_id': 'l1',
      });
      expect(find.byKey(const Key('stock-recorded')), findsOneWidget);
      expect(api.calls.where((c) => c == 'shoppingList').length, greaterThan(before));
    });

    testWidgets('the button needs stock in the warehouse and the right to record', (tester) async {
      api.shopping = ShoppingView(lines: [cementLine(inWarehouse: 0)], batches: api.shopping.batches, fetchedAt: pf.wednesday);
      await openShell(tester);
      expect(find.byKey(const Key('issue-stock-p1')), findsNothing);
    });

    testWidgets('an account that may not record stock sees the hint, no button', (tester) async {
      stock.statusAnswer = const StockStatus(enabled: true, canRecord: false);
      await openShell(tester);
      expect(find.text('In warehouse: 6 bag'), findsOneWidget);
      expect(find.byKey(const Key('issue-stock-p1')), findsNothing);
    });
  });

  group('recording on the Stock screen', () {
    late StockController controller;
    late StockSubmitter submitter;
    late DateTime clock;
    var recorded = 0;

    Future<void> openStock(WidgetTester tester) async {
      useTallPhone(tester);
      recorded = 0;
      clock = DateTime.utc(2026, 10, 27, 2);
      controller = StockController(remote: stock);
      await controller.refresh();
      submitter = StockSubmitter(remote: stock, store: MemoryStockPendingStore(), now: () => clock);
      await submitter.load('s1');
      await tester.pumpWidget(wrap(Scaffold(body: StockScreen(controller: controller, submitter: submitter, onRecorded: () => recorded++))));
      await tester.pumpAndSettle();
    }

    testWidgets('read-only account: no Issue, Received or Return', (tester) async {
      stock.statusAnswer = const StockStatus(enabled: true, canRecord: false);
      await openStock(tester);
      expect(find.byKey(const Key('stock-issue')), findsNothing);
      expect(find.byKey(const Key('stock-leftovers')), findsNothing);
      await tester.tap(find.text('To receive (2)'));
      await tester.pumpAndSettle();
      expect(find.byKey(const Key('receive-p-1:1')), findsNothing);
      await tester.tap(find.text('Recent'));
      await tester.pumpAndSettle();
      expect(find.byKey(const Key('return-r-issue')), findsNothing);
    });

    testWidgets('Received: part of a line, checked against what is still awaited', (tester) async {
      await openStock(tester);
      await tester.tap(find.text('To receive (2)'));
      await tester.pumpAndSettle();
      expect(find.text('Not matched yet'), findsOneWidget, reason: 'the Wire box line');
      await press(tester, 'receive-p-1:1');
      expect(tester.widget<TextField>(find.byKey(const Key('receive-qty'))).controller!.text, '8');
      await tester.enterText(find.byKey(const Key('receive-qty')), '9');
      await press(tester, 'receive-send');
      expect(find.text(stockFailureCopy(StockFailure.moreThanAwaited).english), findsOneWidget);
      expect(stock.writes, isEmpty);
      await tester.enterText(find.byKey(const Key('receive-qty')), '5');
      await press(tester, 'receive-send');
      final (fn, params, _) = stock.writes.single;
      expect(fn, 'stk_receive');
      expect(params['p_purchase'], 'p-1');
      expect(params['p_line_no'], 1);
      expect(params['p_qty'], '5');
      expect(recorded, 1);
      expect(find.byKey(const Key('receive-qty')), findsNothing, reason: 'the sheet closed');
    });

    testWidgets('an unmatched line can still be received (it becomes stock once matched)', (tester) async {
      await openStock(tester);
      await tester.tap(find.text('To receive (2)'));
      await tester.pumpAndSettle();
      await press(tester, 'receive-p-2:1');
      expect(find.text(notMatchedYet.english), findsOneWidget);
      await press(tester, 'receive-send');
      expect(stock.writes.single.$2['p_qty'], '3');
    });

    testWidgets('Recent: cost states without values; Return brings the issue back', (tester) async {
      await openStock(tester);
      await tester.tap(find.text('Recent'));
      await tester.pumpAndSettle();
      expect(find.text('Cost assignment pending'), findsOneWidget);
      expect(find.text('For: Cement for slab'), findsOneWidget);
      expect(find.byKey(const Key('record-r-old')), findsOneWidget);
      expect(find.byKey(const Key('return-r-old')), findsNothing, reason: 'all of it already came back');
      expectNoPesos();
      await press(tester, 'return-r-issue');
      expect(find.text('Return to the warehouse'), findsOneWidget);
      expect(find.byKey(const Key('move-to')), findsNothing);
      await press(tester, 'move-send');
      final body = stock.writes.single.$2['p_body'] as Map<String, dynamic>;
      expect(body['returns_record'], 'r-issue');
      expect(body['quantity'], '4');
      expect(body.containsKey('from'), isFalse);
      expect(body.containsKey('to'), isFalse);
    });

    testWidgets('unplanned issue needs a reason; a request line of another item is not offered', (tester) async {
      stock.requestLinesAnswer = {
        'f-sulit': [const StockRequestLine(lineId: 'l-wire', description: 'Tie wire', unit: 'piece', catalogItemId: 'item-wire')],
      };
      await openStock(tester);
      await press(tester, 'stock-issue');
      await pick(tester, 'move-item', cement.label);
      await pick(tester, 'move-to', 'Sulit');
      await tester.tap(find.byKey(const Key('move-request')));
      await tester.pumpAndSettle();
      expect(find.textContaining('Tie wire —'), findsNothing);
      await tester.tap(find.text('None — unplanned').last);
      await tester.pumpAndSettle();
      await tester.enterText(find.byKey(const Key('move-qty')), '2');
      await press(tester, 'move-send');
      expect(find.text(stockFailureCopy(StockFailure.unplannedReasonRequired).english), findsOneWidget);
      expect(stock.attempts, isEmpty);
      await tester.enterText(find.byKey(const Key('move-reason')), 'Extra for the gate');
      await press(tester, 'move-send');
      final body = stock.writes.single.$2['p_body'] as Map<String, dynamic>;
      expect(body['to'], 'f-sulit');
      expect(body['unplanned_reason'], 'Extra for the gate');
      expect(body.containsKey('request_line_id'), isFalse);
    });

    /// An issue of 3 bag to Barlin for the Cement request, whose answer is lost.
    Future<void> issueLost(WidgetTester tester, {bool recorded = false}) async {
      await press(tester, 'stock-issue');
      await pick(tester, 'move-item', cement.label);
      await pick(tester, 'move-to', 'Barlin Residence');
      await pick(tester, 'move-request', 'Cement — Juan · 10 bag still needed');
      await tester.enterText(find.byKey(const Key('move-qty')), '3');
      if (recorded) {
        stock.loseNextAnswer = TimeoutException('lost after it was recorded');
      } else {
        stock.failNextWrite = const SocketException('lost');
      }
      await press(tester, 'move-send');
    }

    /// Whether a field takes input — scrolled back into the built part of the form first.
    Future<bool> fieldOn(WidgetTester tester, String key) async {
      final f = find.byKey(Key(key));
      if (f.evaluate().isEmpty) await tester.scrollUntilVisible(f, -300, scrollable: find.byType(Scrollable).first);
      return tester.widget<TextField>(f).enabled ?? true;
    }

    testWidgets('a lost answer locks the form: nothing can change; Send again sends the saved payload unchanged', (tester) async {
      await openStock(tester);
      await issueLost(tester);
      expect(find.text(notSureLabel.english), findsOneWidget);
      expect(find.text(stockFailureCopy(StockFailure.noConnection).english), findsOneWidget);
      expect(find.text('Issue or move'), findsOneWidget, reason: 'the form stays, locked');
      expect([await fieldOn(tester, 'move-qty'), await fieldOn(tester, 'move-note')], [false, false], reason: 'the quantity cannot be changed');
      expect(tester.widget<DropdownButtonFormField<String>>(find.byKey(const Key('move-to'))).onChanged, isNull);
      expect(find.byKey(const Key('move-send')), findsNothing, reason: 'no Send of the form — only Send again, Check or Cancel');
      expect(find.text(cancelChangeLabel.english), findsOneWidget, reason: 'a change goes through the server\'s cancel');
      await press(tester, 'unsure-send-again');
      expect(stock.attempts, hasLength(2));
      expect(stock.attempts[1], stock.attempts[0], reason: 'the same operation id and the same payload, byte for byte');
      expect(stock.writes.single.$2['p_body']['quantity'], '3');
      expect(find.text('Issue or move'), findsNothing, reason: 'recorded: the form closed');
      expect(recorded, 1);
      expect(submitter.unresolved, isEmpty);
    });

    testWidgets('a changed quantity after a timeout: only once the server cancels the id — then it is a new operation, and the late original is refused', (tester) async {
      await openStock(tester);
      await issueLost(tester);
      final first = stock.attempts.single;
      await press(tester, 'unsure-check');
      expect(find.text(notYetCopy.english), findsOneWidget, reason: 'the server has neither');
      expect(await fieldOn(tester, 'move-qty'), isFalse, reason: 'a check never unlocks it');
      clock = clock.add(const Duration(hours: 5));
      await press(tester, 'unsure-check');
      expect(await fieldOn(tester, 'move-qty'), isFalse, reason: 'no clock unlocks it either');
      await press(tester, 'unsure-cancel');
      expect(stock.cancelled, {'s1:${first.$1}'}, reason: 'the server cancelled the id for good');
      expect(find.text(stockFailureCopy(StockFailure.opCancelled).english), findsOneWidget);
      expect(await fieldOn(tester, 'move-qty'), isTrue, reason: 'now it may be changed');
      expect(submitter.unresolved, isEmpty);
      await tester.enterText(find.byKey(const Key('move-qty')), '5');
      await press(tester, 'move-send');
      expect(stock.writes.single.$2['p_body']['quantity'], '5');
      expect(stock.writes.single.$2['p_op'], isNot(first.$1), reason: 'a changed payload never travels under the old id');
      // The first request, held up on the network, arrives now.
      await expectLater(stock.write(StockWrite.move, jsonDecode(first.$2) as Map<String, dynamic>, userId: 's1'), throwsA(anything));
      expect(stock.writes.map((w) => w.$2['p_body']['quantity']), ['5'], reason: 'only the new submission is recorded');
    });

    testWidgets('Cancel it and change, when the server finds it was recorded: the form closes as recorded — nothing changes', (tester) async {
      await openStock(tester);
      await issueLost(tester, recorded: true);
      await press(tester, 'unsure-cancel');
      expect(find.text('Issue or move'), findsNothing);
      expect([stock.writes.length, stock.cancelled.length], [1, 0]);
      expect(stock.writes.single.$2['p_body']['quantity'], '3');
      expect(recorded, 1);
    });

    testWidgets('Cancel with no signal: nothing known, the form stays locked', (tester) async {
      await openStock(tester);
      await issueLost(tester);
      stock.failReads = const SocketException('offline');
      await press(tester, 'unsure-cancel');
      expect(await fieldOn(tester, 'move-qty'), isFalse);
      expect(find.text(stockFailureCopy(StockFailure.noConnection).english), findsOneWidget);
      expect(stock.cancelled, isEmpty);
    });

    testWidgets('a lost answer that was in fact recorded: Check finds it — nothing sent again, recorded once', (tester) async {
      await openStock(tester);
      await issueLost(tester, recorded: true);
      await press(tester, 'unsure-check');
      expect(find.text('Issue or move'), findsNothing);
      expect([stock.attempts.length, stock.writes.length, stock.checks], [1, 1, 1]);
      expect(find.byKey(const Key('stock-recorded')), findsOneWidget);
    });

    testWidgets('closing the form keeps it: the Stock tab shows it, nothing new starts, Send again from there', (tester) async {
      await openStock(tester);
      await issueLost(tester);
      await tester.pageBack();
      await tester.pumpAndSettle();
      final op = stock.attempts.single.$1;
      expect(find.byKey(Key('unsure-$op')), findsOneWidget);
      expect(find.text('Issued 3 bag Cement — Warehouse → Barlin Residence'), findsOneWidget);
      expect(find.byKey(const Key('stock-issue')), findsNothing, reason: 'no new submission until it is resolved');
      expect(find.byKey(const Key('stock-finish-first')), findsOneWidget);
      await tester.tap(find.text('To receive (2)'));
      await tester.pumpAndSettle();
      expect(find.byKey(const Key('receive-p-1:1')), findsNothing);
      await tester.tap(find.descendant(of: find.byKey(const Key('stock-parts')), matching: find.text('Stock')));
      await tester.pumpAndSettle();
      await press(tester, 'unsure-send-again');
      expect(stock.attempts[1], stock.attempts[0]);
      expect(find.byKey(Key('unsure-$op')), findsNothing);
      expect(find.byKey(const Key('stock-issue')), findsOneWidget);
      expect(recorded, 1);
    });

    testWidgets('a refusal is explained and nothing is recorded', (tester) async {
      await openStock(tester);
      await press(tester, 'stock-issue');
      await pick(tester, 'move-item', cement.label);
      await pick(tester, 'move-to', 'Barlin Residence');
      await tester.enterText(find.byKey(const Key('move-qty')), '30');
      await pick(tester, 'move-request', 'Cement — Juan · 10 bag still needed');
      stock.failNextWrite = pf.refusal('NOT_ENOUGH');
      await press(tester, 'move-send');
      expect(find.text(stockFailureCopy(StockFailure.notEnough).english), findsOneWidget);
      expect(stock.writes, isEmpty);
      expect(recorded, 0);
    });

    testWidgets('leftovers: a project purchase, at the site or brought to the warehouse', (tester) async {
      stock.projectLinesAnswer = {
        'f-barlin': [
          StockLine.fromJson(const {
            'purchase_id': 'p-9', 'line_no': 2, 'destination': 'project', 'folder_id': 'f-barlin', 'item_name': 'Cement',
            'unit': 'bag', 'quantity': 20, 'purchase_date': '2026-10-22', 'entered': 5,
            'match': {'item_id': 'item-cement', 'item_name': 'Cement', 'item_unit': 'bag', 'per': 1, 'covers': 1},
          }),
        ],
      };
      await openStock(tester);
      await press(tester, 'stock-leftovers');
      await pick(tester, 'leftover-project', 'Barlin Residence');
      expect(find.textContaining('up to 15 bag can be recorded'), findsOneWidget);
      await tester.tap(find.byKey(const Key('leftover-line-p-9:2')));
      await tester.pumpAndSettle();
      await tester.enterText(find.byKey(const Key('leftover-qty')), '16');
      await press(tester, 'leftover-send');
      expect(find.text(stockFailureCopy(StockFailure.moreThanBought).english), findsOneWidget);
      await tester.enterText(find.byKey(const Key('leftover-qty')), '3');
      await tester.tap(find.text('Brought to the warehouse'));
      await tester.pumpAndSettle();
      await press(tester, 'leftover-send');
      final (fn, params, _) = stock.writes.single;
      expect(fn, 'stk_leftover');
      expect(params['p_purchase'], 'p-9');
      expect(params['p_line_no'], 2);
      expect(params['p_qty'], '3');
      expect(params['p_where'], 'warehouse');
      expect(recorded, 1);
    });
  });

  group('Stock tab layout and the Received sheet (Phase 6a)', () {
    late StockController controller;
    late StockSubmitter submitter;

    Future<void> openStock(WidgetTester tester, {Size? size, double scale = 1}) async {
      if (size == null) {
        useTallPhone(tester);
      } else {
        tester.view.physicalSize = size;
        tester.view.devicePixelRatio = 1.0;
        addTearDown(tester.view.reset);
      }
      controller = StockController(remote: stock);
      await controller.refresh();
      submitter = StockSubmitter(remote: stock, store: MemoryStockPendingStore(), now: () => DateTime.utc(2026, 10, 27, 2));
      await submitter.load('s1');
      await tester.pumpWidget(MaterialApp(
        theme: workMateTheme(),
        builder: (context, child) => MediaQuery(data: MediaQuery.of(context).copyWith(textScaler: TextScaler.linear(scale)), child: child!),
        home: Scaffold(body: StockScreen(controller: controller, submitter: submitter)),
      ));
      await tester.pumpAndSettle();
    }

    Future<void> openReceive(WidgetTester tester, {String key = 'receive-p-1:1'}) async {
      await tester.tap(find.byKey(const Key('stock-part-receive')));
      await tester.pumpAndSettle();
      await press(tester, key);
    }

    String qtyField(WidgetTester tester) => tester.widget<TextField>(find.byKey(const Key('receive-qty'))).controller!.text;

    testWidgets('the switch is a WmSegmented: the count on To receive, and each segment key changes the part', (tester) async {
      await openStock(tester);
      expect(find.byType(SegmentedButton<StockPart>), findsNothing);
      expect(tester.widget(find.byKey(const Key('stock-parts'))), isA<WmSegmented<StockPart>>());
      expect(find.text('To receive (2)'), findsOneWidget);
      expect(find.byKey(const Key('stock-item-item-cement')), findsOneWidget);
      await tester.tap(find.byKey(const Key('stock-part-receive')));
      await tester.pumpAndSettle();
      expect(find.byKey(const Key('awaiting-p-1:1')), findsOneWidget);
      expect(find.byKey(const Key('stock-item-item-cement')), findsNothing);
      await tester.tap(find.byKey(const Key('stock-part-recent')));
      await tester.pumpAndSettle();
      expect(find.byKey(const Key('record-r-issue')), findsOneWidget);
      expect(find.byKey(const Key('awaiting-p-1:1')), findsNothing);
      await tester.tap(find.byKey(const Key('stock-part-stock')));
      await tester.pumpAndSettle();
      expect(find.byKey(const Key('stock-item-item-cement')), findsOneWidget);
    });

    testWidgets('an item card shows its total on the right and one row per place; the words "in all" are gone', (tester) async {
      await openStock(tester);
      final card = find.byKey(const Key('stock-item-item-cement'));
      final name = tester.getRect(find.descendant(of: card, matching: find.text('Cement · Portland')));
      final total = tester.getRect(find.descendant(of: card, matching: find.text('14 bag')));
      expect(total.left, greaterThan(name.right), reason: 'the total sits at the right of the name');
      expect(total.center.dy, closeTo(name.center.dy, 12));
      expect(find.textContaining('in all'), findsNothing);
      expect(find.descendant(of: card, matching: find.text('Warehouse')), findsOneWidget);
      expect(find.descendant(of: card, matching: find.text('10 bag')), findsOneWidget);
      expect(find.descendant(of: card, matching: find.text('Barlin Residence')), findsOneWidget);
      expect(find.descendant(of: card, matching: find.text('4 bag')), findsOneWidget);
      expect(find.byIcon(Icons.warehouse_outlined), findsOneWidget);
      expect(find.byIcon(Icons.construction_outlined), findsOneWidget);
    });

    testWidgets('no peso on any of the three parts, nor in the Received sheet', (tester) async {
      await openStock(tester);
      expectNoPesos();
      await tester.tap(find.byKey(const Key('stock-part-receive')));
      await tester.pumpAndSettle();
      expectNoPesos();
      await tester.tap(find.byKey(const Key('stock-part-recent')));
      await tester.pumpAndSettle();
      expectNoPesos();
      expect(find.text('Cost assignment pending'), findsOneWidget, reason: 'a cost move shows only its state');
      await tester.tap(find.byKey(const Key('stock-part-receive')));
      await tester.pumpAndSettle();
      await press(tester, 'receive-p-1:1');
      expectNoPesos();
    });

    testWidgets('Received: + adds 1, - takes 1 and stops at 0, a typed 2.5 becomes 3.5', (tester) async {
      await openStock(tester);
      await openReceive(tester);
      expect(qtyField(tester), '8');
      await press(tester, 'receive-plus');
      expect(qtyField(tester), '9');
      await press(tester, 'receive-minus');
      await press(tester, 'receive-minus');
      expect(qtyField(tester), '7');
      await tester.enterText(find.byKey(const Key('receive-qty')), '1');
      await press(tester, 'receive-minus');
      expect(qtyField(tester), '0');
      await press(tester, 'receive-minus');
      expect(qtyField(tester), '0', reason: 'never below zero');
      await tester.enterText(find.byKey(const Key('receive-qty')), '2.5');
      await press(tester, 'receive-plus');
      expect(qtyField(tester), '3.5');
      await press(tester, 'receive-minus');
      expect(qtyField(tester), '2.5');
      await tester.enterText(find.byKey(const Key('receive-qty')), '0.5');
      await press(tester, 'receive-minus');
      expect(qtyField(tester), '0', reason: 'a part of one stops at zero');
      await tester.enterText(find.byKey(const Key('receive-qty')), '');
      await press(tester, 'receive-plus');
      expect(qtyField(tester), '1', reason: 'an empty box counts as 0');
      await tester.enterText(find.byKey(const Key('receive-qty')), 'abc');
      await press(tester, 'receive-plus');
      expect(qtyField(tester), '1', reason: 'an unreadable box counts as 0');
      expect(tester.getSize(find.byKey(const Key('receive-minus'))).width, 52);
      expect(tester.getSize(find.byKey(const Key('receive-plus'))).height, 52);
      expect(tester.getRect(find.byKey(const Key('receive-minus'))).right, lessThan(tester.getRect(find.byKey(const Key('receive-qty'))).left + 1));
      expect(tester.getRect(find.byKey(const Key('receive-plus'))).left, greaterThan(tester.getRect(find.byKey(const Key('receive-qty'))).right - 1));
    });

    testWidgets("Received: Send sits in the sheet footer and records exactly today's parameters", (tester) async {
      await openStock(tester);
      await openReceive(tester);
      expect(find.ancestor(of: find.byKey(const Key('receive-send')), matching: find.byType(WmSheetFrame)), findsOneWidget);
      expect(
          find.descendant(
              of: find.descendant(of: find.byType(WmSheetFrame), matching: find.byType(ListView)), matching: find.byKey(const Key('receive-send'))),
          findsNothing,
          reason: 'pinned in the footer, not in the scrolling body');
      await press(tester, 'receive-minus');
      await tester.enterText(find.byKey(const Key('receive-note')), '  on the truck ');
      await press(tester, 'receive-send');
      final (fn, params, _) = stock.writes.single;
      expect(fn, 'stk_receive');
      expect(params.keys.toSet(), {'p_op', 'p_purchase', 'p_line_no', 'p_qty', 'p_on', 'p_note'});
      expect(params['p_purchase'], 'p-1');
      expect(params['p_line_no'], 1);
      expect(params['p_qty'], '7');
      expect(params['p_note'], 'on the truck');
      expect(find.byKey(const Key('receive-qty')), findsNothing, reason: 'the sheet closed');
      expect(find.byKey(const Key('stock-recorded')), findsOneWidget, reason: 'the notice stays a SnackBar on the tab');
    });

    testWidgets('Received: more than awaited is refused above Send in the footer and nothing is sent', (tester) async {
      await openStock(tester);
      await openReceive(tester);
      await press(tester, 'receive-plus');
      await press(tester, 'receive-plus');
      await press(tester, 'receive-send');
      expect(stock.writes, isEmpty);
      expect(find.byKey(const Key('stock-failure')), findsOneWidget);
      expect(find.text(stockFailureCopy(StockFailure.moreThanAwaited).english), findsOneWidget);
    });

    testWidgets('Received, answer lost: no Send, the unresolved box in the body, the fields and buttons locked', (tester) async {
      await openStock(tester);
      await openReceive(tester);
      stock.failNextWrite = const SocketException('lost');
      await press(tester, 'receive-send');
      final op = stock.attempts.single.$1;
      expect(find.byKey(const Key('receive-send')), findsNothing);
      // The tab behind the sheet lists the same unresolved record; the sheet's own box is the one in its body.
      expect(
          find.descendant(
              of: find.descendant(of: find.byType(WmSheetFrame), matching: find.byType(ListView)), matching: find.byKey(Key('unsure-$op'))),
          findsOneWidget);
      expect(tester.widget<TextField>(find.byKey(const Key('receive-qty'))).enabled, isFalse);
      final before = qtyField(tester);
      await tester.ensureVisible(find.byKey(const Key('receive-plus')));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const Key('receive-plus')), warnIfMissed: false);
      await tester.pumpAndSettle();
      expect(qtyField(tester), before, reason: 'locked: + does nothing');
    });

    for (final part in ['stock-part-stock', 'stock-part-receive', 'stock-part-recent']) {
      testWidgets('320 x 568 at text scale 1.3 raises no exception ($part)', (tester) async {
        await openStock(tester, size: const Size(320, 568), scale: 1.3);
        await tester.tap(find.byKey(Key(part)));
        await tester.pumpAndSettle();
        expect(tester.takeException(), isNull);
        expect(find.byKey(const Key('stock-parts')), findsOneWidget);
      });
    }

    testWidgets('320 x 568 at text scale 1.3: the Received sheet raises no exception', (tester) async {
      await openStock(tester, size: const Size(320, 568), scale: 1.3);
      await tester.tap(find.byKey(const Key('stock-part-receive')));
      await tester.pumpAndSettle();
      await press(tester, 'receive-p-1:1');
      expect(find.byKey(const Key('receive-send')), findsOneWidget);
      expect(tester.takeException(), isNull);
    });
  });

  group('a record whose answer was lost survives reopening and a restart (R101)', () {
    Future<void> openWith(WidgetTester tester, StockPendingStore store, {WorkerProfile buyer = staff}) async {
      useTallPhone(tester);
      await tester.pumpWidget(wrap(BuyerShell(
        buyer: buyer,
        versionName: '0.9.0',
        onSignOut: () async {},
        account: account,
        purchasing: PurchasingServices(api: api, stock: stock, stockStore: store),
      )));
      await tester.pumpAndSettle();
    }

    /// Issue from stock (6 bag) whose answer is lost; then the app closes and
    /// the phone's settings are read afresh from what was written.
    Future<void> lostThenClosed(WidgetTester tester, {bool recorded = false}) async {
      SharedPreferences.setMockInitialValues({});
      await openWith(tester, PrefsStockPendingStore(await SharedPreferences.getInstance()));
      if (recorded) {
        stock.loseNextAnswer = TimeoutException('lost after it was recorded');
      } else {
        stock.failNextWrite = const SocketException('lost');
      }
      await press(tester, 'issue-stock-p1');
      await press(tester, 'move-send');
      expect(find.text(notSureLabel.english), findsOneWidget);
      final raw = (await SharedPreferences.getInstance()).getString(PrefsStockPendingStore.key)!;
      await tester.pumpWidget(const SizedBox());
      // ignore: invalid_use_of_visible_for_testing_member
      SharedPreferences.resetStatic();
      SharedPreferences.setMockInitialValues({PrefsStockPendingStore.key: raw});
    }

    testWidgets('closed, then opened again: the shell keeps the Stock tab for it (even switched off) and hides Issue from stock', (tester) async {
      await openWith(tester, MemoryStockPendingStore());
      stock.failNextWrite = const SocketException('lost');
      await press(tester, 'issue-stock-p1');
      await press(tester, 'move-send');
      await tester.pageBack();
      await tester.pumpAndSettle();
      expect(find.byKey(const Key('issue-stock-p1')), findsNothing, reason: 'nothing new until it is resolved');
      stock.statusAnswer = StockStatus.off;
      await tester.tap(find.text('My purchases'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Shopping list').last);
      await tester.pumpAndSettle();
      expect(find.byKey(const Key('tab-stock')), findsOneWidget, reason: 'switched off, but it must still be resolved');
      await tester.tap(find.byKey(const Key('tab-stock')));
      await tester.pumpAndSettle();
      final op = stock.attempts.single.$1;
      expect(find.byKey(Key('unsure-$op')), findsOneWidget);
      stock.statusAnswer = const StockStatus(enabled: true, canRecord: true);
      await press(tester, 'unsure-send-again');
      expect(stock.attempts[1], stock.attempts[0]);
      expect(stock.writes, hasLength(1));
    });

    testWidgets('after a restart with no signal: it is still there and nothing is sent by itself', (tester) async {
      await lostThenClosed(tester);
      stock.failReads = const SocketException('offline');
      await openWith(tester, PrefsStockPendingStore(await SharedPreferences.getInstance()));
      expect(stock.attempts, hasLength(1), reason: 'never sent by itself');
      expect(find.byKey(const Key('tab-stock')), findsOneWidget);
      await tester.tap(find.byKey(const Key('tab-stock')));
      await tester.pumpAndSettle();
      expect(find.text('Issued 6 bag Cement — Warehouse → Barlin Residence'), findsOneWidget);
      expect(stock.attempts, hasLength(1));
      // Signal back: Send again, by hand, sends the saved payload unchanged.
      stock.failReads = null;
      await press(tester, 'unsure-send-again');
      expect(stock.attempts, hasLength(2));
      expect(stock.attempts[1], stock.attempts[0]);
      expect(stock.writes.single.$2['p_body']['quantity'], '6');
      expect(find.byKey(Key('unsure-${stock.attempts[0].$1}')), findsNothing);
    });

    testWidgets('after a restart with signal: a check (read only) finds it was recorded — it goes, never sent again', (tester) async {
      await lostThenClosed(tester, recorded: true);
      await openWith(tester, PrefsStockPendingStore(await SharedPreferences.getInstance()));
      expect(stock.checks, greaterThan(0));
      expect([stock.attempts.length, stock.writes.length], [1, 1]);
      expect(find.byKey(const Key('issue-stock-p1')), findsOneWidget, reason: 'resolved: new records may start');
      expect((await SharedPreferences.getInstance()).getString(PrefsStockPendingStore.key), '[]');
    });

    testWidgets('after a restart, Cancel it on the Stock tab: the server cancels the id, the card goes, new records start; the late original is refused', (tester) async {
      await lostThenClosed(tester);
      await openWith(tester, PrefsStockPendingStore(await SharedPreferences.getInstance()));
      expect(find.byKey(const Key('issue-stock-p1')), findsNothing);
      await tester.tap(find.byKey(const Key('tab-stock')));
      await tester.pumpAndSettle();
      final original = stock.attempts.single;
      await press(tester, 'unsure-cancel');
      expect(find.byKey(Key('unsure-${original.$1}')), findsNothing);
      expect(find.byKey(const Key('stock-refused')), findsOneWidget, reason: 'says it was cancelled and nothing recorded');
      expect((await SharedPreferences.getInstance()).getString(PrefsStockPendingStore.key), '[]');
      await tester.tap(find.text('Shopping list').last);
      await tester.pumpAndSettle();
      expect(find.byKey(const Key('issue-stock-p1')), findsOneWidget, reason: 'settled: new records may start');
      await expectLater(stock.write(StockWrite.move, jsonDecode(original.$2) as Map<String, dynamic>, userId: 's1'), throwsA(anything));
      expect(stock.writes, isEmpty, reason: 'the late original records nothing');
    });

    testWidgets('a damaged saved record: the Stock tab offers Check and Cancel (no Send again); nothing new starts; Cancel settles it', (tester) async {
      const me = WorkerProfile(id: 'aaaaaaaa-0000-4000-8000-0000000000a1', email: 'staff@dacsbuilding.com', displayName: 'Ana Reyes', role: 'staff', status: 'active');
      const op = '11111111-0000-4000-8000-0000000000a1';
      const raw = '[{"op_id":"$op","user_id":"${'aaaaaaaa-0000-4000-8000-0000000000a1'}","fn":"stk_move","payload":"not json"}]';
      // ignore: invalid_use_of_visible_for_testing_member
      SharedPreferences.resetStatic();
      SharedPreferences.setMockInitialValues({PrefsStockPendingStore.key: raw});
      final prefs = await SharedPreferences.getInstance();
      await openWith(tester, PrefsStockPendingStore(prefs), buyer: me);
      expect(find.byKey(const Key('issue-stock-p1')), findsNothing, reason: 'malformed data never unblocks a new send');
      await tester.tap(find.byKey(const Key('tab-stock')));
      await tester.pumpAndSettle();
      expect(find.byKey(const Key('unreadable-$op')), findsOneWidget);
      expect(find.text(unreadableLabel.english), findsOneWidget);
      expect(find.byKey(const Key('unsure-send-again')), findsNothing, reason: 'its payload is never rebuilt');
      expect(find.byKey(const Key('stock-issue')), findsNothing);
      expect(prefs.getString(PrefsStockPendingStore.key), raw, reason: 'opening and checking keep it');
      await press(tester, 'unreadable-cancel');
      expect(stock.cancelled, {'${me.id}:$op'});
      expect(find.byKey(const Key('unreadable-$op')), findsNothing);
      expect(prefs.getString(PrefsStockPendingStore.key), '[]');
      expect(find.byKey(const Key('stock-issue')), findsOneWidget, reason: 'settled by the server: stock records start again');
      expect(stock.attempts, isEmpty);
    });

    testWidgets('a damaged saved record with no signal: Cancel changes nothing — it stays, still blocking', (tester) async {
      const me = WorkerProfile(id: 'aaaaaaaa-0000-4000-8000-0000000000a2', email: 'staff@dacsbuilding.com', displayName: 'Ana Reyes', role: 'staff', status: 'active');
      const op = '11111111-0000-4000-8000-0000000000a2';
      const raw = '[{"op_id":"$op","user_id":"aaaaaaaa-0000-4000-8000-0000000000a2","fn":"stk_move","payload":"not json"}]';
      // ignore: invalid_use_of_visible_for_testing_member
      SharedPreferences.resetStatic();
      SharedPreferences.setMockInitialValues({PrefsStockPendingStore.key: raw});
      final prefs = await SharedPreferences.getInstance();
      await openWith(tester, PrefsStockPendingStore(prefs), buyer: me);
      await tester.tap(find.byKey(const Key('tab-stock')));
      await tester.pumpAndSettle();
      stock.failReads = const SocketException('offline');
      await press(tester, 'unreadable-cancel');
      expect(find.byKey(const Key('unreadable-$op')), findsOneWidget, reason: 'no answer from the server: it stays');
      expect(find.text(stockFailureCopy(StockFailure.noConnection).english), findsOneWidget);
      expect(find.byKey(const Key('stock-refused')), findsNothing, reason: 'never reported as cancelled');
      expect([stock.cancelled, prefs.getString(PrefsStockPendingStore.key)], [isEmpty, raw]);
      expect(find.byKey(const Key('stock-issue')), findsNothing, reason: 'still blocking');
    });

    testWidgets('damaged storage: a recovery error, nothing can start, and the stored text is never touched', (tester) async {
      // ignore: invalid_use_of_visible_for_testing_member
      SharedPreferences.resetStatic();
      SharedPreferences.setMockInitialValues({PrefsStockPendingStore.key: 'not json'});
      final prefs = await SharedPreferences.getInstance();
      await openWith(tester, PrefsStockPendingStore(prefs));
      expect(find.byKey(const Key('issue-stock-p1')), findsNothing);
      await tester.tap(find.byKey(const Key('tab-stock')));
      await tester.pumpAndSettle();
      expect(find.byKey(const Key('stock-recovery')), findsOneWidget);
      expect(find.text(recoveryLabel.english), findsOneWidget);
      expect(find.byKey(const Key('stock-issue')), findsNothing);
      expect(find.byKey(const Key('stock-leftovers')), findsNothing);
      tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.inactive);
      tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
      await tester.pumpAndSettle();
      expect(prefs.getString(PrefsStockPendingStore.key), 'not json');
      expect(stock.attempts, isEmpty);
    });

    testWidgets('a stock server with no store on the phone: no Stock tab at all (never kept in memory alone)', (tester) async {
      useTallPhone(tester);
      await tester.pumpWidget(wrap(BuyerShell(
        buyer: staff,
        versionName: '0.9.0',
        onSignOut: () async {},
        account: account,
        purchasing: PurchasingServices(api: api, stock: stock),
      )));
      await tester.pumpAndSettle();
      expect(find.byKey(const Key('tab-stock')), findsNothing);
      expect(find.byKey(const Key('issue-stock-p1')), findsNothing);
    });

    testWidgets('after a restart, another account on the same phone neither sees nor sends it', (tester) async {
      await lostThenClosed(tester);
      await openWith(tester, PrefsStockPendingStore(await SharedPreferences.getInstance()),
          buyer: const WorkerProfile(id: 's2', email: 'other@dacsbuilding.com', displayName: 'Ben Cruz', role: 'staff', status: 'active'));
      expect(find.byKey(const Key('issue-stock-p1')), findsOneWidget, reason: 'not held back by someone else\'s');
      await tester.tap(find.byKey(const Key('tab-stock')));
      await tester.pumpAndSettle();
      expect(find.textContaining('Issued 6 bag'), findsNothing);
      expect(stock.attempts, hasLength(1));
      expect(stock.checks, 0, reason: 'never checked as another account');
    });
  });

  group('StockController', () {
    test('stock off: the overview is not read', () async {
      stock.statusAnswer = StockStatus.off;
      final c = StockController(remote: stock);
      await c.refresh();
      expect(c.enabled, isFalse);
      expect(stock.overviewCalls, 0);
      expect(c.overview.items, isEmpty);
    });

    test('a failed refresh keeps the last answer and says why', () async {
      final c = StockController(remote: stock);
      await c.refresh();
      stock.failReads = const SocketException('offline');
      await c.refresh();
      expect(c.failure, StockFailure.noConnection);
      expect(c.enabled, isTrue);
      expect(c.overview.items, hasLength(1));
      expect(c.loading, isFalse);
    });

    test('an older refresh answering last changes nothing', () async {
      final c = StockController(remote: stock);
      final first = c.refresh();
      stock.statusAnswer = StockStatus.off;
      final second = c.refresh();
      await Future.wait([first, second]);
      expect(c.enabled, isFalse);
    });

    test('a refresh after dispose is ignored', () async {
      final c = StockController(remote: stock);
      final f = c.refresh();
      c.dispose();
      await f;
      expect(c.loaded, isFalse);
    });
  });
}
