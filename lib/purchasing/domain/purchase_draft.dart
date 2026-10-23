import '../../requests/domain/quantity.dart';
import 'pay_models.dart';
import 'pur_models.dart';

const _keep = Object();

/// Pesos as the server takes them (0096 pur_money): 0 or more, at most two
/// decimals. Commas are allowed while typing ("1,250.50").
double? parseMoney(String text) {
  final t = text.trim().replaceAll(',', '');
  if (!RegExp(r'^\d+(\.\d{1,2})?$').hasMatch(t)) return null;
  return double.parse(t);
}

double round2(num v) => (v * 100).roundToDouble() / 100;
double round3(num v) => (v * 1000).roundToDouble() / 1000;

/// The server's default split of a fee or discount (0096 pur_prorate, and the
/// Purchasing tab's prorate): each share rounded DOWN to the centavo, then
/// the centavos left over one each to the biggest remainders, the earliest
/// line on a tie. Always adds up to [total].
List<double> prorate(double total, List<double> weights) {
  final n = weights.length;
  if (n == 0) return const [];
  final ws = [for (final w in weights) w > 0 ? w : 0.0];
  final sum = ws.fold<double>(0, (a, b) => a + b);
  if (sum <= 0) return prorate(total, List.filled(n, 1));
  final cents = (total * 100).round();
  final exact = [for (final w in ws) cents * w / sum];
  final out = [for (final x in exact) (x + 1e-9).floor()];
  var left = cents - out.fold<int>(0, (a, b) => a + b);
  final order = List.generate(n, (i) => i)
    ..sort((a, b) {
      final ra = exact[a] - (exact[a] + 1e-9).floor();
      final rb = exact[b] - (exact[b] + 1e-9).floor();
      final c = rb.compareTo(ra);
      return c != 0 ? c : a.compareTo(b);
    });
  for (var k = 0; k < order.length && left > 0; k++, left--) {
    out[order[k]] += 1;
  }
  return [for (final c in out) c / 100];
}

String _norm(String s) => s.trim().replaceAll(RegExp(r'\s+'), ' ').toLowerCase();

/// Is the bought thing the item that was requested? (Q10)
enum LineMatch {
  /// The very item, as named on the request.
  same,

  /// The same item, named in other words.
  otherWords,

  /// An important specification differs. Needs a reason; counts only after
  /// the office check.
  substitute;

  static LineMatch parse(String? v) => values.where((m) => m.name == v).firstOrNull ?? same;
}

/// A portion of the request this line buys (0097 portion_picks), with the
/// Still to buy it had when picked (for the preview only — the server
/// decides).
class PortionPick {
  const PortionPick({required this.portionId, required this.quantity, required this.still});
  factory PortionPick.fromJson(Map<String, dynamic> j) => PortionPick(
        portionId: j['portion_id'] as String,
        quantity: (j['quantity'] as num).toDouble(),
        still: (j['still'] as num).toDouble(),
      );
  final String portionId;
  final double quantity;
  final double still;
  Map<String, dynamic> toJson() => {'portion_id': portionId, 'quantity': quantity, 'still': still};
}

/// One line of a purchase being recorded on the phone. Numbers stay the
/// text the buyer typed until sending.
class DraftPurchaseLine {
  const DraftPurchaseLine({
    required this.key,
    this.itemName = '',
    this.quantity = '',
    this.unit = '',
    this.amount = '',
    this.category = '',
    this.destination = 'project',
    this.folderId,
    this.folderLabel = '',
    this.requestLineId,
    this.requestName = '',
    this.requestUnit = '',
    this.picks = const [],
    this.match = LineMatch.same,
    this.substituteReason = '',
    this.unitNote = '',
    this.extraReason = '',
    this.extraLocation,
    this.unplannedReason = '',
  });

