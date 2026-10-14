import '../../requests/domain/request_models.dart';
import '../domain/wp_op.dart';
import '../domain/wp_rules.dart';
import '../domain/wp_task.dart';

/// Everything My Work shows, fresh when online, the phone's last copy offline.
class WorkPlanView {
  const WorkPlanView({
    this.entries = const [],
    this.notes = const [],
    this.proposals = const [],
    this.pendingProposals = const [],
    this.otherFailed = const [],
    this.otherPending = const [],
    this.fetchedAt,
    this.fromCache = false,
    this.error,
  });

  /// Every task this worker has a role on, with what the phone still owes.
  final List<WpEntry> entries;
  final List<WpNote> notes;
  final List<WpProposal> proposals;

  /// Proposals made on this phone, not yet received by the office.
  final List<WpOp> pendingProposals;

  /// Refused operations whose task is no longer on this worker's list (taken
  /// off it, or cancelled) and refused proposals — shown so nobody believes
  /// they reached the office.
  final List<WpOp> otherFailed;

  /// Still-unsent operations whose task is not on the list just read.
  final List<WpOp> otherPending;

  /// When the server's list was read (now, or the saved copy's time).
  final DateTime? fetchedAt;
  final bool fromCache;

  /// Why the server could not be read just now; null when it was.
  final Object? error;

  WpEntry? entry(String taskId) => entries.where((e) => e.task.id == taskId).firstOrNull;
}

/// What a leader proposes from: the teams they currently lead and the open
/// projects / works.
class WpChoices {
  const WpChoices({required this.teams, required this.destinations, this.fromCache = false});

  final List<MyTeam> teams;
  final List<Destination> destinations;
  final bool fromCache;
}

/// Thrown before anything is queued when a report is incomplete.
class WpInvalid implements Exception {
  const WpInvalid(this.field);

  /// 'note', 'description', 'kind', 'title', 'team' or 'destination'.
  final String field;

  @override
  String toString() => 'WpInvalid($field)';
}

/// The problem kinds 0093 accepts, in the order the form offers them.
const wpProblemKinds = ['materials', 'tool', 'preparation', 'other'];

/// What the My Work screens need. An interface so every controller and
/// screen tests with a fake instead of a database and a server.
abstract interface class WorkPlanApi {
  Future<WorkPlanView> load();

  /// "I've read this" for the version on screen.
  Future<void> acknowledge(WpTask task);
  Future<void> startWork(WpTask task);

  /// [photo] is a path [keepPhoto] returned.
  Future<void> reportProgress(WpTask task, String note, {String? photo});
  Future<void> reportProblem(WpTask task, {required String kind, required String description, String? requestId, String? photo});
  Future<void> reportDone(WpTask task, String note);
  Future<void> checkWork(WpTask task, String note);

  Future<WpChoices> choices();
  Future<void> propose({required MyTeam team, required Destination destination, required String title, required String details});

  /// Files a fresh capture: upright, scaled, compressed, in app-private
  /// storage (never the gallery). Returns the stored path.
  Future<String> keepPhoto(String capturedPath);
  Future<void> discardPhoto(String path);

  /// Forgets a refused operation the worker has read.
  Future<void> dismissFailed(WpOp op);

  Future<String?> photoUrl(String path);

  /// Keeps only [workerId]'s saved copy ('' keeps none).
  Future<void> keepOnly(String workerId);
}
