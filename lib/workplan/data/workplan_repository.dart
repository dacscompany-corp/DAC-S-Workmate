import 'dart:async';
import 'dart:io';

import '../../attendance/device/device_bridge.dart';
import '../../attendance/domain/event_id.dart';
import '../../attendance/sync/upload_scheduler.dart';
import '../../requests/domain/request_models.dart';
import '../domain/wp_op.dart';
import '../domain/wp_rules.dart';
import '../domain/wp_task.dart';
import 'workplan_api.dart';
import 'workplan_db.dart';
import 'workplan_remote.dart';

/// Offline-first My Work (spec §11). Every action is saved on the phone
/// first and reaches the server whenever there is signal, from the app or
/// from the background task. The server re-checks role, assignment, version
/// and state when it arrives.
class WorkPlanRepository implements WorkPlanApi {
  WorkPlanRepository({
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

  final WorkPlanDb db;
  final WorkPlanRemote remote;
  final DeviceBridge device;

  /// The same WorkManager work as attendance and requests: one background
  /// drain sends all three.
  final UploadScheduler scheduler;

  /// The worker the app let in, or '' — the scope of EVERY read and write.
  final String Function() currentWorkerId;

  /// App-private folder for task photos (never the gallery).
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

  /// Still the worker a read started for? A sign-out or a switch while the
  /// answer travelled means the answer is not theirs to keep or show.
  bool _still(String w) => currentWorkerId() == w;

  void _stillOrThrow(String w) {
    if (!_still(w)) throw StateError('AUTH_REQUIRED');
  }

  Future<void> _kick() async {
    try {
      await scheduler.enqueue('workplan');
    } catch (_) {
      // Queued on disk; the periodic sweeper is the backstop.
    }
    final now = sendNow;
    if (now != null) unawaited(Future.sync(now).catchError((Object _) {}));
  }

  WpOp _op(String w, WpOpKind kind, {String? taskId, Map<String, dynamic> body = const {}, String? parent}) =>
      WpOp(opId: _newId(), workerId: w, kind: kind, createdAt: _now(), taskId: taskId, parentOpId: parent, body: body);

  Future<void> _queue(List<WpOp> ops) async {
    await db.addOps(ops);
    await _kick();
  }

  // ── reading ────────────────────────────────────────────────────────────

  /// One list, fresh or saved. The saved copy is used only for the list that
  /// could not be read, and only this worker's.
  Future<({List<Map<String, dynamic>> docs, DateTime? at, bool cached, Object? error})> _read(
      String w, String name, Future<List<Map<String, dynamic>>> Function() fetch, int readSince) async {
    try {
      final docs = await fetch();
      final at = _now();
      // Checked inside the save's transaction: a copy wiped at sign-out is
      // never written back by an answer that arrives late, and an action
      // accepted while this read travelled keeps the server's newer answer.
      final saved = await db.saveLists(w, {name: docs}, at, stillValid: () => _still(w), readSince: readSince);
      return (docs: saved[name]!, at: at, cached: false, error: null);
    } catch (e) {
      _stillOrThrow(w);
      final saved = await db.cache(w, name);
      if (saved == null) return (docs: const <Map<String, dynamic>>[], at: null, cached: false, error: e);
      return (
        docs: [for (final d in saved.body as List<dynamic>) Map<String, dynamic>.from(d as Map)],
        at: saved.at,
        cached: true,
        error: e,
      );
    }
  }

  @override
  Future<WorkPlanView> load() async {
    final w = _worker();
    // Taken BEFORE asking the server (see WorkPlanDb.saveLists).
    final since = await db.acceptedSeq(w);
    // All three at once: on a weak signal the wait is one timeout, not three.
    final reads = await Future.wait([
      _read(w, 'work', remote.myWork, since),
      _read(w, 'notes', remote.myNotes, since),
      _read(w, 'proposals', remote.myProposals, since),
    ]);
    final (work, notes, proposals) = (reads[0], reads[1], reads[2]);
    final ops = await db.ops(w);
    // The last wait is over: if the app let someone else in meanwhile, this
    // view is not theirs.
    _stillOrThrow(w);

    final tasks = [for (final d in work.docs) ?WpTask.fromJson(d)];
    final ids = {for (final t in tasks) t.id};
    final entries = [
      for (final t in tasks)
        WpEntry(
          task: t,
          pendingOps: ops.where((o) => o.taskId == t.id && !o.failedPermanently).toList(),
          failedOps: ops.where((o) => o.taskId == t.id && o.failedPermanently).toList(),
        ),
    ];
    return WorkPlanView(
      entries: entries,
      notes: [for (final n in notes.docs) WpNote.fromJson(n)],
      proposals: [for (final p in proposals.docs) WpProposal.fromJson(p)],
      pendingProposals: ops.where((o) => o.kind == WpOpKind.propose && !o.failedPermanently).toList(),
      otherFailed: ops.where((o) => o.failedPermanently && (o.taskId == null || !ids.contains(o.taskId))).toList(),
      otherPending: ops
          .where((o) => !o.failedPermanently && o.kind != WpOpKind.propose && o.taskId != null && !ids.contains(o.taskId))
          .toList(),
      fetchedAt: work.at,
      fromCache: work.cached,
      // The task list decides what the screen says about the connection.
      error: work.error,
    );
  }

  // ── actions ────────────────────────────────────────────────────────────

  @override
  Future<void> acknowledge(WpTask task) async {
    final w = _worker();
    // A second tap for the same version queues nothing.
    final queued = await db.sendable(w);
    if (queued.any((o) => o.kind == WpOpKind.acknowledge && o.taskId == task.id && o.version == task.version)) return;
    await _queue([_op(w, WpOpKind.acknowledge, taskId: task.id, body: {'version': task.version})]);
  }

  @override
  Future<void> startWork(WpTask task) async {
    final w = _worker();
    final queued = await db.sendable(w);
    if (queued.any((o) => o.kind == WpOpKind.start && o.taskId == task.id)) return;
    if (await _movedPast(w, task.id, 'not_started')) return;
    await _queue([_op(w, WpOpKind.start, taskId: task.id)]);
  }

  /// The status of [taskId] in this worker's SAVED task list, or null when
  /// there is no list or the task is not in it. `settle` patches it in the same
  /// transaction that removes an accepted action.
  Future<String?> _savedStatus(String w, String taskId) async {
    final saved = await db.cache(w, 'work');
    final body = saved?.body;
    if (body is! List) return null;
    for (final d in body) {
      if (d is Map && d['id'] == taskId) return d['status'] as String?;
    }
    return null;
  }

  /// True when the saved task is already later than [needs] in the task's
  /// life (not started < in progress < reported < checked < completed). A
  /// status that merely differs is not enough: offline, Report done after a
  /// queued Start sees the saved task still not started and must be queued.
  /// The button can still be enabled for a moment after the quick send was
  /// accepted, and a second tap would queue an action the server refuses (BAD_STATE) and show
  /// a false "not accepted".
  Future<bool> _movedPast(String w, String taskId, String needs) async {
    final status = await _savedStatus(w, taskId);
    final saved = WpStatus.parse(status)?.index, wanted = WpStatus.parse(needs)?.index;
    return saved != null && wanted != null && saved > wanted;
  }

  /// The report, then its photo (linked once the report lands).
  List<WpOp> _withPhoto(String w, WpOp report, String? photo) => [
        report,
        if (photo != null)
          _op(w, WpOpKind.photo, taskId: report.taskId, parent: report.opId, body: {'local_path': photo, 'photo_id': _newId()}),
      ];

  @override
  Future<void> reportProgress(WpTask task, String note, {String? photo}) async {
    final text = note.trim();
    if (text.isEmpty) throw const WpInvalid('note');
    final w = _worker();
    await _queue(_withPhoto(w, _op(w, WpOpKind.progress, taskId: task.id, body: {'note': text}), photo));
  }

  @override
  Future<void> reportProblem(WpTask task, {required String kind, required String description, String? requestId, String? photo}) async {
    if (!wpProblemKinds.contains(kind)) throw const WpInvalid('kind');
    final text = description.trim();
    if (text.isEmpty) throw const WpInvalid('description');
    final w = _worker();
    final report = _op(w, WpOpKind.blocker, taskId: task.id, body: {'kind': kind, 'description': text, 'request_id': requestId});
    await _queue(_withPhoto(w, report, photo));
  }

  @override
  Future<void> reportDone(WpTask task, String note) async {
    final w = _worker();
    final queued = await db.sendable(w);
    if (queued.any((o) => o.kind == WpOpKind.done && o.taskId == task.id)) return;
    if (await _movedPast(w, task.id, 'in_progress')) return;
    await _queue([_op(w, WpOpKind.done, taskId: task.id, body: {'note': note.trim()})]);
  }

  @override
  Future<void> checkWork(WpTask task, String note) async {
    final w = _worker();
    final queued = await db.sendable(w);
    if (queued.any((o) => o.kind == WpOpKind.check && o.taskId == task.id)) return;
    if (await _movedPast(w, task.id, 'reported_done')) return;
    await _queue([_op(w, WpOpKind.check, taskId: task.id, body: {'note': note.trim()})]);
  }

  // ── proposals ──────────────────────────────────────────────────────────

  @override
  Future<WpChoices> choices() async {
    final w = _worker();
    try {
      final teams = await remote.myTeams();
      final destinations = await remote.destinations();
      final at = _now();
      // Both answers belong to the worker the form opened for, or neither is
      // used: checked before, inside the save's transaction, and after it.
      _stillOrThrow(w);
      await db.saveLists(
        w,
        {'teams': [for (final t in teams) t.toRow()], 'destinations': [for (final d in destinations) d.toRow()]},
        at,
        stillValid: () => _still(w),
      );
      _stillOrThrow(w);
      return WpChoices(teams: teams.where((t) => t.iLead).toList(), destinations: destinations);
    } catch (_) {
      _stillOrThrow(w);
      final t = await db.cache(w, 'teams');
      final d = await db.cache(w, 'destinations');
      if (t == null || d == null) rethrow;
      List<Map<String, dynamic>> rows(Object? body) => [for (final r in body as List<dynamic>) Map<String, dynamic>.from(r as Map)];
      return WpChoices(
        teams: rows(t.body).map(MyTeam.fromRow).where((t) => t.iLead).toList(),
        destinations: rows(d.body).map(Destination.fromRow).toList(),
        fromCache: true,
      );
    }
  }

  @override
  Future<void> propose({required MyTeam team, required Destination destination, required String title, required String details}) async {
    final text = title.trim();
    if (text.isEmpty) throw const WpInvalid('title');
    final w = _worker();
    await _queue([
      _op(w, WpOpKind.propose, body: {
        'team_id': team.id,
        'folder_id': destination.projectId,
        'work_id': destination.workId,
        'title': text,
        'details': details.trim(),
        // Display only, while it waits for signal.
        'team_name': team.name,
        'where': destination.label,
      }),
    ]);
  }

  // ── photos and refused operations ──────────────────────────────────────

  @override
  Future<String> keepPhoto(String capturedPath) async {
    final dir = await photoDir();
    await dir.create(recursive: true);
    // No caption: a task photo shows the work, not a time stamp.
    return device.preparePhoto(source: capturedPath, target: '${dir.path}${Platform.pathSeparator}${_newId()}.jpg', caption: '');
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
  Future<void> dismissFailed(WpOp op) async {
    final stored = await db.op(op.opId);
    // Only this worker's own, and only a refused one: a sendable op is still owed.
    if (stored == null || stored.workerId != _worker() || !stored.failedPermanently) return;
    // A refused report's photos were refused with it: they go together.
    final gone = [stored, for (final c in await db.children(stored.opId)) if (c.failedPermanently) c];
    for (final o in gone) {
      await db.deleteOp(o.opId);
      final path = o.localPath;
      if (o.kind == WpOpKind.photo && path != null) await discardPhoto(path);
    }
  }

  @override
  Future<String?> photoUrl(String path) => remote.signedUrl(path);

  @override
  Future<void> keepOnly(String workerId) => db.keepCacheOnly(workerId);
}
