import '../domain/remote_request.dart';
import '../domain/request_draft.dart';
import '../domain/request_models.dart';
import '../domain/request_op.dart';
import '../domain/request_status.dart';

/// What a worker can choose from, fresh when online, the last copy offline.
class RequestReferences {
  const RequestReferences({
    required this.destinations,
    required this.teams,
    required this.catalog,
    this.fromCache = false,
  });

  final List<Destination> destinations;
  final List<MyTeam> teams;
  final List<CatalogItem> catalog;
  final bool fromCache;
}

/// One row of the Requests list: a request still on the phone ([draft]) or
/// one the server holds ([remote]) — with the operations about it still on
/// the phone, so its state never claims more than is true.
class RequestEntry {
  const RequestEntry({
    required this.state,
    this.remote,
    this.draft,
    this.pendingOps = const [],
    this.failedOps = const [],
  });

  final SyncState state;
  final RemoteRequest? remote;
  final RequestDraft? draft;
  final List<RequestOp> pendingOps;
  final List<RequestOp> failedOps;

  String get key => remote?.id ?? draft!.id;

  DateTime get sortTime => remote?.receivedAt ?? draft!.createdAt;

  /// The quantity a worker's still-unsent edit will set, or null.
  double? pendingQuantity(String lineId) {
    double? last;
    for (final o in pendingOps) {
      if (o.kind == OpKind.quantity && o.lineId == lineId) last = o.quantity;
    }
    return last;
  }

  bool cancelPending(String lineId) =>
      pendingOps.any((o) => o.kind == OpKind.cancelRequest || (o.kind == OpKind.cancelLine && o.lineId == lineId));
}

class RequestsView {
  const RequestsView({required this.entries, this.fetchedAt, this.fromCache = false, this.error});

  /// Newest first.
  final List<RequestEntry> entries;

  /// When the server's list was read (now, or the cached copy's time).
  final DateTime? fetchedAt;
  final bool fromCache;

  /// Why the server could not be read just now; null when it was.
  final Object? error;
}

/// Thrown by [RequestsApi.send] for a draft the server would refuse.
class DraftInvalid implements Exception {
  const DraftInvalid(this.issues);
  final List<DraftIssue> issues;

  @override
  String toString() => 'DraftInvalid($issues)';
}

/// What the Requests screens need. An interface so every controller and
/// screen tests with a fake instead of a database and a server.
abstract interface class RequestsApi {
  Future<RequestReferences> references();

  /// Unsent drafts still being edited, newest first.
  Future<List<RequestDraft>> drafts();
  RequestDraft newDraft();
  Future<void> saveDraft(RequestDraft draft);

  /// Discards an unsent draft and its photos.
  Future<void> deleteDraft(RequestDraft draft);

  /// Files a fresh capture for [draftId]: upright, scaled, compressed, in
  /// app-private storage (never the gallery). Returns the stored path.
  Future<String> keepPhoto(String draftId, String capturedPath);
  Future<void> discardPhoto(String path);

  /// Queues the draft (throws [DraftInvalid] first) and starts sending.
  Future<void> send(RequestDraft draft);

  Future<RequestsView> myRequests();
  Future<void> changeQuantity(RemoteRequest request, RemoteLine line, double quantity);
  Future<void> cancelLine(RemoteRequest request, RemoteLine line);
  Future<void> cancelRequest(RemoteRequest request);

  /// A refused draft back to editing (spec §3: an offline draft whose
  /// destination closed stays visible for resolution). False when the phone
  /// refused: an op of it may still be sent, or its request already landed.
  Future<bool> returnToDrafts(String draftId);

  /// Forgets a refused operation the worker has read.
  Future<void> dismissFailed(RequestOp op);

  Future<String?> photoUrl(String path);
}
