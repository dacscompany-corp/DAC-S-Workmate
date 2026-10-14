/// A task as the worker is shown it (0093 wp_task_doc, worker part): never
/// the office's notes, source passage, flags or anyone's acknowledgements.
/// Quantities and money do not exist here.
library;

enum WpStatus {
  notStarted('not_started'),
  inProgress('in_progress'),
  reportedDone('reported_done'),
  leaderChecked('leader_checked'),
  completed('completed');

  const WpStatus(this.wire);
  final String wire;

  /// Null for a state this build does not know (drafts and cancelled tasks
  /// never reach a worker).
  static WpStatus? parse(String? value) => values.where((s) => s.wire == value).firstOrNull;
}

/// The caller's part in a task. A leader who is also assigned is
/// responsible or helper — the server answers the assignment first.
enum WpRole {
  responsible,
  helper,
  leader;

  static WpRole? parse(String? value) => values.where((r) => r.name == value).firstOrNull;
}

DateTime? _instant(Object? v) => v == null ? null : DateTime.parse(v as String);

List<Map<String, dynamic>> _list(Object? v) => [for (final e in (v as List<dynamic>? ?? const [])) Map<String, dynamic>.from(e as Map)];

class WpPerson {
  const WpPerson({required this.id, required this.name});

  factory WpPerson.fromJson(Map<String, dynamic> j) => WpPerson(id: j['id'] as String, name: (j['name'] as String?) ?? '');

  final String id;
  final String name;
}

/// An open problem. Only the office clears it, after checking (spec §8).
class WpBlocker {
  const WpBlocker({
    required this.id,
    required this.kind,
    required this.description,
    required this.reportedAt,
    required this.reportedBy,
    this.requestId,
  });

  factory WpBlocker.fromJson(Map<String, dynamic> j) => WpBlocker(
        id: j['id'] as String,
        kind: (j['kind'] as String?) ?? 'other',
        description: (j['description'] as String?) ?? '',
        requestId: j['request_id'] as String?,
        reportedAt: DateTime.parse(j['reported_at'] as String),
        reportedBy: (j['reported_by'] as String?) ?? '',
      );

  final String id;

  /// materials / tool / preparation / other.
  final String kind;
  final String description;
  final String? requestId;
  final DateTime reportedAt;
  final String reportedBy;
}

/// An earlier task this one waits for (only unfinished ones are sent).
class WpWaiting {
  const WpWaiting({required this.taskId, required this.title, required this.status});

  factory WpWaiting.fromJson(Map<String, dynamic> j) =>
      WpWaiting(taskId: j['task_id'] as String, title: (j['title'] as String?) ?? '', status: (j['status'] as String?) ?? '');

  final String taskId;
  final String title;
  final String status;
}

/// A photo the server lets THIS worker see (0093 filters them).
class WpPhoto {
  const WpPhoto({required this.id, required this.path, required this.createdAt, this.blockerId, this.eventId});

  factory WpPhoto.fromJson(Map<String, dynamic> j) => WpPhoto(
        id: j['id'] as String,
        path: j['path'] as String,
        blockerId: j['blocker_id'] as String?,
        eventId: (j['event_id'] as num?)?.toInt(),
        createdAt: DateTime.parse(j['created_at'] as String),
      );

  final String id;

  /// Inside the private task-photos bucket.
  final String path;
  final String? blockerId;
  final int? eventId;
  final DateTime createdAt;
}

/// One history line. A worker never sees acknowledgements or proposals here.
class WpEvent {
  const WpEvent({required this.id, required this.kind, required this.note, required this.by, required this.at});

  factory WpEvent.fromJson(Map<String, dynamic> j) => WpEvent(
        id: (j['id'] as num).toInt(),
        kind: (j['kind'] as String?) ?? '',
        note: (j['note'] as String?) ?? '',
        by: (j['by'] as String?) ?? '',
        at: DateTime.parse(j['at'] as String),
      );

  final int id;
  final String kind;
  final String note;
  final String by;
  final DateTime at;
}

class WpTask {
  const WpTask({
    required this.id,
    required this.title,
    required this.instructions,
    required this.projectId,
    required this.projectName,
    required this.workId,
    required this.workName,
    required this.status,
    required this.version,
    required this.myRole,
    this.meetingId,
    this.teamId,
    this.teamName,
    this.sentBack = false,
    this.blocked = false,
    this.plannedStart,
    this.plannedEnd,
    this.versionAt,
    this.completedAt,
    this.responsible,
    this.helpers = const [],
    this.blockers = const [],
    this.waitingFor = const [],
    this.photos = const [],
    this.history = const [],
    this.myAckVersion,
    this.canCheck = false,
  });

