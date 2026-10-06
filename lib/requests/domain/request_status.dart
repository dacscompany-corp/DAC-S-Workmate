import '../../attendance/domain/work_date.dart';
import 'remote_request.dart';

/// Where a request stands for the worker (spec §4E): every state is shown,
/// so nobody believes an unsent request reached the office. [cancelled] is a
/// received request cancelled whole, so the list says what the detail says.
enum SyncState { draft, pending, received, failed, needsResolution, cancelled }

/// One line's progress, most urgent first.
enum LineProgress { needsResolution, officeChecking, cancelled, waiting, partlyArranged, arranged }

LineProgress lineProgress(RemoteLine l) {
  if (l.hasConflict) return LineProgress.needsResolution;
  // A reduction of arranged quantity waits on the office even on a cancelled
  // line: that order may already be placed.
  if (l.portions.any((p) => p.pendingReduction > 0)) return LineProgress.officeChecking;
  if (l.cancelled) return LineProgress.cancelled;
  final arranged = l.portions.where((p) => p.arranged).length;
  if (arranged == 0) return LineProgress.waiting;
  return arranged == l.portions.length ? LineProgress.arranged : LineProgress.partlyArranged;
}

/// A received request's state. Something not yet sent, or refused, outranks
/// what the server says.
SyncState remoteState(RemoteRequest r, {required bool pending, required bool failed}) {
  if (failed) return SyncState.failed;
  if (pending) return SyncState.pending;
  if (r.lines.any((l) => l.hasConflict)) return SyncState.needsResolution;
  if (r.cancelled) return SyncState.cancelled;
  return SyncState.received;
}

/// Nothing left open: cancelled whole, or every line cancelled.
bool requestClosed(RemoteRequest r) => r.cancelled || r.lines.every((l) => l.cancelled);

/// Only the requester changes a request (0085 NOT_YOUR_LINE): a leader reads
/// their team's requests but edits only their own.
bool canChangeLine(RemoteRequest r, RemoteLine l) => r.mine && !r.cancelled && !l.cancelled;

bool canCancelRequest(RemoteRequest r) => r.mine && !requestClosed(r);

const _days = ['Mon', 'Tue', 'Wed', 'Thu', 'Fri', 'Sat', 'Sun'];
const _months = ['Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun', 'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec'];

/// "Wed 14 Oct" for a calendar date ("2026-10-14"), read as it is — a date
/// has no time zone to shift through.
String calendarDay(String iso) {
  final m = RegExp(r'^(\d{4})-(\d{2})-(\d{2})$').firstMatch(iso);
  if (m == null) return iso;
  final d = DateTime.utc(int.parse(m[1]!), int.parse(m[2]!), int.parse(m[3]!));
  return '${_days[d.weekday - 1]} ${d.day} ${_months[d.month - 1]}';
}

/// The earliest delivery still ahead (Manila today or later) on anything open,
/// or null.
String? nextDelivery(Iterable<RemoteRequest> requests, DateTime now) {
  final today = WorkDate.of(now).iso;
  String? best;
  for (final r in requests) {
    if (r.cancelled) continue;
    for (final l in r.lines) {
      if (l.cancelled) continue;
      for (final p in l.portions) {
        if (p.deliveryOn.compareTo(today) < 0) continue;
        if (best == null || p.deliveryOn.compareTo(best) < 0) best = p.deliveryOn;
      }
    }
  }
  return best;
}
