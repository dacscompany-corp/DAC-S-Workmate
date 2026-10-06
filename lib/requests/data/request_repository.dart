import 'dart:async';
import 'dart:io';

import '../../attendance/device/device_bridge.dart';
import '../../attendance/domain/event_id.dart';
import '../../attendance/sync/upload_scheduler.dart';
import '../domain/remote_request.dart';
import '../domain/request_draft.dart';
import '../domain/request_models.dart';
import '../domain/request_op.dart';
import '../domain/request_status.dart';
import 'request_remote.dart';
import 'requests_api.dart';
import 'requests_db.dart';

/// Offline-first requests (spec §4E). Drafting, sending and editing all
/// happen on the phone first; the queue reaches the server whenever there is
/// signal, from the app or from the background task.
class RequestRepository implements RequestsApi {
  RequestRepository({
    required this.db,
    required this.remote,
    required this.device,
    required this.scheduler,
    required this.currentWorkerId,
    required this.photoDir,
    this.sendNow,
    DateTime Function()? now,
    String Function()? newId,
  })  : _now = now ?? DateTime.now,
        _newId = newId ?? newEventId;

  final RequestsDb db;
  final RequestRemote remote;
  final DeviceBridge device;

  /// The same WorkManager work as attendance: one background drain sends both.
  final UploadScheduler scheduler;

  /// The worker the app let in, or '' — the scope of EVERY read and write.
  final String Function() currentWorkerId;

  /// App-private folder for request photos (never the gallery).
  final Future<Directory> Function() photoDir;

  /// Drains the queue now in the live app (main.dart); null in tests.
  final Future<void> Function()? sendNow;
  final DateTime Function() _now;
  final String Function() _newId;

  String _worker() {
    final w = currentWorkerId();
    // Nothing may be read or queued under nobody.
    if (w.isEmpty) throw StateError('AUTH_REQUIRED');
    return w;
  }

  Future<void> _kick() async {
    try {
      await scheduler.enqueue('requests');
    } catch (_) {
      // Queued on disk; the periodic sweeper is the backstop.
    }
    final now = sendNow;
    if (now != null) unawaited(Future.sync(now).catchError((Object _) {}));
  }

  // ── choices ────────────────────────────────────────────────────────────

  @override
  Future<RequestReferences> references() async {
    final w = _worker();
    try {
      final destinations = await remote.destinations();
      final teams = await remote.myTeams();
      final catalog = await remote.catalog();
      final at = _now();
      await db.putCache(w, 'destinations', [for (final d in destinations) d.toRow()], at);
      await db.putCache(w, 'teams', [for (final t in teams) t.toRow()], at);
      await db.putCache(w, 'catalog', [for (final c in catalog) c.toRow()], at);
      return RequestReferences(destinations: destinations, teams: teams, catalog: catalog);
    } catch (_) {
      final d = await db.cache(w, 'destinations');
      final t = await db.cache(w, 'teams');
      final c = await db.cache(w, 'catalog');
      if (d == null || t == null || c == null) rethrow;
      List<Map<String, dynamic>> rows(Object? body) => [for (final r in body as List<dynamic>) Map<String, dynamic>.from(r as Map)];
      return RequestReferences(
        destinations: rows(d.body).map(Destination.fromRow).toList(),
        teams: rows(t.body).map(MyTeam.fromRow).toList(),
        catalog: rows(c.body).map(CatalogItem.fromRow).whereType<CatalogItem>().toList(),
        fromCache: true,
      );
    }
  }

  // ── drafts ─────────────────────────────────────────────────────────────

  @override
  Future<List<RequestDraft>> drafts() async => db.drafts(_worker(), queued: false);

  @override
  RequestDraft newDraft() => RequestDraft(id: _newId(), createdAt: _now());

  @override
  Future<void> saveDraft(RequestDraft draft) async => db.saveDraft(_worker(), draft, _now());

  @override
  Future<void> deleteDraft(RequestDraft draft) async {
    final stored = await db.deleteUnsentDraft(_worker(), draft.id);
    // A queued draft's photos are still owed to the server: never touch them.
    for (final l in stored?.lines ?? const <DraftLine>[]) {
      for (final p in l.photos) {
        await discardPhoto(p);
      }
    }
  }

  @override
  Future<String> keepPhoto(String draftId, String capturedPath) async {
    final dir = Directory('${(await photoDir()).path}${Platform.pathSeparator}$draftId');
    await dir.create(recursive: true);
    // No caption: a request photo shows the item, not a time stamp.
    return device.preparePhoto(
      source: capturedPath,
      target: '${dir.path}${Platform.pathSeparator}${_newId()}.jpg',
      caption: '',
    );
  }

  @override
  Future<void> discardPhoto(String path) async {
    try {
      await File(path).delete();
    } catch (_) {
      // Already gone.
    }
  }

