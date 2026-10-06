import 'request_models.dart';

/// A request as the server keeps it (0085 pr_my_requests). Quantities only —
/// no price, amount or cost exists in these tables.
double _num(Object? v) => (v as num?)?.toDouble() ?? 0;

/// One weekly-batch share of a line's quantity (spec §4A: 10 this week plus
/// 2 next week are two portions with their own dates).
class Portion {
  const Portion({
    required this.quantity,
    required this.pendingReduction,
    required this.arranged,
    required this.cutoffAt,
    required this.purchaseOn,
    required this.deliveryOn,
  });

  factory Portion.fromJson(Map<String, dynamic> j) => Portion(
        quantity: _num(j['quantity']),
        pendingReduction: _num(j['pending_reduction']),
        arranged: j['arranged'] == true,
        cutoffAt: DateTime.parse(j['cutoff_at'] as String),
        purchaseOn: j['purchase_on'] as String,
        deliveryOn: j['delivery_on'] as String,
      );

  final double quantity;

  /// Arranged quantity the worker no longer needs; the office resolves it.
  final double pendingReduction;

  /// The office has arranged this quantity for purchase.
  final bool arranged;
  final DateTime cutoffAt;

  /// Calendar dates ("2026-10-12"), never instants.
  final String purchaseOn;
  final String deliveryOn;
}

class RemoteLine {
  const RemoteLine({
    required this.id,
    required this.position,
    required this.kind,
    required this.description,
    required this.unit,
    required this.version,
    required this.needed,
    this.catalogItemId,
    this.spec = '',
    this.category = '',
    this.intendedMemberName,
    this.urgent = false,
    this.urgentReason,
    this.neededBy,
    this.notes = '',
    this.cancelled = false,
    this.hasConflict = false,
    this.portions = const [],
  });

  factory RemoteLine.fromJson(Map<String, dynamic> j) => RemoteLine(
        id: j['id'] as String,
        position: (j['position'] as num).toInt(),
        kind: ItemKind.parse(j['kind'] as String?) ?? ItemKind.material,
        catalogItemId: j['catalog_item_id'] as String?,
        description: j['description'] as String,
        spec: (j['spec'] as String?) ?? '',
        unit: j['unit'] as String,
        category: (j['category'] as String?) ?? '',
        intendedMemberName: j['intended_member_name'] as String?,
        urgent: j['urgent'] == true,
        urgentReason: j['urgent_reason'] as String?,
        neededBy: j['needed_by'] as String?,
        notes: (j['notes'] as String?) ?? '',
        cancelled: j['status'] == 'cancelled',
        version: (j['version'] as num).toInt(),
        hasConflict: j['has_conflict'] == true,
        needed: _num(j['needed']),
        portions: [
          for (final p in (j['portions'] as List<dynamic>? ?? const [])) Portion.fromJson(Map<String, dynamic>.from(p as Map)),
        ],
      );

  final String id;
  final int position;
  final ItemKind kind;
  final String? catalogItemId;
  final String description;
  final String spec;
  final String unit;
  final String category;
  final String? intendedMemberName;
  final bool urgent;
  final String? urgentReason;
  final String? neededBy;
  final String notes;
  final bool cancelled;

  /// Rises on every change; an edit made against an older version becomes a
  /// conflict for the office instead of an overwrite (spec §4E).
  final int version;
  final bool hasConflict;

  /// Still needed: Σ(quantity − pending reduction).
  final double needed;
  final List<Portion> portions;
}

class RemotePhoto {
  const RemotePhoto({required this.id, required this.path, this.lineId});

  factory RemotePhoto.fromJson(Map<String, dynamic> j) =>
      RemotePhoto(id: j['id'] as String, lineId: j['line_id'] as String?, path: j['path'] as String);

  final String id;
  final String? lineId;

  /// Inside the private request-photos bucket.
  final String path;
}

class RemoteRequest {
  const RemoteRequest({
    required this.id,
    required this.receivedAt,
    required this.mine,
    required this.requesterName,
    required this.projectId,
    required this.projectName,
    required this.workId,
    required this.workName,
    this.cancelled = false,
    this.draftedAt,
    this.note = '',
    this.teamId,
    this.teamName,
    this.lines = const [],
    this.photos = const [],
  });

  factory RemoteRequest.fromJson(Map<String, dynamic> j) => RemoteRequest(
        id: j['id'] as String,
        cancelled: j['status'] == 'cancelled',
        receivedAt: DateTime.parse(j['received_at'] as String),
        draftedAt: j['drafted_at'] == null ? null : DateTime.parse(j['drafted_at'] as String),
        note: (j['note'] as String?) ?? '',
        mine: j['mine'] == true,
        requesterName: (j['requester_name'] as String?) ?? '',
        projectId: j['project_id'] as String,
        projectName: (j['project_name'] as String?) ?? '',
        workId: j['work_id'] as String,
        workName: (j['work_name'] as String?) ?? '',
        teamId: j['team_id'] as String?,
        teamName: j['team_name'] as String?,
        lines: [for (final l in (j['lines'] as List<dynamic>? ?? const [])) RemoteLine.fromJson(Map<String, dynamic>.from(l as Map))],
        photos: [for (final p in (j['photos'] as List<dynamic>? ?? const [])) RemotePhoto.fromJson(Map<String, dynamic>.from(p as Map))],
      );

  final String id;
  final bool cancelled;
  final DateTime receivedAt;
  final DateTime? draftedAt;
  final String note;

  /// False for a team member's request a leader is shown (read-only to them).
  final bool mine;
  final String requesterName;
  final String projectId;
  final String projectName;
  final String workId;
  final String workName;
  final String? teamId;
  final String? teamName;
  final List<RemoteLine> lines;
  final List<RemotePhoto> photos;

  /// "Santos Townhouse · Main Contract".
  String get title => '$projectName · $workName';
}
