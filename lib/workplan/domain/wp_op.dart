import 'dart:convert';

/// One My Work change waiting to reach the server (spec §11: acknowledge,
/// report progress and report problems offline; send each once). [opId] is
/// minted once, at enqueue, and reused on every retry: the 0093 RPCs answer a
/// repeated operation id with their first answer.
enum WpOpKind {
  acknowledge,
  start,
  progress,
  blocker,
  done,
  check,
  propose,

  /// A photo for the progress note or problem report [WpOp.parentOpId] made.
  photo;

  static WpOpKind parse(String value) => values.byName(value);
}

class WpOp {
  const WpOp({
    required this.opId,
    required this.workerId,
    required this.kind,
    required this.createdAt,
    this.taskId,
    this.parentOpId,
    this.blockerId,
    this.eventId,
    this.body = const {},
    this.seq = 0,
    this.attempts = 0,
    this.lastError,
    this.failedPermanently = false,
  });

  factory WpOp.fromMap(Map<String, Object?> m) => WpOp(
        opId: m['op_id']! as String,
        workerId: m['worker_id']! as String,
        kind: WpOpKind.parse(m['kind']! as String),
        createdAt: DateTime.fromMillisecondsSinceEpoch(m['created_at']! as int, isUtc: true),
        taskId: m['task_id'] as String?,
        parentOpId: m['parent_op_id'] as String?,
        blockerId: m['blocker_id'] as String?,
        eventId: m['event_id'] as int?,
        body: Map<String, dynamic>.from(jsonDecode(m['body']! as String) as Map),
        seq: (m['seq'] as int?) ?? 0,
        attempts: (m['attempts'] as int?) ?? 0,
        lastError: m['last_error'] as String?,
        failedPermanently: m['failed_permanently'] == 1,
      );

  final String opId;

  /// Who queued it. Every read and every send is scoped to ONE worker: site
  /// phones are shared.
  final String workerId;
  final WpOpKind kind;
  final DateTime createdAt;

  /// The task it is about (null for a proposal).
  final String? taskId;

  /// photo: the progress / problem op it belongs to.
  final String? parentOpId;

  /// photo: filled in when its parent landed — the problem it shows, or the
  /// progress note's history line.
  final String? blockerId;
  final int? eventId;

  /// acknowledge: version; progress / done / check: note; blocker: kind,
  /// description, request_id; propose: team_id, folder_id, work_id, title,
  /// details, project_name, work_name; photo: local_path, photo_id.
  final Map<String, dynamic> body;

  /// Queue order (insertion order).
  final int seq;
  final int attempts;
  final String? lastError;
  final bool failedPermanently;

  int? get version => (body['version'] as num?)?.toInt();
  String get note => (body['note'] as String?) ?? '';
  String? get localPath => body['local_path'] as String?;
  String? get photoId => body['photo_id'] as String?;

  Map<String, Object?> toMap() => {
        'op_id': opId,
        'worker_id': workerId,
        'kind': kind.name,
        'created_at': createdAt.millisecondsSinceEpoch,
        'task_id': taskId,
        'parent_op_id': parentOpId,
        'blocker_id': blockerId,
        'event_id': eventId,
        'body': jsonEncode(body),
        'seq': seq,
        'attempts': attempts,
        'last_error': lastError,
        'failed_permanently': failedPermanently ? 1 : 0,
      };
}