  /// A line for request portions picked from the shopping list: the item,
  /// unit and place come from the request; the quantity is what is still to
  /// buy on the picked portions.
  factory DraftPurchaseLine.fromShopping(String key, ShoppingLine line, List<PurPortion> portions) {
    final picks = [
      for (final p in portions)
        if (p.stillToBuy > 0) PortionPick(portionId: p.id, quantity: p.stillToBuy, still: p.stillToBuy),
    ];
    final qty = picks.fold<double>(0, (a, p) => a + p.quantity);
    return DraftPurchaseLine(
      key: key,
      itemName: line.description,
      quantity: qty > 0 ? formatQuantity(qty).replaceAll(',', '') : '',
      unit: line.unit,
      // The Purchasing tab's default: the request's category, else Materials.
      category: line.category.trim().isEmpty ? 'Materials' : line.category,
      folderId: line.workId,
      folderLabel: line.placeLabel,
      requestLineId: line.lineId,
      requestName: line.description,
      requestUnit: line.unit,
      picks: picks,
    );
  }

  factory DraftPurchaseLine.fromJson(Map<String, dynamic> j) => DraftPurchaseLine(
        key: j['key'] as String,
        itemName: (j['item_name'] as String?) ?? '',
        quantity: (j['quantity'] as String?) ?? '',
        unit: (j['unit'] as String?) ?? '',
        amount: (j['amount'] as String?) ?? '',
        category: (j['category'] as String?) ?? '',
        destination: (j['destination'] as String?) ?? 'project',
        folderId: j['folder_id'] as String?,
        folderLabel: (j['folder_label'] as String?) ?? '',
        requestLineId: j['request_line_id'] as String?,
        requestName: (j['request_name'] as String?) ?? '',
        requestUnit: (j['request_unit'] as String?) ?? '',
        picks: [for (final p in (j['picks'] as List<dynamic>? ?? const [])) PortionPick.fromJson(Map<String, dynamic>.from(p as Map))],
        match: LineMatch.parse(j['match'] as String?),
        substituteReason: (j['substitute_reason'] as String?) ?? '',
        unitNote: (j['unit_note'] as String?) ?? '',
        extraReason: (j['extra_reason'] as String?) ?? '',
        extraLocation: j['extra_location'] as String?,
        unplannedReason: (j['unplanned_reason'] as String?) ?? '',
      );

  final String key;
  final String itemName;
  final String quantity;
  final String unit;
  final String amount;
  final String category;

  /// 'project' (a project or one of its jobs, [folderId]) or 'warehouse'.
  final String destination;
  final String? folderId;
  final String folderLabel;
  final String? requestLineId;
  final String requestName;
  final String requestUnit;
  final List<PortionPick> picks;
  final LineMatch match;
  final String substituteReason;

  /// Phone rule (Q10): why a different unit was bought. Kept in the
  /// purchase's notes — the server has no field for it.
  final String unitNote;
  final String extraReason;

  /// Where an extra goes: 'project' or 'warehouse'. Never moves the cost.
  final String? extraLocation;
  final String unplannedReason;

  bool get linked => requestLineId != null;

  /// Same unit as the request and not a substitute: it counts toward Bought
  /// at once; otherwise it waits for the office check (0097 pur_cover_lines).
  bool get countsDirectly => _norm(unit) == _norm(requestUnit) && match != LineMatch.substitute;

  bool get differentUnit => linked && _norm(unit) != _norm(requestUnit);

  /// What the picked portions can still take.
  double get pickedStill => round3(picks.fold<double>(0, (a, p) => a + (p.quantity < p.still ? p.quantity : p.still)));

  /// More than the picked portions still need: an extra (Q11).
  double get extraQuantity {
    if (!linked || !countsDirectly) return 0;
    final q = parseQuantity(quantity) ?? 0;
    return q > pickedStill ? round3(q - pickedStill) : 0;
  }

