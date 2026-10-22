import '../../requests/domain/quantity.dart';
import 'pur_models.dart';
import 'purchase_draft.dart';

/// A buyer's correction of their own recorded purchase on the phone (Q13):
/// the date, the supplier, each line's quantity and amount, the receipt
/// total, and new receipt photos. Nothing else changes here — not the
/// project (that needs the owner), not the request links, never a void.
class CorrectionDraft {
  const CorrectionDraft({
    required this.purchaseDate,
    required this.supplier,
    required this.quantities,
    required this.amounts,
    required this.receiptTotal,
    this.supplierChanged = false,
    this.photos = const {},
    this.reason = '',
  });

  /// The purchase as stored, ready to edit.
  factory CorrectionDraft.of(PurchaseDetail p) => CorrectionDraft(
        purchaseDate: p.purchaseDate,
        supplier: p.supplier,
        quantities: [for (final l in p.lines) formatQuantity(l.quantity).replaceAll(',', '')],
        amounts: [for (final l in p.lines) l.amount.toStringAsFixed(2)],
        receiptTotal: p.receiptTotal.toStringAsFixed(2),
      );

  final String purchaseDate;
  final String supplier;

  /// The buyer typed a different supplier: the picked one from the list is dropped.
  final bool supplierChanged;

  /// One per stored line, in line order.
  final List<String> quantities;
  final List<String> amounts;
  final String receiptTotal;

  /// New receipt photos for empty slots only: slot → file on the phone.
  final Map<String, String> photos;
  final String reason;

  CorrectionDraft copyWith({
    String? purchaseDate,
    String? supplier,
    bool? supplierChanged,
    List<String>? quantities,
    List<String>? amounts,
    String? receiptTotal,
    Map<String, String>? photos,
    String? reason,
  }) =>
      CorrectionDraft(
        purchaseDate: purchaseDate ?? this.purchaseDate,
        supplier: supplier ?? this.supplier,
        supplierChanged: supplierChanged ?? this.supplierChanged,
        quantities: quantities ?? this.quantities,
        amounts: amounts ?? this.amounts,
        receiptTotal: receiptTotal ?? this.receiptTotal,
        photos: photos ?? this.photos,
        reason: reason ?? this.reason,
      );

  /// Lines + the stored fees − the stored discounts.
  double computedTotal(PurchaseDetail p) {
    final items = amounts.fold<double>(0, (a, s) => a + (parseMoney(s) ?? 0));
    final fees = p.charges.where((c) => c.kind == 'delivery_fee').fold<double>(0, (a, c) => a + c.amount);
    final discounts = p.charges.where((c) => c.kind == 'discount').fold<double>(0, (a, c) => a + c.amount);
    return round2(items + fees - discounts);
  }
}

enum CorrectionProblem { badDate, badQuantity, badAmount, badTotal, totalMismatch, reasonRequired, nothingChanged }

/// What the server would refuse, said first; with the line number when about one.
List<(CorrectionProblem, int?)> correctionProblems(PurchaseDetail p, CorrectionDraft c) {
  final out = <(CorrectionProblem, int?)>[];
  if (!RegExp(r'^\d{4}-\d{2}-\d{2}$').hasMatch(c.purchaseDate)) out.add((CorrectionProblem.badDate, null));
  for (var i = 0; i < p.lines.length; i++) {
    if (parseQuantity(c.quantities[i]) == null) out.add((CorrectionProblem.badQuantity, i + 1));
    if (parseMoney(c.amounts[i]) == null) out.add((CorrectionProblem.badAmount, i + 1));
  }
  final total = parseMoney(c.receiptTotal);
  if (total == null) {
    out.add((CorrectionProblem.badTotal, null));
  } else if (round2(total) != c.computedTotal(p)) {
    out.add((CorrectionProblem.totalMismatch, null));
  }
  if (c.reason.trim().isEmpty) out.add((CorrectionProblem.reasonRequired, null));
  if (out.isEmpty && !changed(p, c)) out.add((CorrectionProblem.nothingChanged, null));
  return out;
}

/// Whether the correction changes anything at all.
bool changed(PurchaseDetail p, CorrectionDraft c) {
  if (c.purchaseDate != p.purchaseDate || c.supplierChanged || c.photos.isNotEmpty) return true;
  if (round2(parseMoney(c.receiptTotal) ?? -1) != round2(p.receiptTotal)) return true;
  for (var i = 0; i < p.lines.length; i++) {
    if (round3(parseQuantity(c.quantities[i]) ?? -1) != round3(p.lines[i].quantity)) return true;
    if (round2(parseMoney(c.amounts[i]) ?? -1) != round2(p.lines[i].amount)) return true;
  }
  return false;
}

/// The pur_correct body. Request links, reasons and the picked supplier are
/// left out on purpose: pur_inherit keeps them as stored. Fees keep their
/// split while no line amount changed; otherwise the server splits them by
/// the new amounts again (pur_prorate), which may differ from an adjusted one.
Map<String, dynamic> correctionBody(PurchaseDetail p, CorrectionDraft c) {
  final amountsChanged = [
    for (var i = 0; i < p.lines.length; i++) round2(parseMoney(c.amounts[i]) ?? 0) != round2(p.lines[i].amount),
  ].any((x) => x);
  return {
    'source': 'workmate',
    'purchase_date': c.purchaseDate,
    // The stored time of day stays while the date is unchanged (the web's rule).
    'date_time': p.dateTime.length >= 10 && p.dateTime.substring(0, 10) == c.purchaseDate ? p.dateTime : c.purchaseDate,
    'supplier': c.supplier.trim(),
    if (c.supplierChanged) 'supplier_id': null,
    'payment_method': p.paymentMethod,
    'notes': p.notes,
    'receipt_total': round2(parseMoney(c.receiptTotal) ?? 0),
    'docs': <String, dynamic>{},
    'lines': [
      for (var i = 0; i < p.lines.length; i++)
        {
          'destination': p.lines[i].destination,
          'folder_id': p.lines[i].folderId,
          'item_name': p.lines[i].itemName,
          'category': p.lines[i].category,
          'quantity': round3(parseQuantity(c.quantities[i]) ?? 0),
          'unit': p.lines[i].unit,
          'amount': round2(parseMoney(c.amounts[i]) ?? 0),
          'in_inventory': p.lines[i].inInventory,
          'min_stock': p.lines[i].minStock,
        },
    ],
    'charges': [
      for (final ch in p.charges)
        {
          'kind': ch.kind,
          'amount': round2(ch.amount),
          if (!amountsChanged && ch.shares.isNotEmpty)
            'shares': [for (final e in ch.shares.entries) {'line': e.key, 'amount': round2(e.value)}],
        },
    ],
  };
}
