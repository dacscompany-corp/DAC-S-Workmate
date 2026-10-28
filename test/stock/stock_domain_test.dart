import 'dart:async';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:workmate/purchasing/domain/pur_models.dart';
import 'package:workmate/requests/domain/remote_request.dart';
import 'package:workmate/stock/domain/stock_failure.dart';
import 'package:workmate/stock/domain/stock_forms.dart';
import 'package:workmate/stock/domain/stock_models.dart';

import 'stock_fakes.dart';

void main() {
  group('the server\'s answers, as the phone reads them', () {
    test('the overview: items by place, deliveries awaited, the latest records', () {
      final ov = sampleOverview();
      final c = ov.item('item-cement')!;
      expect([c.total, c.inWarehouse, c.at(warehousePlace), c.at('f-barlin'), c.at('f-sulit')], [14, 10, 10, 4, 0]);
      expect(ov.awaiting.map((l) => [l.key, l.awaiting, l.match?.itemId]).toList(), [
        ['p-1:1', 8, 'item-cement'],
        ['p-2:1', 3, null],
      ]);
      final issue = ov.recent.first;
      expect([issue.kind, issue.unit, issue.canReturn, issue.costs.single.status], ['issue', 'bag', true, 'pending']);
      expect([ov.recent.last.unit, ov.recent.last.what, ov.recent.last.canReturn], ['bag', 'Cement', false],
          reason: 'a receipt is counted in the purchase line\'s unit');
    });

    test('quantities only: no cost-move value is read, even when an owner account is sent one', () {
      final cost = sampleOverview().recent.first.costs.single;
      expect([cost.kind, cost.status, cost.reversed], ['assign', 'pending', false]);
      // StockCostState has no value, estimate or amount field at all.
      expect(cost.toString().contains('400'), isFalse);
    });

    test('numbers arrive as JSON numbers or numeric text; both are read', () {
      final l = StockLine.fromJson({'purchase_id': 'p', 'line_no': '2', 'quantity': '3', 'awaiting': '1.5', 'match': null});
      expect([l.lineNo, l.quantity, l.awaiting], [2, 3, 1.5]);
    });

    test('leftover room: the line in item units, less what is already stock — the server\'s rounding', () {
      StockLine line(double qty, double per, double covers, double entered) => StockLine(
          purchaseId: 'p', lineNo: 1, quantity: qty, entered: entered, match: StockMatch(itemId: 'i', per: per, covers: covers));
      expect(line(10, 10, 10, 3).leftoverRoom, 7);
      expect(line(3, 3, 100, 33.333).leftoverRoom, 66.667, reason: '3 boxes = 100 pieces');
      expect(line(2, 2, 100, 100).leftoverRoom, 0);
      expect(const StockLine(purchaseId: 'p', lineNo: 1, quantity: 5).leftoverRoom, 0, reason: 'not matched yet');
    });

    test('a request line fits an item only if it is that item\'s (or has none) and in the same unit', () {
      const own = StockRequestLine(lineId: 'a', catalogItemId: 'item-cement', unit: 'Bag ');
      const none = StockRequestLine(lineId: 'b', unit: 'bag');
      const other = StockRequestLine(lineId: 'c', catalogItemId: 'item-sand', unit: 'bag');
      const box = StockRequestLine(lineId: 'd', unit: 'box');
      expect([own.fits(cement), none.fits(cement), other.fits(cement), box.fits(cement)], [true, true, false, false]);
    });

    test('completed projects come last, marked', () {
      expect(sampleChoices.projectsInOrder.map((p) => p.label).toList(), ['Barlin Residence', 'Sulit', 'Old Fence (completed)']);
    });

    test('the shopping list keeps From stock, In warehouse and the catalogue item — also through its saved copy', () {
      final l = ShoppingLine.fromJson({
        'line_id': 'l', 'request_id': 'r', 'bought': 2, 'from_stock': 4, 'in_warehouse': '10', 'in_warehouse_unit': 'bag',
        'catalog_item_id': 'item-cement', 'still_to_buy': 4,
      });
      final again = ShoppingLine.fromJson(l.toJson());
      expect([again.bought, again.fromStock, again.inWarehouse, again.inWarehouseUnit, again.catalogItemId],
          [2, 4, 10, 'bag', 'item-cement']);
      final old = ShoppingLine.fromJson({'line_id': 'l', 'request_id': 'r'});
      expect([old.fromStock, old.inWarehouse, old.catalogItemId], [0, 0, null], reason: 'a saved copy from 0.8.1');
    });

    test('a worker\'s request line and portion read "from_stock" (0106); 0 from a server before 0106', () {
      Map<String, dynamic> line([Map<String, dynamic> extra = const {}]) => {
            'id': 'l', 'position': 1, 'kind': 'material', 'description': 'Cement', 'unit': 'bag', 'version': 1, 'needed': 6,
            'portions': [
              {'quantity': 6, 'pending_reduction': 0, 'arranged': false, 'cutoff_at': '2026-10-31T04:00:00Z', 'purchase_on': '2026-11-02',
               'delivery_on': '2026-11-04', ...extra},
            ],
            ...extra,
          };
      final now = RemoteLine.fromJson(line({'from_stock': 4}));
      expect([now.fromStock, now.portions.single.fromStock], [4, 4]);
      final before = RemoteLine.fromJson(line());
      expect([before.fromStock, before.portions.single.fromStock], [0, 0]);
    });
  });

  group('the forms check what the server checks', () {
    const today = '2026-10-27';

    test('quantities: above 0, at most 3 decimals, commas allowed; sent as plain text', () {
      expect(['8', '2.5', '1,000', '0.001'].map(parseStockQty).toList(), [8, 2.5, 1000, 0.001]);
      expect(['0', '-1', '1.2345', 'abc', '', '1000001'].map(parseStockQty).toList(), List.filled(6, null));
      expect([qtyText(8), qtyText(2.5), qtyText(33.333)], ['8', '2.5', '33.333']);
    });

    test('an issue to a project fills a request line, or says why it is needed', () {
      final f = MoveForm(itemId: 'item-cement', to: 'f-barlin', quantity: '4', on: today);
      expect(f.kind, 'issue');
      expect(f.problems(today: today), [StockFailure.unplannedReasonRequired]);
      f.requestLineId = 'line-1';
      expect(f.problems(today: today), isEmpty);
      expect(f.body(), {'item_id': 'item-cement', 'quantity': '4', 'on': today, 'note': '', 'from': 'warehouse', 'to': 'f-barlin',
                        'request_line_id': 'line-1'});
      f
        ..requestLineId = null
        ..unplannedReason = '  formwork ';
      expect(f.body()['unplanned_reason'], 'formwork');
      expect(f.body().containsKey('request_line_id'), isFalse);
    });

    test('a move between projects, or to the warehouse (no request there); never to the same place', () {
      final f = MoveForm(itemId: 'item-cement', from: 'f-barlin', to: warehousePlace, quantity: '1', on: today);
      expect([f.kind, f.problems(today: today)], ['move', isEmpty]);
      expect(f.body().keys.toSet(), {'item_id', 'quantity', 'on', 'note', 'from', 'to'});
      f.to = 'f-barlin';
      expect(f.problems(today: today), contains(StockFailure.badPlace));
      f.to = null;
      expect(f.problems(today: today), contains(StockFailure.badPlace));
    });

    test('a return names its issue only: the same lots go back to the warehouse', () {
      final f = MoveForm(itemId: 'item-cement', returnsRecord: 'r-issue', quantity: '2', on: today);
      expect([f.kind, f.problems(today: today)], ['return', isEmpty]);
      expect(f.body(), {'item_id': 'item-cement', 'quantity': '2', 'on': today, 'note': '', 'returns_record': 'r-issue'});
    });

    test('a day that has not happened, a missing item, a bad quantity, a long note — each refused here first', () {
      final f = MoveForm(to: 'f-barlin', quantity: '0', on: '2026-10-28', unplannedReason: 'x', note: 'n' * 301);
      expect(f.problems(today: today), [StockFailure.badItem, StockFailure.badQuantity, StockFailure.badDate, StockFailure.badNote]);
    });

    test('received: in the line\'s unit, never more than awaited', () {
      final line = sampleOverview().awaiting.first;
      final f = ReceiveForm(line: line, quantity: '9', on: today);
      expect(f.problems(today: today), [StockFailure.moreThanAwaited]);
      f.quantity = '8';
      expect(f.problems(today: today), isEmpty);
      expect(f.params('op-1'), {'p_op': 'op-1', 'p_purchase': 'p-1', 'p_line_no': 1, 'p_qty': '8', 'p_on': today, 'p_note': ''});
    });

    test('leftovers: a matched line only, in item units, never more than it brought', () {
      const matched = StockLine(purchaseId: 'p', lineNo: 2, quantity: 10, entered: 6, match: StockMatch(itemId: 'i', per: 10, covers: 10));
      final f = LeftoverForm(line: matched, quantity: '5', on: today);
      expect(f.problems(today: today), [StockFailure.moreThanBought]);
      f
        ..quantity = '4'
        ..where = 'warehouse';
      expect(f.problems(today: today), isEmpty);
      expect(f.params('op-2'), {'p_op': 'op-2', 'p_purchase': 'p', 'p_line_no': 2, 'p_qty': '4', 'p_where': 'warehouse', 'p_on': today,
                                'p_note': ''});
      final unmatched = LeftoverForm(line: const StockLine(purchaseId: 'p', lineNo: 3, quantity: 2), quantity: '1', on: today);
      expect(unmatched.problems(today: today), [StockFailure.toMatch]);
    });
  });

  group('refusals in words', () {
    test('every server code the phone can meet has its own words, in English and Tagalog', () {
      for (final code in ['STOCK_OFF', 'NOT_ALLOWED', 'TO_MATCH', 'MORE_THAN_AWAITED', 'MORE_THAN_BOUGHT', 'MORE_THAN_ISSUED', 'NOT_ENOUGH',
                          'BAD_RETURN', 'BAD_LOCATION', 'UNPLANNED_REASON_REQUIRED', 'REQUEST_EXCEEDED', 'ITEM_MISMATCH', 'UNIT_MISMATCH',
                          'LINE_CLOSED', 'BAD_REQUEST_LINK', 'BAD_DATE', 'BAD_STATE', 'NOT_WAREHOUSE', 'NOT_PROJECT']) {
        final f = StockFailure.of(Exception('P0001: $code'));
        expect(f, isNot(StockFailure.unexpected), reason: code);
        final copy = stockFailureCopy(f);
        expect(copy.english.isNotEmpty && copy.tagalog.isNotEmpty && copy.english != copy.tagalog, isTrue, reason: code);
      }
    });

    test('whole codes only, and no signal is "press Send again", never a guess', () {
      expect(StockFailure.of(Exception('UNPLANNED_REASON_REQUIRED')), StockFailure.unplannedReasonRequired);
      expect(StockFailure.of(Exception('REASON_REQUIRED')), StockFailure.reasonRequired);
      expect(StockFailure.of(const SocketException('down')), StockFailure.noConnection);
      expect(StockFailure.of(TimeoutException('slow')), StockFailure.noConnection);
      expect(StockFailure.of(StateError('AUTH_REQUIRED')), StockFailure.sessionExpired);
      expect(StockFailure.of(Exception('something odd')), StockFailure.unexpected);
      expect([StockFailure.noConnection.retryable, StockFailure.notEnough.retryable], [true, false]);
      expect(stockFailureCopy(StockFailure.noConnection).english, contains('never recorded twice'));
    });
  });
}
