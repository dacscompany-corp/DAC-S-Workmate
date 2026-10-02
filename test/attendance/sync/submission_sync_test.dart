import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import 'package:workmate/attendance/data/attendance_db.dart';
import 'package:workmate/attendance/data/attendance_remote.dart';
import 'package:workmate/attendance/data/submission_request.dart';
import 'package:workmate/attendance/domain/attendance_record.dart';
import 'package:workmate/attendance/domain/work_date.dart';
import 'package:workmate/attendance/sync/submission_sync.dart';

class ScriptedRemote implements AttendanceRemote {
  final sent = <String>[];
  final Map<String, Object> failures = {};
  AttendanceRecord? todayRow;
  @override
  Future<AttendanceRecord> submit(SubmissionRequest r, {required String workerId}) async {
    sent.add('${r.direction.wire}:${r.eventId}');
    final f = failures[r.eventId];
    if (f != null) throw f;
    return AttendanceRecord(
        id: 'srv-${r.eventId}', workDate: WorkDate.of(r.capturedAt).iso, status: r.direction == TimeDirection.timeIn ? AttendanceStatus.working : AttendanceStatus.complete, totalMinutes: r.direction == TimeDirection.timeOut ? 585 : null);
  }
  @override
  Future<AttendanceRecord?> today(String workDate) async => todayRow;
  @override
  Future<List<AttendanceRecord>> history(String from, String to) async => [];
  @override
  Future<List<AttendanceProject>> activeProjects() async => [];
}