  /// Null for a task this build cannot show (an unknown state or role).
  static WpTask? fromJson(Map<String, dynamic> j) {
    final status = WpStatus.parse(j['status'] as String?);
    final role = WpRole.parse(j['my_role'] as String?);
    if (status == null || role == null) return null;
    final resp = j['responsible'];
    return WpTask(
      id: j['id'] as String,
      meetingId: j['meeting_id'] as String?,
      title: (j['title'] as String?) ?? '',
      instructions: (j['instructions'] as String?) ?? '',
      projectId: j['folder_id'] as String,
      projectName: (j['project_name'] as String?) ?? '',
      workId: j['work_id'] as String,
      workName: (j['work_name'] as String?) ?? '',
      teamId: j['team_id'] as String?,
      teamName: j['team_name'] as String?,
      status: status,
      sentBack: j['sent_back'] == true,
      blocked: j['blocked'] == true,
      plannedStart: j['planned_start'] as String?,
      plannedEnd: j['planned_end'] as String?,
      version: (j['version'] as num?)?.toInt() ?? 1,
      versionAt: _instant(j['version_at']),
      completedAt: _instant(j['completed_at']),
      responsible: resp == null ? null : WpPerson.fromJson(Map<String, dynamic>.from(resp as Map)),
      helpers: _list(j['helpers']).map(WpPerson.fromJson).toList(),
      blockers: _list(j['blockers']).map(WpBlocker.fromJson).toList(),
      waitingFor: _list(j['waiting_for']).map(WpWaiting.fromJson).toList(),
      photos: _list(j['photos']).map(WpPhoto.fromJson).toList(),
      history: _list(j['history']).map(WpEvent.fromJson).toList(),
      myRole: role,
      myAckVersion: (j['my_ack_version'] as num?)?.toInt(),
      canCheck: j['can_check'] == true,
    );
  }

  final String id;
  final String? meetingId;
  final String title;
  final String instructions;
  final String projectId;
  final String projectName;
  final String workId;
  final String workName;
  final String? teamId;
  final String? teamName;
  final WpStatus status;

  /// The office sent the reported work back; cleared when it is reported again.
  final bool sentBack;

  /// An open problem or an unfinished earlier task (the server derives it).
  final bool blocked;

  /// Calendar dates ("2026-10-14"), never instants.
  final String? plannedStart;
  final String? plannedEnd;

  /// Rises with every change the people on it must read again.
  final int version;
  final DateTime? versionAt;
  final DateTime? completedAt;
  final WpPerson? responsible;
  final List<WpPerson> helpers;
  final List<WpBlocker> blockers;
  final List<WpWaiting> waitingFor;
  final List<WpPhoto> photos;

  /// Oldest first, as the server sends it.
  final List<WpEvent> history;
  final WpRole myRole;

  /// The newest version this worker acknowledged, or null.
  final int? myAckVersion;

  /// The server's "you may check this reported work" (a current leader, not
  /// assigned to it).
  final bool canCheck;

  /// "Barlin Residence · Main Contract".
  String get where => '$projectName · $workName';

  bool get assigned => myRole == WpRole.responsible || myRole == WpRole.helper;

  /// Assigned and the current version not yet acknowledged.
  bool get needsReading => assigned && (myAckVersion ?? 0) < version;

  /// Read before, but the office has changed it since (spec §7: highlight it).
  bool get changedSinceRead => assigned && myAckVersion != null && myAckVersion! < version;

  /// What the office wrote about the newest revision ("Changed: planned
  /// dates — …"), or null.
  String? get latestChange => history.where((e) => e.kind == 'revised').lastOrNull?.note;
}

/// The latest shared meeting notes this worker was chosen to receive.
class WpNote {
  const WpNote({
    required this.meetingId,
    required this.title,
    required this.heldOn,
    required this.version,
    required this.sharedNotes,
    required this.changeNote,
    required this.publishedAt,
  });

  factory WpNote.fromJson(Map<String, dynamic> j) => WpNote(
        meetingId: j['meeting_id'] as String,
        title: (j['title'] as String?) ?? '',
        heldOn: (j['held_on'] as String?) ?? '',
        version: (j['version'] as num?)?.toInt() ?? 1,
        sharedNotes: (j['shared_notes'] as String?) ?? '',
        changeNote: (j['change_note'] as String?) ?? '',
        publishedAt: DateTime.parse(j['published_at'] as String),
      );

  final String meetingId;
  final String title;

  /// A calendar date.
  final String heldOn;
  final int version;
  final String sharedNotes;
  final String changeNote;
  final DateTime publishedAt;
}

/// A leader's own proposal (0094 wp_my_proposals).
enum WpProposalState {
  sent,
  published,
  declined,
  cancelled;

  static WpProposalState parse(String? value) => values.where((s) => s.name == value).firstOrNull ?? sent;
}

class WpProposal {
  const WpProposal({
    required this.id,
    required this.title,
    required this.projectName,
    required this.workName,
    required this.proposedAt,
    required this.state,
    this.reason,
    this.decidedAt,
  });

  factory WpProposal.fromJson(Map<String, dynamic> j) => WpProposal(
        id: j['id'] as String,
        title: (j['title'] as String?) ?? '',
        projectName: (j['project_name'] as String?) ?? '',
        workName: (j['work_name'] as String?) ?? '',
        proposedAt: DateTime.parse(j['proposed_at'] as String),
        state: WpProposalState.parse(j['status'] as String?),
        reason: j['reason'] as String?,
        decidedAt: _instant(j['decided_at']),
      );

  final String id;
  final String title;
  final String projectName;
  final String workName;
  final DateTime proposedAt;
  final WpProposalState state;

  /// The office's reason, when it declined or cancelled it.
  final String? reason;
  final DateTime? decidedAt;

  String get where => '$projectName · $workName';
}
