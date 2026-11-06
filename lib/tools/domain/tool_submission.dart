import 'dart:convert';

/// The five tool writes the phone makes, by their server function (0111).
/// The office's own functions (tl_issue, …) are never called from the phone.
enum ToolWrite {
  issue('tl_team_issue'),
  handover('tl_team_handover'),
  giveBack('tl_team_return'),
  undo('tl_team_reverse'),
  report('tl_report_problem');

  const ToolWrite(this.fn);
  final String fn;

  static ToolWrite? byFn(String fn) => values.where((w) => w.fn == fn).firstOrNull;
}

/// One tool record sent from the phone (Q22): its operation id and its exact
/// payload travel together and never change. It is kept on the phone from the
/// moment before it is first sent until the SERVER settles it — a reply, a
/// refusal of its first Send, or the server confirming the id was recorded or
/// is cancelled for good. The same rule as stock (R101–R104).
class ToolSubmission {
  const ToolSubmission({
    required this.opId,
    required this.userId,
    required this.write,
    required this.payload,
    required this.summary,
    required this.createdAt,
    this.lastSentAt,
    this.sends = 0,
  });

  /// [params] are the server call's parameters, `p_op` included.
  factory ToolSubmission.create({
    required String opId,
    required String userId,
    required ToolWrite write,
    required Map<String, dynamic> params,
    required String summary,
    required DateTime now,
  }) {
    if (params['p_op'] != opId) throw ArgumentError('the payload carries its own operation id');
    return ToolSubmission(opId: opId, userId: userId, write: write, payload: jsonEncode(params), summary: summary, createdAt: now);
  }

  static ToolSubmission? fromJson(Map<String, dynamic> j) {
    final write = ToolWrite.byFn(j['fn'] as String? ?? '');
    final opId = j['op_id'] as String?;
    final userId = j['user_id'] as String?;
    final payload = j['payload'] as String?;
    if (write == null || opId == null || userId == null || payload == null) return null;
    final params = jsonDecode(payload);
    if (params is! Map || params['p_op'] != opId) return null;
    return ToolSubmission(
      opId: opId,
      userId: userId,
      write: write,
      payload: payload,
      summary: j['summary'] as String? ?? '',
      createdAt: DateTime.parse(j['created_at'] as String),
      lastSentAt: j['last_sent_at'] == null ? null : DateTime.parse(j['last_sent_at'] as String),
      sends: (j['sends'] as num?)?.toInt() ?? 0,
    );
  }

  final String opId;

  /// The account that sent it; nobody else sees, sends or checks it.
  final String userId;
  final ToolWrite write;

  /// The exact parameters sent, as JSON text — every Send again decodes
  /// this, never the form.
  final String payload;

  /// What it was, in words ("Issued TOOL-0003 Grinder to Ben (W-0002)").
  final String summary;
  final DateTime createdAt;

  /// The last time it left the phone (set just before sending).
  final DateTime? lastSentAt;
  final int sends;

  Map<String, dynamic> get params => Map<String, dynamic>.from(jsonDecode(payload) as Map);

  ToolSubmission sentAt(DateTime t) => ToolSubmission(
        opId: opId,
        userId: userId,
        write: write,
        payload: payload,
        summary: summary,
        createdAt: createdAt,
        lastSentAt: t,
        sends: sends + 1,
      );

  Map<String, dynamic> toJson() => {
        'op_id': opId,
        'user_id': userId,
        'fn': write.fn,
        'payload': payload,
        'summary': summary,
        'created_at': createdAt.toUtc().toIso8601String(),
        'last_sent_at': lastSentAt?.toUtc().toIso8601String(),
        'sends': sends,
      };
}
