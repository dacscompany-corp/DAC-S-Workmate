/// What the stock server functions (0104, 0105) return, as the phone reads
/// it. QUANTITIES ONLY (Q26, Q28): no peso is read from any answer — a cost
/// move's value, which owner accounts are sent, is never parsed here.
library;

double _num(Object? v) => switch (v) {
      num n => n.toDouble(),
      String s => double.tryParse(s) ?? 0,
      _ => 0,
    };

String _str(Object? v) => v == null ? '' : v.toString();

DateTime? _time(Object? v) => v == null ? null : DateTime.tryParse(v.toString())?.toUtc();

List<Map<String, dynamic>> _rows(Object? v) => [for (final r in (v as List<dynamic>? ?? const [])) Map<String, dynamic>.from(r as Map)];

/// `stk_status()`: stock is usable here only when [enabled] (switched on AND
/// this account may record stock).
class StockStatus {
  const StockStatus({this.enabled = false, this.canRecord = false});

  factory StockStatus.fromJson(Map<String, dynamic> j) =>
      StockStatus(enabled: j['enabled'] == true, canRecord: j['can_record'] == true);

  final bool enabled;
  final bool canRecord;

  static const off = StockStatus();
}

/// A catalogue item stock can be recorded in (`stk_choices().items`).
class StockItemChoice {
  const StockItemChoice({required this.itemId, required this.name, this.spec = '', this.unit = ''});

  factory StockItemChoice.fromJson(Map<String, dynamic> j) =>
      StockItemChoice(itemId: _str(j['item_id']), name: _str(j['name']), spec: _str(j['spec']), unit: _str(j['unit']));

  final String itemId;
  final String name;
  final String spec;
  final String unit;

  /// "Cement — Portland (bag)".
  String get label => '$name${spec.trim().isEmpty ? '' : ' — $spec'} ($unit)';
}

/// A project (Main Contract or an Additional Works job) goods can go to.
class StockProject {
  const StockProject({required this.folderId, required this.name, this.main = true, this.completed = false});

  factory StockProject.fromJson(Map<String, dynamic> j) =>
      StockProject(folderId: _str(j['folder_id']), name: _str(j['name']), main: j['main'] != false, completed: j['completed'] == true);

  final String folderId;
  final String name;
  final bool main;

  /// Goods can still be recorded there (Q16); the cost move waits for the owner.
  final bool completed;

  String get label => completed ? '$name (completed)' : name;
}

class StockChoices {
  const StockChoices({this.items = const [], this.projects = const []});

  factory StockChoices.fromJson(Map<String, dynamic> j) => StockChoices(
        items: _rows(j['items']).map(StockItemChoice.fromJson).toList(),
        projects: _rows(j['projects']).map(StockProject.fromJson).toList(),
      );

  final List<StockItemChoice> items;
  final List<StockProject> projects;

  StockItemChoice? item(String? id) => items.where((i) => i.itemId == id).firstOrNull;

  /// Open projects first, then completed ones (marked), as the web lists them.
  List<StockProject> get projectsInOrder => [...projects.where((p) => !p.completed), ...projects.where((p) => p.completed)];
}

/// Where some of an item is, and how much.
class StockPlace {
  const StockPlace({required this.name, required this.kind, this.folderId, this.quantity = 0});

  factory StockPlace.fromJson(Map<String, dynamic> j) =>
      StockPlace(name: _str(j['name']), kind: _str(j['kind']), folderId: j['folder_id'] as String?, quantity: _num(j['quantity']));

  final String name;

  /// 'warehouse' or 'site'.
  final String kind;
  final String? folderId;
  final double quantity;

  bool get isWarehouse => kind == 'warehouse';
}

/// One item with stock somewhere (`stk_overview().items`).
class StockItem {
  const StockItem({required this.itemId, required this.name, this.spec = '', this.unit = '', this.total = 0, this.places = const []});

  factory StockItem.fromJson(Map<String, dynamic> j) => StockItem(
        itemId: _str(j['item_id']),
        name: _str(j['name']),
        spec: _str(j['spec']),
        unit: _str(j['unit']),
        total: _num(j['total']),
        places: _rows(j['places']).map(StockPlace.fromJson).toList(),
      );

  final String itemId;
  final String name;
  final String spec;
  final String unit;
  final double total;
  final List<StockPlace> places;

