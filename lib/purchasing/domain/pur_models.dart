/// What the purchasing server functions (0097, 0101) return, as the phone
/// reads it. Numbers arrive as JSON numbers or numeric text; both are read.
library;

import 'pay_models.dart' show PayState;

double _num(Object? v) => switch (v) {
      num n => n.toDouble(),
      String s => double.tryParse(s) ?? 0,
      _ => 0,
    };

String _str(Object? v) => v == null ? '' : v.toString();

DateTime? _time(Object? v) => v == null ? null : DateTime.tryParse(v.toString())?.toUtc();

List<Map<String, dynamic>> _rows(Object? v) => [for (final r in (v as List<dynamic>? ?? const [])) Map<String, dynamic>.from(r as Map)];

/// One weekly batch (0086 `pr_office_batches`).
class PurBatch {
  const PurBatch({required this.id, required this.cutoffAt, this.purchaseOn, this.deliveryOn});

  factory PurBatch.fromJson(Map<String, dynamic> j) => PurBatch(
        id: _str(j['id']),
        cutoffAt: _time(j['cutoff_at']) ?? DateTime.utc(1970),
        purchaseOn: j['purchase_on'] as String?,
        deliveryOn: j['delivery_on'] as String?,
      );

  final String id;
  final DateTime cutoffAt;
  final String? purchaseOn;
  final String? deliveryOn;

  Map<String, dynamic> toJson() =>
      {'id': id, 'cutoff_at': cutoffAt.toIso8601String(), 'purchase_on': purchaseOn, 'delivery_on': deliveryOn};

  /// "This week" (Q4): the first batch whose cutoff is still ahead — the
  /// rule the Purchasing tab uses for its default batch.
  static PurBatch? current(List<PurBatch> batches, DateTime now) {
    final ahead = batches.where((b) => b.cutoffAt.isAfter(now)).toList()..sort((a, b) => a.cutoffAt.compareTo(b.cutoffAt));
    return ahead.firstOrNull;
  }
}

/// One portion of a request line (0097 `pur_shopping_list` → portions).
class PurPortion {
  const PurPortion({
    required this.id,
    required this.batchId,
    this.cutoffAt,
    this.quantity = 0,
    this.pendingReduction = 0,
    this.bought = 0,
    this.stillToBuy = 0,
    this.arranged = false,
    this.buyerId,
    this.buyerName,
    this.mine = false,
    this.changed = false,
  });

  factory PurPortion.fromJson(Map<String, dynamic> j) => PurPortion(
        id: _str(j['id']),
        batchId: _str(j['batch_id']),
        cutoffAt: _time(j['cutoff_at']),
        quantity: _num(j['quantity']),
        pendingReduction: _num(j['pending_reduction']),
        bought: _num(j['bought']),
        stillToBuy: _num(j['still_to_buy']),
        arranged: j['arranged'] == true,
        buyerId: j['buyer_id'] as String?,
        buyerName: j['buyer_name'] as String?,
        mine: j['mine'] == true,
        changed: j['changed'] == true,
      );

  final String id;
  final String batchId;
  final DateTime? cutoffAt;
  final double quantity;
  final double pendingReduction;
  final double bought;
  final double stillToBuy;
  final bool arranged;
  final String? buyerId;
  final String? buyerName;
  final bool mine;

  /// The request's quantity changed after this portion was assigned.
  final bool changed;

  bool get unassigned => buyerId == null;

  Map<String, dynamic> toJson() => {
        'id': id,
        'batch_id': batchId,
        'cutoff_at': cutoffAt?.toIso8601String(),
        'quantity': quantity,
        'pending_reduction': pendingReduction,
        'bought': bought,
        'still_to_buy': stillToBuy,
        'arranged': arranged,
        'buyer_id': buyerId,
        'buyer_name': buyerName,
        'mine': mine,
        'changed': changed,
      };
}

/// One request line still to buy (0097 `pur_shopping_list`).
class ShoppingLine {
  const ShoppingLine({
    required this.lineId,
    required this.requestId,
    this.description = '',
    this.spec = '',
    this.unit = '',
    this.category = '',
    this.urgent = false,
    this.urgentReason = '',
    this.neededBy,
    this.notes = '',
    this.projectId = '',
    this.projectName = '',
    this.workId = '',
    this.workName = '',
    this.requesterName = '',
    this.needed = 0,
    this.bought = 0,
    this.stillToBuy = 0,
    this.unitChecks = 0,
    this.portions = const [],
  });

