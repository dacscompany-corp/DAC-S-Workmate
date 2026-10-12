import '../../requests/domain/request_models.dart';

// Find Previous Item (Stage 1b, migration 0090). The shapes of what
// pr_history_search / pr_history_item return. No price, amount or cost
// exists anywhere in them: workers never see procurement money.

const _months = ['Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun', 'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec'];

/// "3 Oct 2026", "around Aug 2026" or "Date unknown". A history date is a
/// calendar day (or a month, or unknown): its parts are read, never passed
/// through a time zone (PH is UTC+8 — a shift would move it a day).
String historyDateLabel(String? date, String precision) {
  if (precision == 'unknown' || date == null) return 'Date unknown';
  final m = RegExp(r'^(\d{4})-(\d{2})-(\d{2})$').firstMatch(date);
  if (m == null) return 'Date unknown';
  final month = int.parse(m.group(2)!);
  if (month < 1 || month > 12) return 'Date unknown';
  if (precision == 'approximate') return 'around ${_months[month - 1]} ${m.group(1)}';
  return '${int.parse(m.group(3)!)} ${_months[month - 1]} ${m.group(1)}';
}

/// Main Contract, or the Additional Works job's name.
String historyWhere(String projectName, String workName) => '$projectName · $workName';

/// The newest entry the worker may see for an item (inside the filters).
class HistoryLatest {
  const HistoryLatest({
    required this.entryKind,
    required this.entryId,
    required this.label,
    required this.projectName,
    required this.workName,
    required this.date,
    required this.datePrecision,
  });

  factory HistoryLatest.fromJson(Map<String, dynamic> j) => HistoryLatest(
        entryKind: j['entry_kind'] as String,
        entryId: j['entry_id'] as String,
        label: j['label'] as String,
        projectName: (j['project_name'] as String?) ?? '',
        workName: (j['work_name'] as String?) ?? 'Main Contract',
        date: j['date'] as String?,
        datePrecision: (j['date_precision'] as String?) ?? 'unknown',
      );

  final String entryKind;
  final String entryId;

  /// 'Requested', 'Requested — cancelled' or 'Historical reference'.
  final String label;
  final String projectName;
  final String workName;
  final String? date;
  final String datePrecision;

  Map<String, dynamic> toJson() => {
        'entry_kind': entryKind,
        'entry_id': entryId,
        'label': label,
        'project_name': projectName,
        'work_name': workName,
        'date': date,
        'date_precision': datePrecision,
      };

  /// "Latest: Requested · 3 Oct 2026 · Barlin Residence"
  String get summary => 'Latest: $label · ${historyDateLabel(date, datePrecision)} · $projectName';
}

/// One search result: a catalogue item with history the worker may see.
class HistoryCard {
  const HistoryCard({
    required this.id,
    required this.kind,
    required this.name,
    required this.spec,
    required this.unit,
    required this.category,
    required this.brand,
    required this.aliases,
    required this.active,
    required this.coverPath,
    required this.latest,
  });

  /// Null for a kind this build does not know (it could not be requested).
  static HistoryCard? fromJson(Map<String, dynamic> j) {
    final kind = ItemKind.parse(j['kind'] as String?);
    if (kind == null) return null;
    final latest = j['latest'];
    return HistoryCard(
      id: j['id'] as String,
      kind: kind,
      name: j['name'] as String,
      spec: (j['spec'] as String?) ?? '',
      unit: j['unit'] as String,
      category: (j['category'] as String?) ?? '',
      brand: (j['brand'] as String?) ?? '',
      aliases: [for (final a in (j['aliases'] as List<dynamic>? ?? const [])) a as String],
      active: j['active'] != false,
      coverPath: j['cover_path'] as String?,
      latest: latest == null ? null : HistoryLatest.fromJson(Map<String, dynamic>.from(latest as Map)),
    );
  }

  final String id;
  final ItemKind kind;
  final String name;
  final String spec;
  final String unit;
  final String category;
  final String brand;
  final List<String> aliases;

  /// False: no longer listed — it cannot be requested again.
  final bool active;
  final String? coverPath;
  final HistoryLatest? latest;