  double get inWarehouse => places.where((p) => p.isWarehouse).fold(0, (s, p) => s + p.quantity);

  /// How much is at one place: 'warehouse' or a project's folder id.
  double at(String place) => place == warehousePlace
      ? inWarehouse
      : places.where((p) => !p.isWarehouse && p.folderId == place).fold(0, (s, p) => s + p.quantity);
}

/// The warehouse as a place to pick, beside projects' folder ids.
const warehousePlace = 'warehouse';

/// A purchase line as stock sees it (0104 `stk_line_json`): a warehouse line
/// awaiting delivery, or a project line whose leftovers can be recorded.
class StockLine {
  const StockLine({
    required this.purchaseId,
    required this.lineNo,
    this.destination = '',
    this.folderId,
    this.folderName = '',
    this.itemName = '',
    this.unit = '',
    this.quantity = 0,
    this.purchaseDate = '',
    this.boughtByName = '',
    this.received = 0,
    this.notDelivered = 0,
    this.awaiting = 0,
    this.entered = 0,
    this.match,
  });

  factory StockLine.fromJson(Map<String, dynamic> j) => StockLine(
        purchaseId: _str(j['purchase_id']),
        lineNo: _num(j['line_no']).toInt(),
        destination: _str(j['destination']),
        folderId: j['folder_id'] as String?,
        folderName: _str(j['folder_name']),
        itemName: _str(j['item_name']),
        unit: _str(j['unit']),
        quantity: _num(j['quantity']),
        purchaseDate: _str(j['purchase_date']),
        boughtByName: _str(j['bought_by_name']),
        received: _num(j['received']),
        notDelivered: _num(j['not_delivered']),
        awaiting: _num(j['awaiting']),
        entered: _num(j['entered']),
        match: j['match'] == null ? null : StockMatch.fromJson(Map<String, dynamic>.from(j['match'] as Map)),
      );

  final String purchaseId;
  final int lineNo;
  final String destination;
  final String? folderId;
  final String folderName;
  final String itemName;

  /// The purchase line's own unit (receipts are counted in it, Q6).
  final String unit;
  final double quantity;
  final String purchaseDate;
  final String boughtByName;
  final double received;
  final double notDelivered;
  final double awaiting;

  /// Item units already entered as stock (leftovers, opening stock).
  final double entered;

  /// How the line counts as a catalogue item; null = the office matches it first.
  final StockMatch? match;

  String get key => '$purchaseId:$lineNo';

  /// Leftovers still recordable, in item units — never more than the line
  /// brought (MORE_THAN_BOUGHT), the same rounding as the server's.
  double get leftoverRoom {
    final m = match;
    if (m == null || m.per <= 0) return 0;
    final total = (quantity * m.covers / m.per * 1000).roundToDouble() / 1000;
    final room = ((total - entered) * 1000).roundToDouble() / 1000;
    return room < 0 ? 0 : room;
  }
}

class StockMatch {
  const StockMatch({required this.itemId, this.itemName = '', this.itemUnit = '', this.per = 1, this.covers = 1});

  factory StockMatch.fromJson(Map<String, dynamic> j) => StockMatch(
        itemId: _str(j['item_id']),
        itemName: _str(j['item_name']),
        itemUnit: _str(j['item_unit']),
        per: _num(j['per']),
        covers: _num(j['covers']),
      );

  final String itemId;
  final String itemName;
  final String itemUnit;
  final double per;
  final double covers;
}

/// A cost move's STATE under a record (0105) — never its value.
class StockCostState {
  const StockCostState({required this.kind, required this.status, this.reversed = false});

  factory StockCostState.fromJson(Map<String, dynamic> j) =>
      StockCostState(kind: _str(j['kind']), status: _str(j['status']), reversed: j['reversed'] == true);

  final String kind;
  final String status;
  final bool reversed;
}

/// One stock record (0104/0105 `stk_record_json`), quantities only.
class StockRecord {
  const StockRecord({
    required this.id,
    required this.kind,
    this.status = 'done',
    this.itemId,
    this.itemName = '',
    this.itemUnit = '',
    this.lineItem = '',
    this.lineUnit = '',
    this.fromName = '',
    this.toName = '',
    this.quantity = 0,
    this.bookQuantity,
    this.on = '',
    this.requestDescription = '',
    this.unplannedReason = '',
    this.reason = '',
    this.note = '',
    this.recordedBy = '',
    this.recordedByName = '',
    this.recordedAt,
    this.reversed = false,
    this.returnable = 0,
    this.costs = const [],
  });