  factory ShoppingLine.fromJson(Map<String, dynamic> j) => ShoppingLine(
        lineId: _str(j['line_id']),
        requestId: _str(j['request_id']),
        description: _str(j['description']),
        spec: _str(j['spec']),
        unit: _str(j['unit']),
        category: _str(j['category']),
        urgent: j['urgent'] == true,
        urgentReason: _str(j['urgent_reason']),
        neededBy: j['needed_by'] as String?,
        notes: _str(j['notes']),
        projectId: _str(j['project_id']),
        projectName: _str(j['project_name']),
        workId: _str(j['work_id']),
        workName: _str(j['work_name']),
        requesterName: _str(j['requester_name']),
        needed: _num(j['needed']),
        bought: _num(j['bought']),
        stillToBuy: _num(j['still_to_buy']),
        unitChecks: _num(j['unit_checks']).toInt(),
        portions: _rows(j['portions']).map(PurPortion.fromJson).toList(),
      );

  final String lineId;
  final String requestId;
  final String description;
  final String spec;
  final String unit;
  final String category;
  final bool urgent;
  final String urgentReason;
  final String? neededBy;
  final String notes;
  final String projectId;
  final String projectName;

  /// The project or Additional Works job the request is for — where a
  /// purchase for it must go (0097 BAD_REQUEST_LINK otherwise).
  final String workId;
  final String workName;
  final String requesterName;
  final double needed;
  final double bought;
  final double stillToBuy;
  final int unitChecks;
  final List<PurPortion> portions;

  Map<String, dynamic> toJson() => {
        'line_id': lineId,
        'request_id': requestId,
        'description': description,
        'spec': spec,
        'unit': unit,
        'category': category,
        'urgent': urgent,
        'urgent_reason': urgentReason,
        'needed_by': neededBy,
        'notes': notes,
        'project_id': projectId,
        'project_name': projectName,
        'work_id': workId,
        'work_name': workName,
        'requester_name': requesterName,
        'needed': needed,
        'bought': bought,
        'still_to_buy': stillToBuy,
        'unit_checks': unitChecks,
        'portions': [for (final p in portions) p.toJson()],
      };

  /// "Santos Townhouse · AW-03 Fence"; the main contract shows the project alone.
  String get placeLabel => workName.isEmpty || workName == 'Main Contract' ? projectName : '$projectName · $workName';
}

/// An Additional Works job under an open project (0101 `pur_destinations`).
class PurWork {
  const PurWork({required this.folderId, required this.name});
  factory PurWork.fromJson(Map<String, dynamic> j) => PurWork(folderId: _str(j['folder_id']), name: _str(j['name']));
  final String folderId;
  final String name;
  Map<String, dynamic> toJson() => {'folder_id': folderId, 'name': name};
}

/// An open project a phone purchase may go to, with its open jobs (Q11).
class PurDestination {
  const PurDestination({required this.folderId, required this.name, this.works = const []});
  factory PurDestination.fromJson(Map<String, dynamic> j) => PurDestination(
        folderId: _str(j['folder_id']),
        name: _str(j['name']),
        works: _rows(j['works']).map(PurWork.fromJson).toList(),
      );
  final String folderId;
  final String name;
  final List<PurWork> works;
  Map<String, dynamic> toJson() => {'folder_id': folderId, 'name': name, 'works': [for (final w in works) w.toJson()]};
}

/// A supplier from the company's list (0097 `pur_suppliers`).
class Supplier {
  const Supplier({required this.id, required this.name, this.branch = '', this.active = true});
  factory Supplier.fromJson(Map<String, dynamic> j) =>
      Supplier(id: _str(j['id']), name: _str(j['name']), branch: _str(j['branch']), active: j['active'] != false);
  final String id;
  final String name;
  final String branch;
  final bool active;

  /// How the server writes it on the purchase: "Name · Branch".
  String get label => branch.isEmpty ? name : '$name · $branch';
  Map<String, dynamic> toJson() => {'id': id, 'name': name, 'branch': branch, 'active': active};
}