  DraftPurchaseLine copyWith({
    String? itemName,
    String? quantity,
    String? unit,
    String? amount,
    String? category,
    String? destination,
    Object? folderId = _keep,
    String? folderLabel,
    LineMatch? match,
    String? substituteReason,
    String? unitNote,
    String? extraReason,
    Object? extraLocation = _keep,
    String? unplannedReason,
  }) =>
      DraftPurchaseLine(
        key: key,
        itemName: itemName ?? this.itemName,
        quantity: quantity ?? this.quantity,
        unit: unit ?? this.unit,
        amount: amount ?? this.amount,
        category: category ?? this.category,
        destination: destination ?? this.destination,
        folderId: identical(folderId, _keep) ? this.folderId : folderId as String?,
        folderLabel: folderLabel ?? this.folderLabel,
        requestLineId: requestLineId,
        requestName: requestName,
        requestUnit: requestUnit,
        picks: picks,
        match: match ?? this.match,
        substituteReason: substituteReason ?? this.substituteReason,
        unitNote: unitNote ?? this.unitNote,
        extraReason: extraReason ?? this.extraReason,
        extraLocation: identical(extraLocation, _keep) ? this.extraLocation : extraLocation as String?,
        unplannedReason: unplannedReason ?? this.unplannedReason,
      );

  Map<String, dynamic> toJson() => {
        'key': key,
        'item_name': itemName,
        'quantity': quantity,
        'unit': unit,
        'amount': amount,
        'category': category,
        'destination': destination,
        'folder_id': folderId,
        'folder_label': folderLabel,
        'request_line_id': requestLineId,
        'request_name': requestName,
        'request_unit': requestUnit,
        'picks': [for (final p in picks) p.toJson()],
        'match': match.name,
        'substitute_reason': substituteReason,
        'unit_note': unitNote,
        'extra_reason': extraReason,
        'extra_location': extraLocation,
        'unplanned_reason': unplannedReason,
      };
}

/// A delivery fee or discount (Q9). [shares], when the buyer adjusted the
/// split, holds one typed share per line; otherwise the server splits it by
/// line amount.
class DraftCharge {
  const DraftCharge({required this.kind, this.amount = '', this.shares});
  factory DraftCharge.fromJson(Map<String, dynamic> j) => DraftCharge(
        kind: j['kind'] as String,
        amount: (j['amount'] as String?) ?? '',
        shares: (j['shares'] as List<dynamic>?)?.map((s) => s as String).toList(),
      );
  final String kind;
  final String amount;
  final List<String>? shares;

  bool get isFee => kind == 'delivery_fee';

  DraftCharge copyWith({String? amount, Object? shares = _keep}) => DraftCharge(
        kind: kind,
        amount: amount ?? this.amount,
        shares: identical(shares, _keep) ? this.shares : shares as List<String>?,
      );

  Map<String, dynamic> toJson() => {'kind': kind, 'amount': amount, 'shares': shares};
}

/// Payment methods the Purchasing tab offers ('' = not yet paid / not known).
const paymentMethods = ['Cash', 'GCash', 'Bank transfer', 'Check', 'On account', ''];

/// A purchase being recorded on the phone (Q7–Q11). Saved on the phone as
/// it is typed; sent once, when there is signal.
class PurchaseDraft {
  const PurchaseDraft({
    required this.id,
    required this.createdAt,
    required this.purchaseDate,
    this.supplierId,
    this.supplierName = '',
    this.paymentMethod = 'Cash',
    this.notes = '',
    this.receiptTotal = '',
    this.lines = const [],
    this.charges = const [],
    this.photos = const {},
    this.noReceipt = false,
    this.noReceiptReason = '',
    this.paidNow = 'none',
    this.paidAmount = '',
    this.paidFrom = 'company',
    this.paidMethod = 'cash',
    this.paidCredit,
  });

