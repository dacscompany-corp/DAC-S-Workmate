import 'dart:io';

import '../device/device_bridge.dart';
import '../domain/attendance_record.dart';
import '../domain/photo_overlay.dart';
import '../domain/today_reconcile.dart';
import '../domain/work_date.dart';
import '../sync/upload_scheduler.dart';
import 'attendance_db.dart';
import 'attendance_remote.dart';
import 'submission_request.dart';

/// Offline-first attendance. The UI never waits on the network to confirm
/// attendance: SUBMIT writes the photo, queues the row, updates the mirror and
/// returns — all on the phone. The upload happens afterwards in the background.
class AttendanceRepository {
  AttendanceRepository({
    required this.db,
    required this.remote,
    required this.device,
    required this.scheduler,
    required this.currentWorkerId,
    required this.photoDir,
    DateTime Function()? now,
  }) : _now = now ?? DateTime.now;

  final AttendanceDb db;
  final AttendanceRemote remote;
  final DeviceBridge device;
  final UploadScheduler scheduler;

  /// The signed-in worker (session id, else the last signed-in id; offline the
  /// session can report nobody). Scope for EVERY local read and write.
  final String Function() currentWorkerId;

  /// App-private directory for queued photos (never the gallery).
  final Future<Directory> Function() photoDir;
  final DateTime Function() _now;

  Future<AttendanceRecord> submit(SubmissionRequest r) async {
    final workerId = currentWorkerId();
    // Nothing may be queued or mirrored under nobody.
    if (workerId.isEmpty) throw StateError('AUTH_REQUIRED');
    final workDate = WorkDate.of(r.capturedAt).iso;
    // Matched on the PAIR — an id alone is ambiguous across systems.
    final projectName = (await db.projects(workerId))
            .where((p) => p.id == r.projectId && p.system == r.projectSystem)
            .map((p) => p.name)
            .firstOrNull ??
        '';

    // Caption burned in and compressed BEFORE the row is queued: a pending row
    // must point at the exact bytes that will be uploaded.
    final dir = await photoDir();
    await dir.create(recursive: true);
    final prepared = await device.preparePhoto(
      source: r.photoPath,
      target: '${dir.path}${Platform.pathSeparator}${r.eventId}.jpg',
      caption: photoOverlayCaption(projectName, r.capturedAt),
    );
    // Decided HERE, at capture time — the upload happens later, with signal by definition.
    final queued = r.withPhoto(prepared, wasOffline: !await device.isOnline());

    await db.insertPending(PendingSubmission.fromRequest(queued, workerId: workerId, projectName: projectName, createdAt: _now()));
    final mirror = await _mirrorAfter(workerId, queued, workDate, projectName);
    await db.upsertRecord(workerId, mirror, pending: true);
    try {
      await scheduler.enqueue(r.eventId);
    } catch (_) {
      // The row is saved; the periodic sweeper is the backstop.
    }
    return mirror;
  }

  /// Today from the mirror; the network only CORRECTS it. Throws the network
  /// error only when there is genuinely nothing to show (Unknown).
  Future<AttendanceRecord?> today() async {
    final workerId = currentWorkerId();
    final workDate = WorkDate.of(_now()).iso;
    final cached = await db.recordFor(workerId, workDate);
    final hasPending = (await db.sendable(workerId)).any((p) => WorkDate.of(p.capturedAt).iso == workDate);

    AttendanceRecord? fresh;
    Object? error;
    var answered = false;
    try {
      fresh = await remote.today(workDate);
      answered = true;
    } catch (e) {
      error = e;
    }

    switch (reconcileToday(serverAnswered: answered, server: fresh, cached: cached, hasPending: hasPending)) {
      case TodayUse(:final record):
        // Only write back what the SERVER said, and never over a mirror that a queued row still owns.
        if (answered && fresh != null && !hasPending) await db.upsertRecord(workerId, record, pending: hasPending);
        return record.copyWith(pending: hasPending);
      case TodayClear():
        await db.clearRecord(workerId, workDate);
        return null;
      case TodayUnknown():
        throw error!;
    }
  }

  /// History, mirrored as it is fetched; served from the mirror offline. An
  /// empty mirror and an unreachable server are different answers.
  Future<List<AttendanceRecord>> history(String from, String to) async {
    final workerId = currentWorkerId();
    try {
      final records = await remote.history(from, to);
      // Days with a sendable queue row belong to the phone until they upload.
      final pendingDates = (await db.sendable(workerId)).map((p) => WorkDate.of(p.capturedAt).iso).toSet();
      final out = <AttendanceRecord>[];
      final seen = <String>{};
      for (final r in records) {
        seen.add(r.workDate);
        if (pendingDates.contains(r.workDate)) {
          final mirror = await db.recordFor(workerId, r.workDate);
          out.add(mirror?.copyWith(pending: true) ?? r);
          continue;
        }
        await db.upsertRecord(workerId, r, pending: false);
        out.add(r);
      }
      for (final d in pendingDates) {
        if (seen.contains(d) || d.compareTo(from) < 0 || d.compareTo(to) > 0) continue;
        final mirror = await db.recordFor(workerId, d);
        if (mirror != null) out.add(mirror.copyWith(pending: true));
      }
      out.sort((a, b) => b.workDate.compareTo(a.workDate));
      return out;
    } catch (_) {
      final cached = await db.recordsBetween(workerId, from, to);
      if (cached.isNotEmpty) return cached;
      rethrow;
    }
  }

  /// Projects, cached per worker (a different worker may have a different owner).
  Future<List<AttendanceProject>> activeProjects() async {
    final workerId = currentWorkerId();
    try {
      final projects = await remote.activeProjects();
      if (projects.isNotEmpty) await db.replaceProjects(workerId, projects);
      return projects;
    } catch (_) {
      final cached = await db.projects(workerId);
      if (cached.isNotEmpty) return cached;
      rethrow;
    }
  }

  Future<AttendanceRecord> _mirrorAfter(String workerId, SubmissionRequest r, String workDate, String projectName) async {
    final existing = await db.recordFor(workerId, workDate);
    if (r.direction == TimeDirection.timeIn) {
      return AttendanceRecord(
        id: existing?.id ?? workDate,
        workDate: workDate,
        status: AttendanceStatus.working,
        timeInAt: r.capturedAt.toUtc(),
        timeInProjectName: projectName,
        pending: true,
      );
    }
    final timeIn = existing?.timeInAt;
    return AttendanceRecord(
      id: existing?.id ?? workDate,
      workDate: workDate,
      status: AttendanceStatus.complete,
      timeInAt: timeIn,
      timeOutAt: r.capturedAt.toUtc(),
      timeInProjectName: existing?.timeInProjectName,
      timeOutProjectName: projectName,
      // Optimistic; replaced by the server's own calculation when the upload lands.
      totalMinutes: timeIn == null ? null : r.capturedAt.difference(timeIn).inMinutes,
      pending: true,
    );
  }
}
