import 'quantity.dart';
import 'request_models.dart';

const _keep = Object();

/// One item on a request being prepared on the phone. Quantity stays the
/// text the worker typed until sending, so a half-typed "2." is not lost.
class DraftLine {
  const DraftLine({
    required this.id,
    this.kind = ItemKind.material,
    this.catalogItemId,
    this.description = '',
    this.spec = '',
    this.unit = '',
    this.category = '',
    this.quantity = '',
    this.memberId,
    this.memberName,
    this.urgent = false,
    this.urgentReason = '',
    this.neededBy,
    this.notes = '',
    this.photos = const [],
  });

  /// A line copied from an official catalogue item (spec §4A).
  factory DraftLine.fromCatalog(String id, CatalogItem item) => DraftLine(
        id: id,
        kind: item.kind,
        catalogItemId: item.id,
        description: item.name,
        spec: item.spec,
        unit: item.unit,
        category: item.category,
      );

  factory DraftLine.fromJson(Map<String, dynamic> j) => DraftLine(
        id: j['id'] as String,
        kind: ItemKind.parse(j['kind'] as String?) ?? ItemKind.material,
        catalogItemId: j['catalog_item_id'] as String?,
        description: (j['description'] as String?) ?? '',
        spec: (j['spec'] as String?) ?? '',
        unit: (j['unit'] as String?) ?? '',
        category: (j['category'] as String?) ?? '',
        quantity: (j['quantity'] as String?) ?? '',
        memberId: j['member_id'] as String?,
        memberName: j['member_name'] as String?,
        urgent: j['urgent'] == true,
        urgentReason: (j['urgent_reason'] as String?) ?? '',
        neededBy: j['needed_by'] as String?,
        notes: (j['notes'] as String?) ?? '',
        photos: [for (final p in (j['photos'] as List<dynamic>? ?? const [])) p as String],
      );

  final String id;
  final ItemKind kind;

  /// Set when picked from the catalogue; null for an unlisted item the office
  /// matches later.
  final String? catalogItemId;
  final String description;
  final String spec;
  final String unit;
  final String category;
  final String quantity;

  /// The member a material is for (team requests; a leader may name anyone).
  final String? memberId;
  final String? memberName;
  final bool urgent;
  final String urgentReason;

  /// "2026-10-08" — a calendar date.
  final String? neededBy;
  final String notes;

  /// Prepared JPEGs in app-private storage, sent after the request lands.
  final List<String> photos;

  bool get fromCatalog => catalogItemId != null;

  DraftLine copyWith({
    ItemKind? kind,
    Object? catalogItemId = _keep,
    String? description,
    String? spec,
    String? unit,
    String? category,
    String? quantity,
    Object? memberId = _keep,
    Object? memberName = _keep,
    bool? urgent,
    String? urgentReason,
    Object? neededBy = _keep,
    String? notes,
    List<String>? photos,
  }) =>
      DraftLine(
        id: id,
        kind: kind ?? this.kind,
        catalogItemId: identical(catalogItemId, _keep) ? this.catalogItemId : catalogItemId as String?,
        description: description ?? this.description,
        spec: spec ?? this.spec,
        unit: unit ?? this.unit,
        category: category ?? this.category,
        quantity: quantity ?? this.quantity,
        memberId: identical(memberId, _keep) ? this.memberId : memberId as String?,
        memberName: identical(memberName, _keep) ? this.memberName : memberName as String?,
        urgent: urgent ?? this.urgent,
        urgentReason: urgentReason ?? this.urgentReason,
        neededBy: identical(neededBy, _keep) ? this.neededBy : neededBy as String?,
        notes: notes ?? this.notes,
        photos: photos ?? this.photos,
      );

  Map<String, dynamic> toJson() => {
        'id': id,
        'kind': kind.wire,
        'catalog_item_id': catalogItemId,
        'description': description,
        'spec': spec,
        'unit': unit,
        'category': category,
        'quantity': quantity,
        'member_id': memberId,
        'member_name': memberName,
        'urgent': urgent,
        'urgent_reason': urgentReason,
        'needed_by': neededBy,
        'notes': notes,
        'photos': photos,
      };
}

/// A request being prepared on the phone (spec §4E: works with no signal).
class RequestDraft {
  const RequestDraft({
    required this.id,
    required this.createdAt,
    this.destination,
    this.teamId,
    this.teamName,
    this.note = '',
    this.lines = const [],
  });

  factory RequestDraft.fromJson(Map<String, dynamic> j) => RequestDraft(
        id: j['id'] as String,
        createdAt: DateTime.parse(j['created_at'] as String),
        destination: j['destination'] == null ? null : Destination.fromRow(Map<String, dynamic>.from(j['destination'] as Map)),
        teamId: j['team_id'] as String?,
        teamName: j['team_name'] as String?,
        note: (j['note'] as String?) ?? '',
        lines: [for (final l in (j['lines'] as List<dynamic>? ?? const [])) DraftLine.fromJson(Map<String, dynamic>.from(l as Map))],
      );