  factory PurchaseDraft.fromJson(Map<String, dynamic> j) => PurchaseDraft(
        id: j['id'] as String,
        createdAt: DateTime.parse(j['created_at'] as String).toUtc(),
        purchaseDate: j['purchase_date'] as String,
        supplierId: j['supplier_id'] as String?,
        supplierName: (j['supplier_name'] as String?) ?? '',
        paymentMethod: (j['payment_method'] as String?) ?? 'Cash',
        notes: (j['notes'] as String?) ?? '',
        receiptTotal: (j['receipt_total'] as String?) ?? '',
        lines: [for (final l in (j['lines'] as List<dynamic>? ?? const [])) DraftPurchaseLine.fromJson(Map<String, dynamic>.from(l as Map))],
        charges: [for (final c in (j['charges'] as List<dynamic>? ?? const [])) DraftCharge.fromJson(Map<String, dynamic>.from(c as Map))],
        photos: Map<String, String>.from((j['photos'] as Map?) ?? const {}),
        noReceipt: j['no_receipt'] == true,
        noReceiptReason: (j['no_receipt_reason'] as String?) ?? '',
        paidNow: (j['paid_now'] as String?) ?? 'none',
        paidAmount: (j['paid_amount'] as String?) ?? '',
        paidFrom: (j['paid_from'] as String?) ?? 'company',
        paidMethod: (j['paid_method'] as String?) ?? 'cash',
        paidCredit: j['paid_credit'] as String?,
      );

  final String id;
  final DateTime createdAt;

  /// The ACTUAL purchase date, "YYYY-MM-DD" (Manila). It decides which
  /// billing period pays (Stage 2 decision): never the sending date.
  final String purchaseDate;
  final String? supplierId;
  final String supplierName;
  final String paymentMethod;
  final String notes;

  /// The receipt total as printed, typed by the buyer (Q9).
  final String receiptTotal;
  final List<DraftPurchaseLine> lines;
  final List<DraftCharge> charges;

  /// Receipt slot → photo file on the phone (Q8).
  final Map<String, String> photos;
  final bool noReceipt;
  final String noReceiptReason;

  /// "Paid now?" (0102, Q3): 'none' (Not paid yet), 'full' or 'part'. A
  /// payment entered here is recorded in the SAME transaction as the
  /// purchase: both or neither. Later payments go through Record payment.
  final String paidNow;

  /// The part paid, when [paidNow] is 'part'.
  final String paidAmount;

  /// petty_cash · own_money · company · credit (Q5).
  final String paidFrom;
  final String paidMethod;

  /// The supplier credit used, when [paidFrom] is 'credit' (R10).
  final String? paidCredit;

  /// Lines + fees − discounts, from what is typed (blank counts as 0).
  double get computedTotal {
    double v(String s) => parseMoney(s) ?? 0;
    final items = lines.fold<double>(0, (a, l) => a + v(l.amount));
    final fees = charges.where((c) => c.isFee).fold<double>(0, (a, c) => a + v(c.amount));
    final discounts = charges.where((c) => !c.isFee).fold<double>(0, (a, c) => a + v(c.amount));
    return round2(items + fees - discounts);
  }

  PurchaseDraft copyWith({
    String? purchaseDate,
    Object? supplierId = _keep,
    String? supplierName,
    String? paymentMethod,
    String? notes,
    String? receiptTotal,
    List<DraftPurchaseLine>? lines,
    List<DraftCharge>? charges,
    Map<String, String>? photos,
    bool? noReceipt,
    String? noReceiptReason,
    String? paidNow,
    String? paidAmount,
    String? paidFrom,
    String? paidMethod,
    Object? paidCredit = _keep,
  }) =>
      PurchaseDraft(
        id: id,
        createdAt: createdAt,
        purchaseDate: purchaseDate ?? this.purchaseDate,
        supplierId: identical(supplierId, _keep) ? this.supplierId : supplierId as String?,
        supplierName: supplierName ?? this.supplierName,
        paymentMethod: paymentMethod ?? this.paymentMethod,
        notes: notes ?? this.notes,
        receiptTotal: receiptTotal ?? this.receiptTotal,
        lines: lines ?? this.lines,
        charges: charges ?? this.charges,
        photos: photos ?? this.photos,
        noReceipt: noReceipt ?? this.noReceipt,
        noReceiptReason: noReceiptReason ?? this.noReceiptReason,
        paidNow: paidNow ?? this.paidNow,
        paidAmount: paidAmount ?? this.paidAmount,
        paidFrom: paidFrom ?? this.paidFrom,
        paidMethod: paidMethod ?? this.paidMethod,
        paidCredit: identical(paidCredit, _keep) ? this.paidCredit : paidCredit as String?,
      );

