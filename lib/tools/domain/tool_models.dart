/// A tool's condition: the four 0107 knows (Q16).
enum ToolCondition {
  good('good'),
  needsRepair('needs_repair'),
  missingParts('missing_parts'),
  damaged('damaged');

  const ToolCondition(this.code);
  final String code;

  static ToolCondition? byCode(Object? code) => values.where((c) => c.code == code).firstOrNull;
}

/// What a worker can report about a tool they hold (Q12). It changes no
/// tool, holder or record: the office reads it and closes it with a note.
enum ProblemKind {
  dontHave('dont_have'),
  broken('broken');

  const ProblemKind(this.code);
  final String code;

  static ProblemKind? byCode(Object? code) => values.where((k) => k.code == code).firstOrNull;
}

String _text(Object? v) => v is String ? v : '';
String? _maybe(Object? v) => v is String ? v : null;
DateTime? _time(Object? v) => v is String ? DateTime.tryParse(v) : null;
List<Map<String, dynamic>> _rows(Object? v) => [for (final r in (v as List<dynamic>? ?? const [])) Map<String, dynamic>.from(r as Map)];

/// One tool as 0111 shows it on the phone (`tl_phone_tool_json`): its
/// number, item, details and custody — never a peso, a purchase, an office
/// note or a photo. [raw] is the server's own answer, kept for the saved copy.
class PhoneTool {
  const PhoneTool({
    required this.raw,
    required this.id,
    required this.label,
    required this.itemName,
    this.itemSpec = '',
    this.details = '',
    this.state,
    this.condition,
    this.holderId,
    this.holderName,
    this.folderId,
    this.folderName,
    this.since,
    this.days,
    this.myOpenProblems = const [],
    this.records = const [],
  });

  factory PhoneTool.fromJson(Map<String, dynamic> j) => PhoneTool(
        raw: j,
        id: j['id'] as String,
        label: _text(j['label']),
        itemName: _text(j['item_name']),
        itemSpec: _text(j['item_spec']),
        details: _text(j['details']),
        state: _maybe(j['state']),
        condition: ToolCondition.byCode(j['condition']),
        holderId: _maybe(j['holder_id']),
        holderName: _maybe(j['holder_name']),
        folderId: _maybe(j['folder_id']),
        folderName: _maybe(j['folder_name']),
        since: _time(j['since']),
        days: (j['days'] as num?)?.toInt(),
        myOpenProblems: [for (final k in (j['my_open_problems'] as List<dynamic>? ?? const [])) ?ProblemKind.byCode(k)],
        records: _rows(j['records']).map(ToolRecord.fromJson).toList(),
      );

  final Map<String, dynamic> raw;
  final String id;

  /// "TOOL-0001".
  final String label;
  final String itemName;
  final String itemSpec;
  final String details;

  /// Null for a tool the caller once had and no longer holds: its history
  /// shows, nobody's custody does.
  final String? state;
  final ToolCondition? condition;
  final String? holderId;
  final String? holderName;
  final String? folderId;
  final String? folderName;
  final DateTime? since;

  /// Whole days in its state, by the Philippine calendar (`tl_days`).
  final int? days;

  /// The caller's own reports still open on it (My tools only).
  final List<ProblemKind> myOpenProblems;

  /// Its records while the person had it, newest first (one tool's page).
  final List<ToolRecord> records;

  /// "Grinder · 18V".
  String get name => itemSpec.trim().isEmpty ? itemName : '$itemName · ${itemSpec.trim()}';
  bool get isIssued => state == 'issued';
  bool get lostPending => state == 'lost_pending';

  /// Someone holds it now (issued, or reported lost and waiting for the owner).
  bool get held => isIssued || lostPending;
}

/// One record of a tool, as a worker or leader may see it (`tl_person_records`).
class ToolRecord {
  const ToolRecord({
    required this.kind,
    required this.status,
    this.at,
    this.folderName,
    this.condition,
    this.reversed = false,
    this.fromName,
    this.toName,
  });

  factory ToolRecord.fromJson(Map<String, dynamic> j) => ToolRecord(
        kind: _text(j['kind']),
        status: _text(j['status']),
        at: _time(j['at']),
        folderName: _maybe(j['folder_name']),
        condition: ToolCondition.byCode(j['condition']),
        reversed: j['reversed'] == true,
        fromName: _maybe(j['from_name']),
        toName: _maybe(j['to_name']),
      );

  /// register, issue, handover, return, repaired, lost, found, retire.
  final String kind;