  factory StockRecord.fromJson(Map<String, dynamic> j) => StockRecord(
        id: _str(j['id']),
        kind: _str(j['kind']),
        status: _str(j['status']),
        itemId: j['item_id'] as String?,
        itemName: _str(j['item_name']),
        itemUnit: _str(j['item_unit']),
        lineItem: _str(j['line_item']),
        lineUnit: _str(j['line_unit']),
        fromName: _str(j['from_name']),
        toName: _str(j['to_name']),
        quantity: _num(j['quantity']),
        bookQuantity: j['book_quantity'] == null ? null : _num(j['book_quantity']),
        on: _str(j['on']),
        requestDescription: _str(j['request_description']),
        unplannedReason: _str(j['unplanned_reason']),
        reason: _str(j['reason']),
        note: _str(j['note']),
        recordedBy: _str(j['recorded_by']),
        recordedByName: _str(j['recorded_by_name']),
        recordedAt: _time(j['recorded_at']),
        reversed: j['reversed'] == true,
        returnable: _num(j['returnable']),
        costs: _rows(j['costs']).map(StockCostState.fromJson).toList(),
      );

  final String id;

  /// receive, not_delivered, leftover, issue, return, move, count, opening.
  final String kind;
  final String status;
  final String? itemId;
  final String itemName;
  final String itemUnit;
  final String lineItem;
  final String lineUnit;
  final String fromName;
  final String toName;
  final double quantity;
  final double? bookQuantity;
  final String on;
  final String requestDescription;
  final String unplannedReason;
  final String reason;
  final String note;
  final String recordedBy;
  final String recordedByName;
  final DateTime? recordedAt;
  final bool reversed;

  /// An issue's quantity not yet returned (0 for anything else).
  final double returnable;
  final List<StockCostState> costs;

  /// Receipts are counted in the purchase line's unit, the rest in the item's.
  String get unit => kind == 'receive' || kind == 'not_delivered' ? lineUnit : itemUnit;
  String get what => itemName.isNotEmpty ? itemName : (lineItem.isNotEmpty ? lineItem : 'Item');
  bool get canReturn => kind == 'issue' && status == 'done' && !reversed && returnable > 0;
}

/// `stk_overview()`: the Stock screen in one read.
class StockOverview {
  const StockOverview({this.items = const [], this.awaiting = const [], this.recent = const []});

  factory StockOverview.fromJson(Map<String, dynamic> j) => StockOverview(
        items: _rows(j['items']).map(StockItem.fromJson).toList(),
        awaiting: _rows(j['awaiting']).map(StockLine.fromJson).toList(),
        recent: _rows(j['recent']).map(StockRecord.fromJson).toList(),
      );

  final List<StockItem> items;

  /// Warehouse lines awaiting delivery or a match.
  final List<StockLine> awaiting;

  /// The latest 50 records, newest first.
  final List<StockRecord> recent;

  StockItem? item(String? id) => items.where((i) => i.itemId == id).firstOrNull;
}

/// A request line goods going to a project can fill (`stk_request_lines`).
class StockRequestLine {
  const StockRequestLine({
    required this.lineId,
    this.description = '',
    this.spec = '',
    this.unit = '',
    this.catalogItemId,
    this.requesterName = '',
    this.stillToBuy = 0,
  });

  factory StockRequestLine.fromJson(Map<String, dynamic> j) => StockRequestLine(
        lineId: _str(j['line_id']),
        description: _str(j['description']),
        spec: _str(j['spec']),
        unit: _str(j['unit']),
        catalogItemId: j['catalog_item_id'] as String?,
        requesterName: _str(j['requester_name']),
        stillToBuy: _num(j['still_to_buy']),
      );

  final String lineId;
  final String description;
  final String spec;
  final String unit;
  final String? catalogItemId;
  final String requesterName;
  final double stillToBuy;

  /// The server's rule (ITEM_MISMATCH, UNIT_MISMATCH): the item's own request
  /// line, or one with no catalogue item, in the same unit.
  bool fits(StockItemChoice item) =>
      (catalogItemId == null || catalogItemId == item.itemId) && unit.trim().toLowerCase() == item.unit.trim().toLowerCase();
}