  Map<String, dynamic> toJson() => {
        'id': id,
        'created_at': createdAt.toIso8601String(),
        'purchase_date': purchaseDate,
        'supplier_id': supplierId,
        'supplier_name': supplierName,
        'payment_method': paymentMethod,
        'notes': notes,
        'receipt_total': receiptTotal,
        'lines': [for (final l in lines) l.toJson()],
        'charges': [for (final c in charges) c.toJson()],
        'photos': photos,
        'no_receipt': noReceipt,
        'no_receipt_reason': noReceiptReason,
        'paid_now': paidNow,
        'paid_amount': paidAmount,
        'paid_from': paidFrom,
        'paid_method': paidMethod,
        'paid_credit': paidCredit,
      };
}

/// An unsent draft (newest first, as [drafts] come) that already has one of
/// the request items in [picked], or null. Ticking an item again after going
/// back must not quietly start a second purchase of it.
PurchaseDraft? draftWithSameItems(List<PurchaseDraft> drafts, List<DraftPurchaseLine> picked) {
  final wanted = {for (final l in picked) if (l.requestLineId != null) l.requestLineId};
  if (wanted.isEmpty) return null;
  for (final d in drafts) {
    if (d.lines.any((l) => wanted.contains(l.requestLineId))) return d;
  }
  return null;
}

/// [draft] with the picked request items it does not have yet added at the
/// end. Adding a line changes the split, so an adjusted split is redone.
PurchaseDraft withPickedLines(PurchaseDraft draft, List<DraftPurchaseLine> picked) {
  final have = {for (final l in draft.lines) if (l.requestLineId != null) l.requestLineId};
  final added = [for (final l in picked) if (l.requestLineId == null || !have.contains(l.requestLineId)) l];
  if (added.isEmpty) return draft;
  return draft.copyWith(
    lines: [...draft.lines, ...added],
    charges: [for (final c in draft.charges) c.copyWith(shares: null)],
  );
}

/// Something the server would refuse, said before sending. The names follow
/// the server's codes where there is one.
enum ProblemKind {
  badDate,
  noLines,
  tooManyLines,
  badName,
  badQuantity,
  badAmount,
  noProject,
  extraReasonRequired,
  nameDiffers,
  substituteReasonRequired,
  unitNoteRequired,
  unplannedReasonRequired,
  badChargeAmount,
  splitMismatch,
  noReceipt,
  noReceiptReason,
  badTotal,
  totalMismatch,

  // "Paid now?" (0102): the web's paidNowProblems codes.
  paidAmount,
  partNotLess,
  personRequired,
  badPaySource,
  creditRequired,
  overCredit,
}

class PurchaseProblem {
  const PurchaseProblem(this.kind, {this.line, this.charge});
  final ProblemKind kind;

  /// 1-based line or charge number, when the problem is about one.
  final int? line;
  final int? charge;

  @override
  bool operator ==(Object other) => other is PurchaseProblem && other.kind == kind && other.line == line && other.charge == charge;

  @override
  int get hashCode => Object.hash(kind, line, charge);

  @override
  String toString() => 'PurchaseProblem($kind, line: $line, charge: $charge)';
}