  Map<String, dynamic> toJson() => {
        'id': id,
        'kind': kind.wire,
        'name': name,
        'spec': spec,
        'unit': unit,
        'category': category,
        'brand': brand,
        'aliases': aliases,
        'active': active,
        'cover_path': coverPath,
        'latest': latest?.toJson(),
      };
}

/// One page of search results.
class HistoryPage {
  const HistoryPage({required this.items, required this.hasMore, this.savedAt});

  factory HistoryPage.fromJson(Map<String, dynamic> j) => HistoryPage(
        items: [
          for (final i in (j['items'] as List<dynamic>? ?? const []))
            ?HistoryCard.fromJson(Map<String, dynamic>.from(i as Map)),
        ],
        hasMore: j['has_more'] == true,
      );

  final List<HistoryCard> items;
  final bool hasMore;

  /// Set when the page came from what this phone saved (no signal): the
  /// oldest save time among the shown items.
  final DateTime? savedAt;

  bool get fromSaved => savedAt != null;
}

/// An approved product photo (private bucket item-gallery).
class HistoryPhoto {
  const HistoryPhoto({required this.id, required this.path, required this.isCover});

  factory HistoryPhoto.fromJson(Map<String, dynamic> j) =>
      HistoryPhoto(id: j['id'] as String, path: j['path'] as String, isCover: j['is_cover'] == true);

  final String id;
  final String path;
  final bool isCover;

  Map<String, dynamic> toJson() => {'id': id, 'path': path, 'is_cover': isCover};
}

/// One dated line of an item's history.
class HistoryEntry {
  const HistoryEntry({
    required this.entryKind,
    required this.entryId,
    required this.label,
    required this.projectId,
    required this.projectName,
    required this.workName,
    required this.date,
    required this.datePrecision,
    required this.quantity,
    required this.unit,
    required this.description,
    required this.note,
  });

  factory HistoryEntry.fromJson(Map<String, dynamic> j) => HistoryEntry(
        entryKind: j['entry_kind'] as String,
        entryId: j['entry_id'] as String,
        label: j['label'] as String,
        projectId: (j['project_id'] as String?) ?? '',
        projectName: (j['project_name'] as String?) ?? '',
        workName: (j['work_name'] as String?) ?? 'Main Contract',
        date: j['date'] as String?,
        datePrecision: (j['date_precision'] as String?) ?? 'unknown',
        quantity: (j['quantity'] as num?)?.toDouble(),
        unit: j['unit'] as String?,
        description: j['description'] as String?,
        note: j['note'] as String?,
      );

  /// 'request_line' or 'reference' — with [entryId], the Request Again link.
  final String entryKind;
  final String entryId;
  final String label;
  final String projectId;
  final String projectName;
  final String workName;
  final String? date;
  final String datePrecision;

  /// Still-needed quantity of a requested line; null for a cancelled line or a reference.
  final double? quantity;
  final String? unit;

  /// Staff text of a historical reference (null for requests).
  final String? description;
  final String? note;

  /// `request_line:<id>` — the key pr_history_visible returns.
  String get key => '$entryKind:$entryId';

  Map<String, dynamic> toJson() => {
        'entry_kind': entryKind,
        'entry_id': entryId,
        'label': label,
        'project_id': projectId,
        'project_name': projectName,
        'work_name': workName,
        'date': date,
        'date_precision': datePrecision,
        'quantity': quantity,
        'unit': unit,
        'description': description,
        'note': note,
      };
}

/// One item's page: photos (cover first) and entries (newest first).
class HistoryItem {
  const HistoryItem({
    required this.id,
    required this.kind,
    required this.name,
    required this.spec,
    required this.unit,
    required this.category,
    required this.brand,
    required this.aliases,
    required this.active,
    required this.photos,
    required this.entries,
  });

