import 'wp_rules.dart';
import 'wp_task.dart';

/// How a task's Next line is coloured (redesign Phase 2 spec §5.2).
enum NextTone { danger, brown, green, normal }

/// The four steps every task goes through. The leader's check is optional in
/// the real flow (the office can approve from "Reported done"), so it is a
/// line under step 3, never a step (owner decision, 12 Nov 2026).
const wpStepLabels = ['Read', 'Started', 'Reported done', 'Approved'];

/// One task's steps and Next line (spec §5).
class WpProgress {
  const WpProgress({required this.reached, required this.leaderChecked, required this.next, required this.tone});

  /// Read · Started · Reported done · Approved.
  final List<bool> reached;

  /// Checked by the leader: shown under step 3.
  final bool leaderChecked;
  final String next;
  final NextTone tone;

  /// The first step not reached; null when all four are.
  int? get current {
    final i = reached.indexOf(false);
    return i < 0 ? null : i;
  }

  int get count => reached.where((r) => r).length;
}

WpProgress progressOf(WpEntry e) {
  final s = e.effectiveStatus;
  final started = s != WpStatus.notStarted;
  final reported = s == WpStatus.reportedDone || s == WpStatus.leaderChecked || s == WpStatus.completed;
  final (next, tone) = _next(e, s);
  return WpProgress(
    reached: [!e.toRead, started, reported, s == WpStatus.completed],
    leaderChecked: s == WpStatus.leaderChecked,
    next: next,
    tone: tone,
  );
}

/// The first rule of spec §5.2 that matches.
(String, NextTone) _next(WpEntry e, WpStatus s) {
  final responsible = e.task.myRole == WpRole.responsible;
  if (e.shownPending.isNotEmpty) return ('Saved on this phone · sends when there is signal', NextTone.brown);
  if (e.toRead) return ('Next: read the task', NextTone.danger);
  if (e.toCheck) return ('Next: check this work', NextTone.danger);
  if (e.blocked) return ('Waiting for the office to clear a problem', NextTone.brown);
  if (s == WpStatus.completed) return ('Completed', NextTone.green);
  if (s == WpStatus.reportedDone || s == WpStatus.leaderChecked) return ('Reported · the office checks it next', NextTone.normal);
  if (responsible && s == WpStatus.notStarted) return ('Next: start work', NextTone.normal);
  if (responsible && s == WpStatus.inProgress) return ('Next: report done', NextTone.normal);
  return ('The responsible person reports this work', NextTone.normal);
}