/// What would be refused, in form order. The Purchasing tab's formProblems,
/// plus the phone's own rules: a receipt photo or a reason (Q8), the typed
/// total matching the lines (Q9) and a note for a different unit (Q10).
List<PurchaseProblem> purchaseProblems(PurchaseDraft d) {
  final out = <PurchaseProblem>[];
  if (!RegExp(r'^\d{4}-\d{2}-\d{2}$').hasMatch(d.purchaseDate)) out.add(const PurchaseProblem(ProblemKind.badDate));
  if (d.lines.isEmpty) out.add(const PurchaseProblem(ProblemKind.noLines));
  if (d.lines.length > 50) out.add(const PurchaseProblem(ProblemKind.tooManyLines));
  for (var i = 0; i < d.lines.length; i++) {
    final l = d.lines[i];
    final n = i + 1;
    if (l.itemName.trim().isEmpty || l.itemName.trim().length > 200) out.add(PurchaseProblem(ProblemKind.badName, line: n));
    if (parseQuantity(l.quantity) == null) out.add(PurchaseProblem(ProblemKind.badQuantity, line: n));
    if (parseMoney(l.amount) == null) out.add(PurchaseProblem(ProblemKind.badAmount, line: n));
    if (l.destination != 'warehouse' && (l.folderId ?? '').isEmpty) out.add(PurchaseProblem(ProblemKind.noProject, line: n));
    if (l.linked) {
      if (l.extraQuantity > 0 && (l.extraReason.trim().isEmpty || l.extraLocation == null)) {
        out.add(PurchaseProblem(ProblemKind.extraReasonRequired, line: n));
      }
      if (l.match == LineMatch.same && l.requestName.isNotEmpty && _norm(l.itemName) != _norm(l.requestName)) {
        out.add(PurchaseProblem(ProblemKind.nameDiffers, line: n));
      }
      if (l.match == LineMatch.substitute && l.substituteReason.trim().isEmpty) {
        out.add(PurchaseProblem(ProblemKind.substituteReasonRequired, line: n));
      }
      if (l.differentUnit && l.match != LineMatch.substitute && l.unitNote.trim().isEmpty) {
        out.add(PurchaseProblem(ProblemKind.unitNoteRequired, line: n));
      }
    } else if (l.unplannedReason.trim().isEmpty) {
      out.add(PurchaseProblem(ProblemKind.unplannedReasonRequired, line: n));
    }
  }
  for (var i = 0; i < d.charges.length; i++) {
    final c = d.charges[i];
    final amount = parseMoney(c.amount);
    if (amount == null || amount <= 0) out.add(PurchaseProblem(ProblemKind.badChargeAmount, charge: i + 1));
    final shares = c.shares;
    if (amount != null && shares != null && shares.isNotEmpty) {
      final sum = round2(shares.fold<double>(0, (a, s) => a + (parseMoney(s) ?? 0)));
      if (shares.length != d.lines.length || shares.any((s) => parseMoney(s) == null) || sum != round2(amount)) {
        out.add(PurchaseProblem(ProblemKind.splitMismatch, charge: i + 1));
      }
    }
  }
  if (d.noReceipt) {
    if (d.noReceiptReason.trim().isEmpty) out.add(const PurchaseProblem(ProblemKind.noReceiptReason));
  } else if (d.photos.isEmpty) {
    out.add(const PurchaseProblem(ProblemKind.noReceipt));
  }
  final total = parseMoney(d.receiptTotal);
  if (total == null) {
    out.add(const PurchaseProblem(ProblemKind.badTotal));
  } else if (round2(total) != d.computedTotal) {
    out.add(const PurchaseProblem(ProblemKind.totalMismatch));
  }
  return out;
}

/// The payment "Paid now?" adds to the purchase, or null for Not paid yet.
/// Paid in full sends the receipt total; the payment's date is the
/// purchase's own date.
PaymentInput? paidNowPayment(PurchaseDraft d) {
  if (d.paidNow != 'full' && d.paidNow != 'part') return null;
  final total = round2(parseMoney(d.receiptTotal) ?? 0);
  return PaymentInput(
    amount: d.paidNow == 'full' ? total.toStringAsFixed(2) : d.paidAmount,
    paidOn: d.purchaseDate,
    method: d.paidMethod,
    source: d.paidFrom,
    creditId: d.paidFrom == 'credit' ? d.paidCredit : null,
  );
}