  final String id;

  /// When the worker started it: sent as drafted_at, information only — the
  /// SERVER's received time decides the weekly batch (spec §4A).
  final DateTime createdAt;
  final Destination? destination;

  /// Null = an individual request (spec §7: no team needed).
  final String? teamId;
  final String? teamName;
  final String note;
  final List<DraftLine> lines;

  RequestDraft copyWith({
    Object? destination = _keep,
    Object? teamId = _keep,
    Object? teamName = _keep,
    String? note,
    List<DraftLine>? lines,
  }) =>
      RequestDraft(
        id: id,
        createdAt: createdAt,
        destination: identical(destination, _keep) ? this.destination : destination as Destination?,
        teamId: identical(teamId, _keep) ? this.teamId : teamId as String?,
        teamName: identical(teamName, _keep) ? this.teamName : teamName as String?,
        note: note ?? this.note,
        lines: lines ?? this.lines,
      );

  Map<String, dynamic> toJson() => {
        'id': id,
        'created_at': createdAt.toUtc().toIso8601String(),
        'destination': destination?.toRow(),
        'team_id': teamId,
        'team_name': teamName,
        'note': note,
        'lines': [for (final l in lines) l.toJson()],
      };
}

/// The server refuses more than this many lines (0085 TOO_MANY_LINES).
const maxLines = 100;

enum DraftIssueKind {
  noDestination,
  noLines,
  tooManyLines,
  noDescription,
  noUnit,
  badQuantity,
  urgentNeedsReason,
  urgentNeedsDate,
  memberNeedsTeam,
}

/// Something to fix before sending; [line] is the item's index, or null.
class DraftIssue {
  const DraftIssue(this.kind, [this.line]);
  final DraftIssueKind kind;
  final int? line;

  @override
  bool operator ==(Object other) => other is DraftIssue && other.kind == kind && other.line == line;

  @override
  int get hashCode => Object.hash(kind, line);

  @override
  String toString() => line == null ? kind.name : '${kind.name}@$line';
}

/// Every rule the server would refuse the draft on, checked before it is
/// queued: a refusal after the worker left the site costs a second trip.
List<DraftIssue> draftIssues(RequestDraft d) {
  final out = <DraftIssue>[];
  if (d.destination == null) out.add(const DraftIssue(DraftIssueKind.noDestination));
  if (d.lines.isEmpty) out.add(const DraftIssue(DraftIssueKind.noLines));
  if (d.lines.length > maxLines) out.add(const DraftIssue(DraftIssueKind.tooManyLines));
  for (var i = 0; i < d.lines.length; i++) {
    final l = d.lines[i];
    if (l.description.trim().isEmpty) out.add(DraftIssue(DraftIssueKind.noDescription, i));
    if (l.unit.trim().isEmpty) out.add(DraftIssue(DraftIssueKind.noUnit, i));
    if (parseQuantity(l.quantity) == null) out.add(DraftIssue(DraftIssueKind.badQuantity, i));
    if (l.urgent && l.urgentReason.trim().isEmpty) out.add(DraftIssue(DraftIssueKind.urgentNeedsReason, i));
    if (l.urgent && l.neededBy == null) out.add(DraftIssue(DraftIssueKind.urgentNeedsDate, i));
    if (l.memberId != null && d.teamId == null) out.add(DraftIssue(DraftIssueKind.memberNeedsTeam, i));
  }
  return out;
}

/// The p_request argument of pr_submit_request (0085), exactly. Call only
/// when [draftIssues] is empty. An intended member travels on materials only:
/// a tool's responsible person is named at issue (spec §4A).
Map<String, dynamic> submitPayload(RequestDraft d) => {
      'folder_id': d.destination!.projectId,
      'work_id': d.destination!.workId,
      if (d.teamId != null) 'team_id': d.teamId,
      'note': d.note.trim(),
      'drafted_at': d.createdAt.toUtc().toIso8601String(),
      'lines': [
        for (final l in d.lines)
          {
            'kind': l.kind.wire,
            if (l.catalogItemId != null) 'catalog_item_id': l.catalogItemId,
            'description': l.description.trim(),
            'spec': l.spec.trim(),
            'unit': l.unit.trim(),
            'category': l.category.trim(),
            'quantity': parseQuantity(l.quantity),
            if (l.kind == ItemKind.material && l.memberId != null) 'intended_member_id': l.memberId,
            'urgent': l.urgent,
            if (l.urgent) 'urgent_reason': l.urgentReason.trim(),
            if (l.urgent) 'needed_by': l.neededBy,
            'notes': l.notes.trim(),
          },
      ],
    };