  /// done, pending (waiting for the owner), rejected, withdrawn.
  final String status;
  final DateTime? at;
  final String? folderName;
  final ToolCondition? condition;
  final bool reversed;

  /// A handover: who passed it to them, or who they passed it to.
  final String? fromName;
  final String? toName;
}

/// The tool a leader typed the number of: Available, in their company
/// (`tl_team_find`). Anything else is one refusal (TOOL_NOT_AVAILABLE).
class FoundTool {
  const FoundTool({required this.id, required this.label, required this.itemName, this.itemSpec = '', this.details = ''});

  factory FoundTool.fromJson(Map<String, dynamic> j) => FoundTool(
        id: j['id'] as String,
        label: _text(j['label']),
        itemName: _text(j['item_name']),
        itemSpec: _text(j['item_spec']),
        details: _text(j['details']),
      );

  final String id;
  final String label;
  final String itemName;
  final String itemSpec;
  final String details;

  String get name => itemSpec.trim().isEmpty ? itemName : '$itemName · ${itemSpec.trim()}';
}

class TeamMember {
  const TeamMember({required this.id, required this.name});
  factory TeamMember.fromJson(Map<String, dynamic> j) => TeamMember(id: j['id'] as String, name: _text(j['name']));

  final String id;

  /// "Amy (W-0001)".
  final String name;
}

class ToolProject {
  const ToolProject({required this.folderId, required this.name, this.main = true});
  factory ToolProject.fromJson(Map<String, dynamic> j) =>
      ToolProject(folderId: j['folder_id'] as String, name: _text(j['name']), main: j['main'] != false);

  final String folderId;

  /// "House", or "House — Fence" for a part of a project.
  final String name;
  final bool main;
}

/// Who a leader may record for (the current members of the teams they lead
/// now), and the open projects: names only (`tl_team_choices`).
class TeamChoices {
  const TeamChoices({this.members = const [], this.projects = const []});

  factory TeamChoices.fromJson(Map<String, dynamic> j) => TeamChoices(
        members: _rows(j['members']).map(TeamMember.fromJson).toList(),
        projects: _rows(j['projects']).map(ToolProject.fromJson).toList(),
      );

  final List<TeamMember> members;
  final List<ToolProject> projects;

  TeamMember? member(String? id) => members.where((m) => m.id == id).firstOrNull;
  ToolProject? project(String? id) => projects.where((p) => p.folderId == id).firstOrNull;
}

/// A tool request line this tool can fill on a project, that the leader can
/// already see (`tl_team_request_lines`). Lines it was bought for come first.
class ToolRequestLine {
  const ToolRequestLine({
    required this.lineId,
    required this.description,
    this.spec = '',
    this.unit = '',
    this.requesterName = '',
    this.stillToFill = 0,
    this.boughtForThisTool = false,
  });

  factory ToolRequestLine.fromJson(Map<String, dynamic> j) => ToolRequestLine(
        lineId: j['line_id'] as String,
        description: _text(j['description']),
        spec: _text(j['spec']),
        unit: _text(j['unit']),
        requesterName: _text(j['requester_name']),
        stillToFill: (j['still_to_fill'] as num?)?.toDouble() ?? 0,
        boughtForThisTool: j['bought_for_this_tool'] == true,
      );

  final String lineId;
  final String description;
  final String spec;
  final String unit;
  final String requesterName;
  final double stillToFill;
  final bool boughtForThisTool;
}

/// One of a leader's own recent issues, handovers and returns
/// (`tl_team_my_records`). [canReverse] is the server's word on Undo.
class LeaderRecord {
  const LeaderRecord({
    required this.raw,
    required this.id,
    required this.toolId,
    required this.label,
    required this.itemName,
    required this.kind,
    this.at,
    this.reversed = false,
    this.holderName,
    this.folderName,
    this.canReverse = false,
  });

  factory LeaderRecord.fromJson(Map<String, dynamic> j) => LeaderRecord(
        raw: j,
        id: j['id'] as String,
        toolId: _text(j['tool_id']),
        label: _text(j['label']),
        itemName: _text(j['item_name']),
        kind: _text(j['kind']),
        at: _time(j['at']),
        reversed: j['reversed'] == true,
        holderName: _maybe(j['holder_name']),
        folderName: _maybe(j['folder_name']),
        canReverse: j['can_reverse'] == true,
      );

  final Map<String, dynamic> raw;
  final String id;
  final String toolId;
  final String label;
  final String itemName;

  /// issue, handover or return.
  final String kind;
  final DateTime? at;
  final bool reversed;
  final String? holderName;
  final String? folderName;
  final bool canReverse;
}