/// What "Paid now?" would have refused (the web's paidNowProblems).
/// [holder]: this account holds petty cash (a staff buyer, R2);
/// [creditLeft]: what the chosen credit has left, if known.
List<PurchaseProblem> paidNowProblems(PurchaseDraft d, {required bool holder, double? creditLeft}) {
  final pay = paidNowPayment(d);
  if (pay == null) return const [];
  final out = <PurchaseProblem>[];
  final amount = parseMoney(pay.amount);
  final total = parseMoney(d.receiptTotal) ?? 0;
  if (amount == null || amount <= 0) {
    out.add(const PurchaseProblem(ProblemKind.paidAmount));
  } else if (d.paidNow == 'part' && amount >= total) {
    out.add(const PurchaseProblem(ProblemKind.partNotLess));
  }
  if ((d.paidFrom == 'petty_cash' || d.paidFrom == 'own_money') && !holder) out.add(const PurchaseProblem(ProblemKind.personRequired));
  if (!paySources.contains(d.paidFrom)) out.add(const PurchaseProblem(ProblemKind.badPaySource));
  if (d.paidFrom == 'credit') {
    if ((d.paidCredit ?? '').isEmpty) {
      out.add(const PurchaseProblem(ProblemKind.creditRequired));
    } else if (amount != null && amount > 0 && creditLeft != null && amount > creditLeft) {
      out.add(const PurchaseProblem(ProblemKind.overCredit));
    }
  }
  return out;
}

/// The pur_record body (0096/0097/0101) for a draft that has no problems.
/// [docs]: receipt slot → uploaded link.
Map<String, dynamic> purchaseBody(PurchaseDraft d, {Map<String, String> docs = const {}}) {
  final lines = [
    for (final l in d.lines)
      {
        'destination': l.destination,
        'folder_id': l.destination == 'warehouse' ? null : l.folderId,
        'item_name': l.itemName.trim(),
        'category': l.category,
        'quantity': round3(parseQuantity(l.quantity) ?? 0),
        'unit': l.unit.trim(),
        'amount': round2(parseMoney(l.amount) ?? 0),
        'in_inventory': false,
        'min_stock': 0,
        if (l.linked) ...{
          'request_line_id': l.requestLineId,
          'portion_picks': [
            for (final p in l.picks)
              if (p.quantity > 0) {'portion_id': p.portionId, 'quantity': round3(p.quantity)},
          ],
          'extra_reason': l.extraReason.trim(),
          'extra_location': l.extraLocation,
          'substitute': l.match == LineMatch.substitute,
          'substitute_reason': l.match == LineMatch.substitute ? l.substituteReason.trim() : '',
        } else ...{
          'request_line_id': null,
          'unplanned_reason': l.unplannedReason.trim(),
        },
      },
  ];
  final charges = [
    for (final c in d.charges)
      {
        'kind': c.kind,
        'amount': round2(parseMoney(c.amount) ?? 0),
        if (c.shares != null && c.shares!.isNotEmpty)
          'shares': [for (var i = 0; i < c.shares!.length; i++) {'line': i + 1, 'amount': round2(parseMoney(c.shares![i]) ?? 0)}],
      },
  ];
  // Q10: a different unit's note goes where the office reads it.
  final unitNotes = [
    for (var i = 0; i < d.lines.length; i++)
      if (d.lines[i].differentUnit && d.lines[i].match != LineMatch.substitute && d.lines[i].unitNote.trim().isNotEmpty)
        'Line ${i + 1} (different unit): ${d.lines[i].unitNote.trim()}',
  ];
  final notes = [if (d.notes.trim().isNotEmpty) d.notes.trim(), ...unitNotes].join('\n');
  return {
    'source': 'workmate',
    'purchase_date': d.purchaseDate,
    'date_time': d.purchaseDate,
    'supplier': d.supplierName.trim(),
    'supplier_id': d.supplierId,
    'payment_method': d.paymentMethod.trim(),
    'notes': notes,
    'docs': docs,
    'no_receipt_reason': d.noReceipt ? d.noReceiptReason.trim() : '',
    'receipt_total': round2(parseMoney(d.receiptTotal) ?? 0),
    'lines': lines,
    'charges': charges,
    if (paidNowPayment(d) case final pay?) 'payments': [paymentBody(pay)],
  };
}
