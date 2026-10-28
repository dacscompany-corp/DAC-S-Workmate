/// The phone's stock forms, checked the way the server checks them (0104):
/// each problem here is one the server would refuse anyway, shown before
/// sending. The bodies are what `stk_move` / `stk_receive` / `stk_leftover`
/// take. Quantities are sent as text, exactly as typed (3 decimals at most).
library;

import 'stock_failure.dart';
import 'stock_models.dart';

/// Same rule as the server's pur_qty: a plain number, at most 3 decimals,
/// above 0 (a count may be 0 — not on the phone), at most 1,000,000.
double? parseStockQty(String text) {
  final s = text.replaceAll(',', '').trim();
  if (!RegExp(r'^\d+(\.\d{1,3})?$').hasMatch(s)) return null;
  final v = double.parse(s);
  return v > 0 && v <= 1000000 ? v : null;
}

/// "8", "2.5", "33.333": what the server is sent.
String qtyText(double v) => v.toStringAsFixed(3).replaceFirst(RegExp(r'\.?0+$'), '');

bool _isDay(String s) => RegExp(r'^\d{4}-\d{2}-\d{2}$').hasMatch(s);

/// An issue (warehouse → project), a move (project → project or → the
/// warehouse) or a return (part of one issue back to the warehouse).
class MoveForm {
  MoveForm({
    this.itemId,
    this.from = warehousePlace,
    this.to,
    this.quantity = '',
    required this.on,
    this.requestLineId,
    this.unplannedReason = '',
    this.note = '',
    this.returnsRecord,
  });

  String? itemId;

  /// [warehousePlace] or a project's folder id.
  String from;
  String? to;
  String quantity;

  /// Manila calendar day ("2026-10-27"), never after today.
  String on;
  String? requestLineId;
  String unplannedReason;
  String note;

  /// Set for a return: the issue it brings goods back from.
  String? returnsRecord;

  bool get isReturn => returnsRecord != null;
  bool get toSite => !isReturn && to != null && to != warehousePlace;

  /// What the server will call it.
  String get kind => isReturn ? 'return' : (from == warehousePlace ? 'issue' : 'move');

  /// Problems the server would refuse, in the order a person fixes them.
  List<StockFailure> problems({required String today}) {
    final out = <StockFailure>[];
    if (itemId == null || itemId!.isEmpty) out.add(StockFailure.badItem);
    if (parseStockQty(quantity) == null) out.add(StockFailure.badQuantity);
    if (!_isDay(on) || on.compareTo(today) > 0) out.add(StockFailure.badDate);
    if (!isReturn) {
      if (to == null || from == to) out.add(StockFailure.badPlace);
      if (toSite && requestLineId == null && unplannedReason.trim().isEmpty) out.add(StockFailure.unplannedReasonRequired);
    }
    if (note.trim().length > 300 || unplannedReason.trim().length > 300) out.add(StockFailure.badNote);
    return out;
  }

  /// `stk_move(p_op, p_body)`'s body.
  Map<String, dynamic> body() {
    final b = <String, dynamic>{'item_id': itemId, 'quantity': qtyText(parseStockQty(quantity)!), 'on': on, 'note': note.trim()};
    if (isReturn) {
      b['returns_record'] = returnsRecord;
    } else {
      b['from'] = from;
      b['to'] = to;
      if (toSite) {
        if (requestLineId != null) {
          b['request_line_id'] = requestLineId;
        } else {
          b['unplanned_reason'] = unplannedReason.trim();
        }
      }
    }
    return b;
  }
}

/// "Received": part or all of a warehouse line, in the line's own unit.
class ReceiveForm {
  ReceiveForm({required this.line, this.quantity = '', required this.on, this.note = ''});

  final StockLine line;
  String quantity;
  String on;
  String note;

  List<StockFailure> problems({required String today}) {
    final out = <StockFailure>[];
    final q = parseStockQty(quantity);
    if (q == null) out.add(StockFailure.badQuantity);
    if (q != null && q > line.awaiting + 0.0005) out.add(StockFailure.moreThanAwaited);
    if (!_isDay(on) || on.compareTo(today) > 0) out.add(StockFailure.badDate);
    if (note.trim().length > 300) out.add(StockFailure.badNote);
    return out;
  }

  /// `stk_receive(p_op, p_purchase, p_line_no, p_qty, p_on, p_note)`.
  Map<String, dynamic> params(String opId) => {
        'p_op': opId,
        'p_purchase': line.purchaseId,
        'p_line_no': line.lineNo,
        'p_qty': qtyText(parseStockQty(quantity)!),
        'p_on': on,
        'p_note': note.trim(),
      };
}

/// Leftovers of a project purchase line, in the catalogue item's unit, left
/// at the project's site or brought to the warehouse (Q3).
class LeftoverForm {
  LeftoverForm({required this.line, this.quantity = '', this.where = 'site', required this.on, this.note = ''});

  final StockLine line;
  String quantity;

  /// 'site' or 'warehouse'.
  String where;
  String on;
  String note;

  List<StockFailure> problems({required String today}) {
    final out = <StockFailure>[];
    if (line.match == null) out.add(StockFailure.toMatch);
    final q = parseStockQty(quantity);
    if (q == null) out.add(StockFailure.badQuantity);
    if (q != null && line.match != null && q > line.leftoverRoom + 0.0005) out.add(StockFailure.moreThanBought);
    if (!_isDay(on) || on.compareTo(today) > 0) out.add(StockFailure.badDate);
    if (note.trim().length > 300) out.add(StockFailure.badNote);
    return out;
  }

  /// `stk_leftover(p_op, p_purchase, p_line_no, p_qty, p_where, p_on, p_note)`.
  Map<String, dynamic> params(String opId) => {
        'p_op': opId,
        'p_purchase': line.purchaseId,
        'p_line_no': line.lineNo,
        'p_qty': qtyText(parseStockQty(quantity)!),
        'p_where': where,
        'p_on': on,
        'p_note': note.trim(),
      };
}
