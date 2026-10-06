import 'dart:convert';

/// One change waiting to reach the server (spec §4E: "send each operation
/// once"). [opId] is minted once, at enqueue, and reused on every retry; the
/// 0085 RPCs answer a repeated op id with their first answer.
enum OpKind {
  submit,
  photo,
  quantity,
  cancelLine,
  cancelRequest;

  static OpKind parse(String value) => values.byName(value);
}

class RequestOp {
  const RequestOp({
    required this.opId,
    required this.workerId,
    required this.kind,
    required this.createdAt,
    this.draftId,
    this.requestId,
    this.lineId,
    this.linePosition,
    this.body = const {},
    this.baseVersion,
    this.seq = 0,
    this.attempts = 0,
    this.lastError,
    this.failedPermanently = false,
  });

  factory RequestOp.fromMap(Map<String, Object?> m) => RequestOp(
        opId: m['op_id']! as String,
        workerId: m['worker_id']! as String,
        kind: OpKind.parse(m['kind']! as String),
        createdAt: DateTime.fromMillisecondsSinceEpoch(m['created_at']! as int, isUtc: true),
        draftId: m['draft_id'] as String?,
        requestId: m['request_id'] as String?,
        lineId: m['line_id'] as String?,
        linePosition: m['line_position'] as int?,
        body: Map<String, dynamic>.from(jsonDecode(m['body']! as String) as Map),
        baseVersion: m['base_version'] as int?,
        seq: (m['seq'] as int?) ?? 0,
        attempts: (m['attempts'] as int?) ?? 0,
        lastError: m['last_error'] as String?,
        failedPermanently: m['failed_permanently'] == 1,
      );

  final String opId;

  /// Who queued it. Every read and every send is scoped to ONE worker: site
  /// phones are shared (spec §4E).
  final String workerId;
  final OpKind kind;
  final DateTime createdAt;

  /// The draft a submit (and its photos) came from.
  final String? draftId;

  /// The server's request; set on a photo op once its submit has landed.
  final String? requestId;
  final String? lineId;

  /// A photo's item index in its draft, resolved to [lineId] at landing.
  final int? linePosition;

  /// submit: the pr_submit_request payload; photo: local_path + photo_id;
  /// quantity: quantity.
  final Map<String, dynamic> body;

  /// quantity: the line version this edit was made against.
  final int? baseVersion;

  /// Queue order (insertion order).
  final int seq;
  final int attempts;
  final String? lastError;
  final bool failedPermanently;

  double? get quantity => (body['quantity'] as num?)?.toDouble();
  String? get localPath => body['local_path'] as String?;
  String? get photoId => body['photo_id'] as String?;

  Map<String, Object?> toMap() => {
        'op_id': opId,
        'worker_id': workerId,
        'kind': kind.name,
        'created_at': createdAt.millisecondsSinceEpoch,
        'draft_id': draftId,
        'request_id': requestId,
        'line_id': lineId,
        'line_position': linePosition,
        'body': jsonEncode(body),
        'base_version': baseVersion,
        'seq': seq,
        'attempts': attempts,
        'last_error': lastError,
        'failed_permanently': failedPermanently ? 1 : 0,
      };
}

bool _bumpsVersion(RequestOp o) => o.kind == OpKind.quantity || o.kind == OpKind.cancelLine;

/// The base version for a new edit of [lineId]: the version the worker saw,
/// plus every edit of that line still waiting to be sent — the worker made
/// this edit on top of those (the 1a-1 carry-over: chain queued edits).
int predictedBase(int seenVersion, Iterable<RequestOp> queued, String lineId) =>
    seenVersion + queued.where((o) => !o.failedPermanently && o.lineId == lineId && _bumpsVersion(o)).length;

/// After an edit of [lineId] answered: the base the next waiting edit of that
/// line must carry, by op id. Applied → the next edit sits on the server's new
/// version. Conflict → every later edit was made on a value the office never
/// saw, so each must also arrive as a conflict (base 0 never matches: versions
/// start at 1). [later] is the queue after the answered op, in order.
Map<String, int> rebaseAfter(List<RequestOp> later, String lineId, Map<String, dynamic> result) {
  final edits = later.where((o) => o.kind == OpKind.quantity && o.lineId == lineId && !o.failedPermanently).toList();
  if (edits.isEmpty) return const {};
  if (result['status'] == 'conflict') return {for (final o in edits) o.opId: 0};
  final version = (result['version'] as num?)?.toInt();
  if (version == null) return const {};
  return {edits.first.opId: version};
}

/// After an edit of a line was refused for good: it changed nothing on the
/// server, so the next waiting edit of that line sits on the refused edit's
/// own base, not on the +1 it was predicted with.
Map<String, int> rebaseAfterRefusal(List<RequestOp> later, RequestOp refused) {
  final base = refused.baseVersion;
  if (refused.kind != OpKind.quantity || refused.lineId == null || base == null) return const {};
  final next =
      later.where((o) => o.kind == OpKind.quantity && o.lineId == refused.lineId && !o.failedPermanently).firstOrNull;
  return next == null ? const {} : {next.opId: base};
}
