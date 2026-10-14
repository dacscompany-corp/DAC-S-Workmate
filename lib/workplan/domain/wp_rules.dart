import 'wp_op.dart';
import 'wp_task.dart';

/// Refused operations as the worker reads them: a photo refused only because
/// its report was refused is part of that report, not a second refusal.
List<WpOp> visibleFailures(List<WpOp> failed) =>
    failed.where((o) => o.kind != WpOpKind.photo || !failed.any((p) => p.opId == o.parentOpId)).toList();

/// Unsent operations as the worker reads them: a report and its photo are
/// one item while both wait; a photo still waiting after its report landed
/// is an item of its own.
List<WpOp> visiblePending(List<WpOp> pending) =>
    pending.where((o) => o.kind != WpOpKind.photo || !pending.any((p) => p.opId == o.parentOpId)).toList();

/// One My Work row: the server's task plus what this phone still owes the
/// server about it — so the screen never claims more than is true.
class WpEntry {
  const WpEntry({required this.task, this.pendingOps = const [], this.failedOps = const []});

  final WpTask task;
  final List<WpOp> pendingOps;
  final List<WpOp> failedOps;

  bool pending(WpOpKind kind) => pendingOps.any((o) => o.kind == kind);

  /// What to show as refused (see [visibleFailures]).
  List<WpOp> get shownFailures => visibleFailures(failedOps);

  /// What to show as still on the phone (see [visiblePending]).
  List<WpOp> get shownPending => visiblePending(pendingOps);

  /// "I've read this" is waiting to be sent for THIS version.
  bool get ackPending => pendingOps.any((o) => o.kind == WpOpKind.acknowledge && o.version == task.version);

  /// The current version still needs this worker's "I've read this".
  bool get toRead => task.needsReading && !ackPending;

  /// Reported work this leader may check, not already checked from this phone.
  bool get toCheck => task.canCheck && task.status == WpStatus.reportedDone && !pending(WpOpKind.check);

  /// The state this phone's queued actions will lead to, for the buttons.
  WpStatus get effectiveStatus {
    if (pending(WpOpKind.check)) return WpStatus.leaderChecked;
    if (pending(WpOpKind.done)) return WpStatus.reportedDone;
    if (pending(WpOpKind.start) && task.status == WpStatus.notStarted) return WpStatus.inProgress;
    return task.status;
  }

  /// Blocked as last read, or a problem reported from this phone that the
  /// office has not cleared yet (spec §14: a new problem locks Report done).
  bool get blocked => task.blocked || pending(WpOpKind.blocker);
}

/// Why Start work / Report done is locked, or null when it is not.
enum WpLock { blocked, mustRead }

/// What the worker can do now.
class WpActions {
  const WpActions({
    this.acknowledge = false,
    this.start = false,
    this.startLock,
    this.progress = false,
    this.problem = false,
    this.done = false,
    this.doneLock,
    this.check = false,
  });

  final bool acknowledge;

  /// Shown (enabled or locked) to the responsible person of a not-started task.
  final bool start;
  final WpLock? startLock;
  final bool progress;
  final bool problem;

  /// Shown (enabled or locked) to the responsible person of a task in progress.
  final bool done;
  final WpLock? doneLock;
  final bool check;
}

/// The rules of 0093, applied on the phone so a worker is never offered an
/// action the server would refuse. The server re-checks every one at send.
WpActions actionsFor(WpEntry e) {
  final t = e.task;
  final status = e.effectiveStatus;
  final responsible = t.myRole == WpRole.responsible;
  // Reading comes first: an offline Start after a revision must show the new
  // instructions before anything else (0093 NOT_ACKNOWLEDGED).
  final mustRead = e.toRead;
  final open = status != WpStatus.completed;
  return WpActions(
    acknowledge: e.toRead,
    start: responsible && status == WpStatus.notStarted,
    startLock: e.blocked ? WpLock.blocked : (mustRead ? WpLock.mustRead : null),
    progress: responsible && (status == WpStatus.notStarted || status == WpStatus.inProgress),
    // Anyone with a role, until the office approves it (0093 wp_report_blocker).
    problem: open,
    done: responsible && status == WpStatus.inProgress,
    doneLock: e.blocked ? WpLock.blocked : null,
    check: e.toCheck,
  );
}

/// The My Work sections (spec §12: Today / Upcoming / Waiting).
enum WpGroup { today, upcoming, waiting, done }

/// [today] is Manila's calendar date ("2026-10-14").
WpGroup groupOf(WpEntry e, String today) {
  final t = e.task;
  final status = e.effectiveStatus;
  if (status == WpStatus.completed) return WpGroup.done;
  if (e.toRead || e.toCheck) return WpGroup.today;
  if (e.blocked || status == WpStatus.reportedDone || status == WpStatus.leaderChecked) return WpGroup.waiting;
  final start = t.plannedStart;
  if (status == WpStatus.notStarted && start != null && start.compareTo(today) > 0) return WpGroup.upcoming;
  return WpGroup.today;
}

/// Planned end has passed and the work is not reported yet.
bool isLate(WpEntry e, String today) {
  final end = e.task.plannedEnd;
  final status = e.effectiveStatus;
  return end != null && end.compareTo(today) < 0 && (status == WpStatus.notStarted || status == WpStatus.inProgress);
}

/// What the My Work tab's number and Home's card say.
class WpUpdates {
  const WpUpdates({this.toRead = 0, this.toCheck = 0, this.pending = 0, this.failed = 0, this.notes = 0});

  /// New or changed tasks waiting for "I've read this".
  final int toRead;

  /// Reported work this leader can check.
  final int toCheck;

  /// Actions saved on this phone, not yet sent.
  final int pending;

  /// Actions the server refused (shown on the task).
  final int failed;

  /// Shared meeting notes this worker receives.
  final int notes;

  /// The tab's red number: what needs this worker.
  int get badge => toRead + toCheck + failed;

  bool get isEmpty => toRead == 0 && toCheck == 0 && pending == 0 && failed == 0;
}

WpUpdates summarizeWork(List<WpEntry> entries, {int notes = 0, int otherPending = 0, int otherFailed = 0}) => WpUpdates(
      toRead: entries.where((e) => e.toRead).length,
      toCheck: entries.where((e) => e.toCheck).length,
      pending: entries.fold(otherPending, (n, e) => n + e.shownPending.length),
      failed: entries.fold(otherFailed, (n, e) => n + e.shownFailures.length),
      notes: notes,
    );
