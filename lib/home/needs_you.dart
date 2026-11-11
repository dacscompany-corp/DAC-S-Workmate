import '../requests/data/requests_api.dart';
import '../requests/domain/request_status.dart';
import '../tools/domain/tool_submission.dart';
import '../workplan/domain/wp_op.dart';
import '../workplan/domain/wp_rules.dart';
import '../workplan/ui/workplan_copy.dart' show opLabel;

/// What a "Needs you" row asks for (redesign spec §5.2), in Home's order.
enum NeedsKind { read, check, notAccepted, fixRequest, finishDraft, toolUnresolved, toolRecords }

/// One thing the worker has to do, with the word on its button.
class NeedsRow {
  const NeedsRow({required this.kind, required this.title, required this.line, required this.action, this.target});

  final NeedsKind kind;
  final String title;
  final String line;

  /// Read, Check, See, Fix or Finish.
  final String action;

  /// The task id (read, check), request entry key (fixRequest, finishDraft)
  /// or operation id (notAccepted, toolUnresolved); null for toolRecords.
  final String? target;

  /// A draft is the worker's own unfinished work, not a problem: grey, not red.
  bool get quiet => kind == NeedsKind.finishDraft;

  /// Unique on Home; the row's key is 'needs-$id'.
  String get id => '${kind.name}-${target ?? 'all'}';
}

class NeedsYou {
  const NeedsYou({required this.rows, required this.allRead});

  final List<NeedsRow> rows;

  /// Every source finished at least one load it can trust (spec §5.3).
  final bool allRead;

  /// "You are all caught up" — only when everything was read.
  bool get caughtUp => allRead && rows.isEmpty;

  /// Nothing known yet: the whole block stays off Home.
  bool get hidden => !allRead && rows.isEmpty;
}

/// Still on this phone (draft, pending, refused send), or the server says it is theirs.
bool isOwnRequest(RequestEntry e) => e.remote == null || e.remote!.mine;

bool _toFix(RequestEntry e) => e.state == SyncState.failed || e.state == SyncState.needsResolution;

/// Own requests the office refused or wants fixed: the Requests tab's red number.
int ownToFix(List<RequestEntry> entries) => entries.where((e) => isOwnRequest(e) && _toFix(e)).length;

String _requestTitle(RequestEntry e) => e.remote?.title ?? e.draft?.destination?.label ?? 'New request';

/// Builds Home's rows from what the controllers already know. A null list
/// means that module is off: read, with nothing to show.
NeedsYou needsYou({
  List<WpEntry>? work,
  List<WpOp> workOtherFailed = const [],
  bool workRead = true,
  List<RequestEntry>? requests,
  bool requestsRead = true,
  List<ToolSubmission>? toolsUnresolved,
  bool toolRecordsNeedChecking = false,
  bool toolsRead = true,
}) {
  final rows = <NeedsRow>[];
  final tasks = work ?? const <WpEntry>[];
  for (final e in tasks) {
    if (!e.toRead) continue;
    rows.add(NeedsRow(
      kind: NeedsKind.read,
      title: e.task.title,
      line: e.task.changedSinceRead ? 'Changed by the office · read it again' : 'New task · read it first',
      action: 'Read',
      target: e.task.id,
    ));
  }
  for (final e in tasks) {
    if (!e.toCheck) continue;
    rows.add(NeedsRow(kind: NeedsKind.check, title: e.task.title, line: 'Reported done · check the work', action: 'Check', target: e.task.id));
  }
  if (work != null) {
    for (final o in [for (final e in tasks) ...e.shownFailures, ...visibleFailures(workOtherFailed)]) {
      rows.add(NeedsRow(kind: NeedsKind.notAccepted, title: opLabel(o), line: 'Not accepted · see why', action: 'See', target: o.opId));
    }
  }
  final entries = requests ?? const <RequestEntry>[];
  for (final e in entries) {
    if (!isOwnRequest(e) || !_toFix(e)) continue;
    rows.add(NeedsRow(
      kind: NeedsKind.fixRequest,
      title: 'Request · ${_requestTitle(e)}',
      line: e.state == SyncState.needsResolution ? 'Needs resolution · check it and send again' : 'Not accepted · check it and send again',
      action: 'Fix',
      target: e.key,
    ));
  }
  for (final e in entries) {
    if (e.state != SyncState.draft) continue;
    final n = e.draft?.lines.length ?? 0;
    rows.add(NeedsRow(
      kind: NeedsKind.finishDraft,
      title: 'Draft · ${e.draft?.destination?.label ?? 'New request'}',
      line: '$n item${n == 1 ? '' : 's'} · not sent yet',
      action: 'Finish',
      target: e.key,
    ));
  }
  for (final s in toolsUnresolved ?? const <ToolSubmission>[]) {
    rows.add(NeedsRow(
      kind: NeedsKind.toolUnresolved,
      title: s.summary.isEmpty ? 'Tool record' : s.summary,
      line: 'Not confirmed · Send again or Check',
      action: 'Check',
      target: s.opId,
    ));
  }
  if (toolRecordsNeedChecking) {
    rows.add(const NeedsRow(kind: NeedsKind.toolRecords, title: 'Saved tool records', line: 'Need checking', action: 'Check'));
  }
  final allRead = (work == null || workRead) && (requests == null || requestsRead) && (toolsUnresolved == null || toolsRead);
  return NeedsYou(rows: rows, allRead: allRead);
}