/// One row of My purchases (0101 `pur_my_purchases` → `pur_list_doc`).
class MyPurchase {
  const MyPurchase({
    required this.id,
    required this.status,
    this.source = '',
    this.purchaseDate = '',
    this.supplier = '',
    this.receiptTotal = 0,
    this.projects = const [],
    this.warehouse = false,
    this.lines = 0,
    this.unplanned = false,
    this.extra = false,
    this.unitCheck = false,
    this.needsReview = false,
    this.pendingChange = false,
    this.noReceiptReason = '',
    this.replacedBy,
    this.supplierId,
    this.pay = const PayState(),
  });

  factory MyPurchase.fromJson(Map<String, dynamic> j) => MyPurchase(
        id: _str(j['id']),
        status: _str(j['status']),
        source: _str(j['source']),
        purchaseDate: _str(j['purchase_date']),
        supplier: _str(j['supplier']),
        receiptTotal: _num(j['receipt_total']),
        projects: [for (final p in (j['projects'] as List<dynamic>? ?? const [])) p.toString()],
        warehouse: j['warehouse'] == true,
        lines: _num(j['lines']).toInt(),
        unplanned: j['unplanned'] == true,
        extra: j['extra'] == true,
        unitCheck: j['unit_check'] == true,
        needsReview: j['needs_review'] == true,
        pendingChange: j['pending_change'] == true,
        noReceiptReason: _str(j['no_receipt_reason']),
        replacedBy: j['replaced_by'] as String?,
        supplierId: j['supplier_id'] as String?,
        pay: PayState.fromJson(j['pay'] == null ? null : Map<String, dynamic>.from(j['pay'] as Map)),
      );

  final String id;
  final String status;
  final String source;
  final String purchaseDate;
  final String supplier;
  final double receiptTotal;
  final List<String> projects;
  final bool warehouse;
  final int lines;
  final bool unplanned;
  final bool extra;
  final bool unitCheck;
  final bool needsReview;
  final bool pendingChange;
  final String noReceiptReason;
  final String? replacedBy;

  /// The listed supplier (0103), for paying from that supplier's credit.
  final String? supplierId;

  /// How it is paid (0102): Unpaid / Partially paid / Paid / Overpaid.
  final PayState pay;

  bool get voided => status == 'void';
}

/// A fee or discount on a stored purchase, with its split by line number.
class PurchaseCharge {
  const PurchaseCharge({required this.kind, required this.amount, this.shares = const {}});
  factory PurchaseCharge.fromJson(Map<String, dynamic> j) => PurchaseCharge(
        kind: _str(j['kind']),
        amount: _num(j['amount']),
        shares: {for (final s in _rows(j['shares'])) _num(s['line']).toInt(): _num(s['amount'])},
      );
  final String kind;
  final double amount;

  /// line number (1-based) → share.
  final Map<int, double> shares;
}

/// One line of a stored purchase (0097 `pur_doc` → lines).
class PurchaseLine {
  const PurchaseLine({
    required this.line,
    this.destination = 'project',
    this.folderId,
    this.folderName = '',
    this.itemName = '',
    this.category = '',
    this.quantity = 0,
    this.unit = '',
    this.amount = 0,
    this.requestLineId,
    this.covered = 0,
    this.extra = 0,
    this.unitCheck = 'none',
    this.unplannedReason = '',
    this.substitute = false,
    this.inInventory = false,
    this.minStock = 0,
  });

  factory PurchaseLine.fromJson(Map<String, dynamic> j) => PurchaseLine(
        line: _num(j['line']).toInt(),
        destination: _str(j['destination']).isEmpty ? 'project' : _str(j['destination']),
        folderId: j['folder_id'] as String?,
        folderName: _str(j['folder_name']),
        itemName: _str(j['item_name']),
        category: _str(j['category']),
        quantity: _num(j['quantity']),
        unit: _str(j['unit']),
        amount: _num(j['amount']),
        requestLineId: j['request_line_id'] as String?,
        covered: _num(j['covered']),
        extra: _num(j['extra']),
        unitCheck: _str(j['unit_check']).isEmpty ? 'none' : _str(j['unit_check']),
        unplannedReason: _str(j['unplanned_reason']),
        substitute: j['substitute'] == true,
        inInventory: j['in_inventory'] == true,
        minStock: _num(j['min_stock']),
      );