  @override
  Future<void> send(RequestDraft draft) async {
    final issues = draftIssues(draft);
    if (issues.isNotEmpty) throw DraftInvalid(issues);
    final w = _worker();
    final at = _now();
    final ops = <RequestOp>[
      RequestOp(opId: _newId(), workerId: w, kind: OpKind.submit, createdAt: at, draftId: draft.id, body: submitPayload(draft)),
      for (var i = 0; i < draft.lines.length; i++)
        for (final p in draft.lines[i].photos)
          RequestOp(
            opId: _newId(),
            workerId: w,
            kind: OpKind.photo,
            createdAt: at,
            draftId: draft.id,
            linePosition: i,
            body: {'local_path': p, 'photo_id': _newId()},
          ),
    ];
    // A second Send of the same draft (a double tap) queues nothing.
    if (await db.queueDraft(w, draft, ops, at)) await _kick();
  }

  // ── the list ───────────────────────────────────────────────────────────

  @override
  Future<RequestsView> myRequests() async {
    final w = _worker();
    List<Map<String, dynamic>>? docs;
    Object? error;
    DateTime? fetchedAt;
    var fromCache = false;
    try {
      docs = await remote.myRequests();
      fetchedAt = _now();
      await db.putCache(w, 'requests', docs, fetchedAt);
    } catch (e) {
      error = e;
      final cached = await db.cache(w, 'requests');
      if (cached != null) {
        docs = [for (final d in cached.body as List<dynamic>) Map<String, dynamic>.from(d as Map)];
        fetchedAt = cached.at;
        fromCache = true;
      }
    }

    final remotes = [for (final d in docs ?? const <Map<String, dynamic>>[]) RemoteRequest.fromJson(d)];
    final remoteIds = {for (final r in remotes) r.id};
    final ops = await db.ops(w);
    final links = await db.links(w);
    final entries = <RequestEntry>[];

    for (final d in await db.drafts(w, queued: true)) {
      final requestId = links[d.id];
      if (requestId != null && remoteIds.contains(requestId)) {
        // The server's copy now shows it. Forget the phone's copy once that
        // copy is FRESH; its photo ops already point at the request.
        if (!fromCache) {
          await db.deleteDraft(w, d.id);
          await db.deleteLink(d.id);
        }
        continue;
      }
      final mine = ops.where((o) => o.draftId == d.id || (requestId != null && o.requestId == requestId)).toList();
      final pending = mine.where((o) => !o.failedPermanently).toList();
      final failed = mine.where((o) => o.failedPermanently).toList();
      final state = failed.isNotEmpty
          ? SyncState.failed
          : (requestId == null || pending.isNotEmpty)
              ? SyncState.pending
              : SyncState.received;
      entries.add(RequestEntry(state: state, draft: d, pendingOps: pending, failedOps: failed));
    }

    for (final r in remotes) {
      final mine = ops.where((o) => o.requestId == r.id).toList();
      final pending = mine.where((o) => !o.failedPermanently).toList();
      final failed = mine.where((o) => o.failedPermanently).toList();
      entries.add(RequestEntry(
        state: remoteState(r, pending: pending.isNotEmpty, failed: failed.isNotEmpty),
        remote: r,
        pendingOps: pending,
        failedOps: failed,
      ));
    }

    entries.sort((a, b) => b.sortTime.compareTo(a.sortTime));
    return RequestsView(entries: entries, fetchedAt: fetchedAt, fromCache: fromCache, error: (docs == null || fromCache) ? error : null);
  }

  // ── changes to received requests ───────────────────────────────────────

  @override
  Future<void> changeQuantity(RemoteRequest request, RemoteLine line, double quantity) async {
    final w = _worker();
    final base = predictedBase(line.version, await db.sendable(w), line.id);
    await db.addOps([
      RequestOp(
        opId: _newId(),
        workerId: w,
        kind: OpKind.quantity,
        createdAt: _now(),
        requestId: request.id,
        lineId: line.id,
        baseVersion: base,
        body: {'quantity': quantity},
      ),
    ]);
    await _kick();
  }

  @override
  Future<void> cancelLine(RemoteRequest request, RemoteLine line) async {
    final w = _worker();
    await db.addOps([
      RequestOp(opId: _newId(), workerId: w, kind: OpKind.cancelLine, createdAt: _now(), requestId: request.id, lineId: line.id),
    ]);
    await _kick();
  }

  @override
  Future<void> cancelRequest(RemoteRequest request) async {
    final w = _worker();
    await db.addOps([RequestOp(opId: _newId(), workerId: w, kind: OpKind.cancelRequest, createdAt: _now(), requestId: request.id)]);
    await _kick();
  }

  // ── refused operations ─────────────────────────────────────────────────

  @override
  Future<bool> returnToDrafts(String draftId) => db.unqueueDraft(_worker(), draftId);

  @override
  Future<void> dismissFailed(RequestOp op) async {
    final stored = await db.op(op.opId);
    // Only this worker's own, and only a refused one: a sendable op is still
    // owed. A refused submit goes back to Drafts instead (returnToDrafts):
    // dismissing it would strand its draft as Pending forever.
    if (stored == null || stored.workerId != _worker() || !stored.failedPermanently || stored.kind == OpKind.submit) return;
    await db.deleteOp(op.opId);
    final path = stored.localPath;
    if (stored.kind == OpKind.photo && path != null) await discardPhoto(path);
  }

  @override
  Future<String?> photoUrl(String path) async => remote.signedUrl(path);
}