void main() {
  late AttendanceDb db;
  late Directory tmp;
  late ScriptedRemote remote;
  late SubmissionSync sync;

  setUpAll(sqfliteFfiInit);
  setUp(() async {
    db = await AttendanceDb.open(databaseFactoryFfi, inMemoryDatabasePath, singleInstance: false);
    tmp = await Directory.systemTemp.createTemp('wmsync');
    remote = ScriptedRemote();
    sync = SubmissionSync(db: db, remote: remote);
  });
  tearDown(() async {
    await db.close();
    await tmp.delete(recursive: true);
  });

  Future<String> queue(String eventId, TimeDirection d, String created, {String workerId = 'w1', bool photo = true}) async {
    final path = '${tmp.path}/$eventId.jpg';
    if (photo) File(path).writeAsBytesSync([1]);
    await db.insertPending(PendingSubmission.fromRequest(
      SubmissionRequest(
          direction: d, projectSystem: ProjectSystem.pc, projectId: 'p1', capturedAt: DateTime.parse(created),
          trustedAt: null, photoPath: path, description: null, eventId: eventId),
      workerId: workerId,
      projectName: 'ABC',
      createdAt: DateTime.parse(created),
    ));
    return path;
  }

  test('one run drains everything, Time In before Time Out, and cleans up', () async {
    final outPhoto = await queue('out', TimeDirection.timeOut, '2026-08-18T23:00:00Z');
    final inPhoto = await queue('in', TimeDirection.timeIn, '2026-08-18T23:45:00Z');
    expect(await sync.drain('w1'), SyncResult.done);
    expect(remote.sent, ['IN:in', 'OUT:out']);
    expect(await db.sendable('w1'), isEmpty);
    expect(File(inPhoto).existsSync(), isFalse);
    expect(File(outPhoto).existsSync(), isFalse);
    expect((await db.recordFor('w1', '2026-08-19'))!.totalMinutes, 585);
  });

  test("another worker's rows are never sent", () async {
    await queue('theirs', TimeDirection.timeIn, '2026-08-18T23:00:00Z', workerId: 'w2');
    expect(await sync.drain('w1'), SyncResult.done);
    expect(remote.sent, isEmpty);
    expect((await db.sendable('w2')).length, 1);
  });

  test('no signal keeps the row and asks WorkManager to retry', () async {
    await queue('e1', TimeDirection.timeIn, '2026-08-18T23:45:00Z');
    remote.failures['e1'] = const SocketException('down');
    expect(await sync.drain('w1'), SyncResult.retry);
    final row = (await db.sendable('w1')).single;
    expect(row.attempts, 1);
    expect(row.lastError, 'noConnection');
  });

  test('the server already having the day drops the row and adopts its record', () async {
    final photo = await queue('e1', TimeDirection.timeIn, '2026-08-18T23:45:00Z');
    remote.failures['e1'] = const PostgrestException(message: 'ALREADY_TIMED_IN', code: 'P0001');
    remote.todayRow = AttendanceRecord(id: 'other-phone', workDate: '2026-08-19', status: AttendanceStatus.working);
    expect(await sync.drain('w1'), SyncResult.done);
    expect(await db.pendingById('e1'), isNull);
    expect(File(photo).existsSync(), isFalse);
    expect((await db.recordFor('w1', '2026-08-19'))!.id, 'other-phone');
  });

  test('a permanent refusal is kept and flagged, and the rest of the queue still goes', () async {
    await queue('bad', TimeDirection.timeIn, '2026-08-18T23:00:00Z');
    await queue('good', TimeDirection.timeIn, '2026-08-19T23:00:00Z');
    remote.failures['bad'] = const PostgrestException(message: 'OUTSIDE_RADIUS', code: 'P0001');
    expect(await sync.drain('w1'), SyncResult.done);
    expect((await db.failed('w1')).single.lastError, 'outsideRadius');
    expect(remote.sent, ['IN:bad', 'IN:good']);
  });

  test('a missing photo fails the row permanently instead of recording no evidence', () async {
    await queue('e1', TimeDirection.timeIn, '2026-08-18T23:45:00Z', photo: false);
    expect(await sync.drain('w1'), SyncResult.done);
    expect((await db.failed('w1')).single.lastError, 'PHOTO_MISSING');
    expect(remote.sent, isEmpty);
  });

  test('a row with no project system fails permanently (PROJECT_RETIRED)', () async {
    await queue('e1', TimeDirection.timeIn, '2026-08-18T23:45:00Z');
    final row = (await db.sendable('w1')).single;
    await db.insertPending(row.copyWithSystem(''));
    expect(await sync.drain('w1'), SyncResult.done);
    expect((await db.failed('w1')).single.lastError, 'PROJECT_RETIRED');
  });

  test('a still-pending mirror is not overwritten while a sendable row owns the day', () async {
    await queue('in', TimeDirection.timeIn, '2026-08-18T23:00:00Z');
    await queue('out', TimeDirection.timeOut, '2026-08-19T09:00:00Z');
    await db.upsertRecord('w1', AttendanceRecord(id: '2026-08-19', workDate: '2026-08-19', status: AttendanceStatus.complete), pending: true);
    remote.failures['out'] = const SocketException('down');
    expect(await sync.drain('w1'), SyncResult.retry);
    expect(remote.sent, ['IN:in', 'OUT:out']);
    expect((await db.recordFor('w1', '2026-08-19'))!.status, AttendanceStatus.complete);
  });

  test('no worker, nothing sent', () async {
    await queue('e1', TimeDirection.timeIn, '2026-08-18T23:45:00Z');
    expect(await sync.drain(''), SyncResult.done);
    expect(remote.sent, isEmpty);
  });

  test('settled counts every row the drain finished with', () async {
    await queue('e1', TimeDirection.timeIn, '2026-08-18T23:45:00Z');
    await queue('e2', TimeDirection.timeOut, '2026-08-19T09:30:00Z');
    expect(await sync.drain('w1'), SyncResult.done);
    expect(sync.settled, 2);
  });

  test('a drain stopped by no signal settled nothing', () async {
    await queue('e1', TimeDirection.timeIn, '2026-08-18T23:45:00Z');
    remote.failures['e1'] = const SocketException('down');
    expect(await sync.drain('w1'), SyncResult.retry);
    expect(sync.settled, 0);
  });
}