  final int line;
  final String destination;
  final String? folderId;
  final String folderName;
  final String itemName;
  final String category;
  final double quantity;
  final String unit;
  final double amount;
  final String? requestLineId;
  final double covered;
  final double extra;

  /// 'none' | 'pending' | 'confirmed' — a different unit or a substitute
  /// counts toward its request only after the office check.
  final String unitCheck;
  final String unplannedReason;
  final bool substitute;

  /// Kept as stored by a correction (stock is the office's, Stage 2B).
  final bool inInventory;
  final double minStock;
}

/// A change sent to the owner about a purchase.
class PurchaseChangeRequest {
  const PurchaseChangeRequest({required this.kind, required this.status, this.reason = '', this.decisionNote = ''});
  factory PurchaseChangeRequest.fromJson(Map<String, dynamic> j) => PurchaseChangeRequest(
      kind: _str(j['kind']), status: _str(j['status']), reason: _str(j['reason']), decisionNote: _str(j['decision_note']));
  final String kind;
  final String status;
  final String reason;
  final String decisionNote;
}

/// The four receipt photo slots a purchase keeps (0096 docs) — the same four
/// the Purchasing tab offers.
const receiptSlots = ['supplier_invoice_url', 'payment_receipt_url', 'delivery_receipt_url', 'po_image_url'];

/// One purchase in full (0097 `pur_purchase` → `pur_purchase_view`, 0101).
class PurchaseDetail {
  const PurchaseDetail({
    required this.id,
    required this.status,
    this.source = '',
    this.purchaseDate = '',
    this.dateTime = '',
    this.supplier = '',
    this.supplierId,
    this.boughtBy,
    this.receiptTotal = 0,
    this.notes = '',
    this.paymentMethod = '',
    this.docs = const {},
    this.lines = const [],
    this.charges = const [],
    this.recordedByName = '',
    this.boughtByName = '',
    this.noReceiptReason = '',
    this.replacedBy,
    this.changeRequests = const [],
  });

  factory PurchaseDetail.fromJson(Map<String, dynamic> j) => PurchaseDetail(
        id: _str(j['id']),
        status: _str(j['status']),
        source: _str(j['source']),
        purchaseDate: _str(j['purchase_date']),
        dateTime: _str(j['date_time']),
        supplier: _str(j['supplier']),
        supplierId: j['supplier_id'] as String?,
        boughtBy: j['bought_by'] as String?,
        receiptTotal: _num(j['receipt_total']),
        notes: _str(j['notes']),
        paymentMethod: _str(j['payment_method']),
        docs: {
          for (final e in Map<String, dynamic>.from((j['docs'] as Map?) ?? const {}).entries)
            if (receiptSlots.contains(e.key) && e.value is String && (e.value as String).isNotEmpty) e.key: e.value as String,
        },
        lines: _rows(j['lines']).map(PurchaseLine.fromJson).toList(),
        charges: _rows(j['charges']).map(PurchaseCharge.fromJson).toList(),
        recordedByName: _str(j['recorded_by_name']),
        boughtByName: _str(j['bought_by_name']),
        noReceiptReason: _str(j['no_receipt_reason']),
        replacedBy: j['replaced_by'] as String?,
        changeRequests: _rows(j['change_requests']).map(PurchaseChangeRequest.fromJson).toList(),
      );

  final String id;
  final String status;
  final String source;
  final String purchaseDate;
  final String dateTime;
  final String supplier;
  final String? supplierId;
  final String? boughtBy;
  final double receiptTotal;
  final String notes;
  final String paymentMethod;

  /// slot → stored link (public-format URL in the private `uploads` bucket).
  final Map<String, String> docs;
  final List<PurchaseLine> lines;
  final List<PurchaseCharge> charges;
  final String recordedByName;
  final String boughtByName;
  final String noReceiptReason;
  final String? replacedBy;
  final List<PurchaseChangeRequest> changeRequests;

  bool get recorded => status == 'recorded';
  bool get waitingForOwner => changeRequests.any((r) => r.status == 'pending');
  bool get needsOfficeCheck => lines.any((l) => l.unitCheck == 'pending');
}