  static HistoryItem? fromJson(Map<String, dynamic> j) {
    final kind = ItemKind.parse(j['kind'] as String?);
    if (kind == null) return null;
    return HistoryItem(
      id: j['id'] as String,
      kind: kind,
      name: j['name'] as String,
      spec: (j['spec'] as String?) ?? '',
      unit: j['unit'] as String,
      category: (j['category'] as String?) ?? '',
      brand: (j['brand'] as String?) ?? '',
      aliases: [for (final a in (j['aliases'] as List<dynamic>? ?? const [])) a as String],
      active: j['active'] != false,
      photos: [for (final p in (j['photos'] as List<dynamic>? ?? const [])) HistoryPhoto.fromJson(Map<String, dynamic>.from(p as Map))],
      entries: [for (final e in (j['entries'] as List<dynamic>? ?? const [])) HistoryEntry.fromJson(Map<String, dynamic>.from(e as Map))],
    );
  }

  final String id;
  final ItemKind kind;
  final String name;
  final String spec;
  final String unit;
  final String category;
  final String brand;
  final List<String> aliases;
  final bool active;
  final List<HistoryPhoto> photos;
  final List<HistoryEntry> entries;

  HistoryItem copyWith({List<HistoryPhoto>? photos, List<HistoryEntry>? entries}) => HistoryItem(
        id: id,
        kind: kind,
        name: name,
        spec: spec,
        unit: unit,
        category: category,
        brand: brand,
        aliases: aliases,
        active: active,
        photos: photos ?? this.photos,
        entries: entries ?? this.entries,
      );

  /// The card search shows for this item when offline.
  HistoryCard toCard() => HistoryCard(
        id: id,
        kind: kind,
        name: name,
        spec: spec,
        unit: unit,
        category: category,
        brand: brand,
        aliases: aliases,
        active: active,
        coverPath: photos.isEmpty ? null : photos.first.path,
        latest: entries.isEmpty
            ? null
            : HistoryLatest(
                entryKind: entries.first.entryKind,
                entryId: entries.first.entryId,
                label: entries.first.label,
                projectName: entries.first.projectName,
                workName: entries.first.workName,
                date: entries.first.date,
                datePrecision: entries.first.datePrecision,
              ),
      );

  Map<String, dynamic> toJson() => {
        'id': id,
        'kind': kind.wire,
        'name': name,
        'spec': spec,
        'unit': unit,
        'category': category,
        'brand': brand,
        'aliases': aliases,
        'active': active,
        'photos': [for (final p in photos) p.toJson()],
        'entries': [for (final e in entries) e.toJson()],
      };
}

/// What "Request this item again" hands to the request being written: the
/// item and the entry the worker recognised. Never a quantity, a price, a
/// purchase or anyone's stock (spec §4.3).
class HistoryPick {
  const HistoryPick({
    required this.itemId,
    required this.kind,
    required this.name,
    required this.spec,
    required this.unit,
    required this.category,
    required this.refKind,
    required this.refId,
    this.coverPath,
  });

  factory HistoryPick.of(HistoryItem item, HistoryEntry entry) => HistoryPick(
        itemId: item.id,
        kind: item.kind,
        name: item.name,
        spec: item.spec,
        unit: item.unit,
        category: item.category,
        refKind: entry.entryKind,
        refId: entry.entryId,
        coverPath: item.photos.isEmpty ? null : item.photos.first.path,
      );

  final String itemId;
  final ItemKind kind;
  final String name;
  final String spec;
  final String unit;
  final String category;
  final String refKind;
  final String refId;
  final String? coverPath;
}

/// The filters of one search (spec §4.3).
class HistoryQuery {
  const HistoryQuery({this.text = '', this.kind, this.category, this.projectId, this.from, this.to});

  final String text;
  final ItemKind? kind;
  final String? category;
  final String? projectId;

  /// "2026-10-01" — calendar days.
  final String? from;
  final String? to;

  HistoryQuery copyWith({
    String? text,
    Object? kind = _keep,
    Object? category = _keep,
    Object? projectId = _keep,
    Object? from = _keep,
    Object? to = _keep,
  }) =>
      HistoryQuery(
        text: text ?? this.text,
        kind: identical(kind, _keep) ? this.kind : kind as ItemKind?,
        category: identical(category, _keep) ? this.category : category as String?,
        projectId: identical(projectId, _keep) ? this.projectId : projectId as String?,
        from: identical(from, _keep) ? this.from : from as String?,
        to: identical(to, _keep) ? this.to : to as String?,
      );

  bool get hasFilters => kind != null || category != null || projectId != null || from != null || to != null;
}

const _keep = Object();
