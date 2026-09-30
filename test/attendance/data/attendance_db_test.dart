import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import 'package:workmate/attendance/data/attendance_db.dart';
import 'package:workmate/attendance/data/submission_request.dart';
import 'package:workmate/attendance/domain/attendance_record.dart';
import 'package:workmate/attendance/domain/location_verification.dart';
import 'package:workmate/attendance/domain/work_date.dart';

SubmissionRequest request({String eventId = 'e1', TimeDirection d = TimeDirection.timeIn, String captured = '2026-08-18T23:45:00Z'}) =>
    SubmissionRequest(
      direction: d,
      projectSystem: ProjectSystem.pc,
      projectId: 'p1',
      capturedAt: DateTime.parse(captured),
      trustedAt: DateTime.parse('2026-08-18T23:45:03Z'),
      photoPath: '/files/attendance-photos/$eventId.jpg',
      description: 'Block A',
      eventId: eventId,
      latitude: 14.5,
      longitude: 121.0,
      accuracyMetres: 9,
      wasOffline: true,
      isMock: false,
      permissionDenied: false,
      locationStatus: 'verified',
    );

void main() {
  late AttendanceDb db;
  setUpAll(sqfliteFfiInit);
  setUp(() async => db = await AttendanceDb.open(databaseFactoryFfi, inMemoryDatabasePath, singleInstance: false));
  tearDown(() => db.close());

  test('a queued submission round-trips every field the upload needs', () async {
    await db.insertPending(PendingSubmission.fromRequest(request(), workerId: 'w1', projectName: 'ABC', createdAt: DateTime.parse('2026-08-18T23:46:00Z')));
    final row = (await db.sendable('w1')).single;
    final back = row.toRequest()!;
    expect(back.capturedAt, DateTime.parse('2026-08-18T23:45:00Z'));
    expect(back.trustedAt, DateTime.parse('2026-08-18T23:45:03Z'));
    expect(back.projectSystem, ProjectSystem.pc);
    expect(back.wasOffline, isTrue);
    expect(back.description, 'Block A');
    expect(row.projectName, 'ABC');
    expect(row.toQueued().workerId, 'w1');
  });

  test("the queue is per worker: another worker's rows are invisible", () async {
    await db.insertPending(PendingSubmission.fromRequest(request(), workerId: 'w1', projectName: 'A', createdAt: DateTime.now()));
    expect(await db.sendable('w2'), isEmpty);
    expect(await db.hasPendingFor('w2'), isFalse);
    expect(await db.hasPendingFor('w1'), isTrue);
  });

  test('re-inserting the same event id replaces, never duplicates', () async {
    final p = PendingSubmission.fromRequest(request(), workerId: 'w1', projectName: 'A', createdAt: DateTime.now());
    await db.insertPending(p);
    await db.insertPending(p);
    expect((await db.sendable('w1')).length, 1);
  });

  test('attempts count up; a failed row leaves the sendable queue but stays visible', () async {
    await db.insertPending(PendingSubmission.fromRequest(request(), workerId: 'w1', projectName: 'A', createdAt: DateTime.now()));
    await db.recordAttempt('e1', 'noConnection');
    expect((await db.pendingById('e1'))!.attempts, 1);
    await db.markFailed('e1', 'outsideRadius');
    expect(await db.sendable('w1'), isEmpty);
    expect(await db.hasPendingFor('w1'), isFalse);
    expect((await db.failed('w1')).single.lastError, 'outsideRadius');
  });

  test('hasAnySendable: empty false, any worker true, failed-only false', () async {
    expect(await db.hasAnySendable(), isFalse);
    await db.insertPending(PendingSubmission.fromRequest(request(), workerId: 'w9', projectName: 'A', createdAt: DateTime.now()));
    expect(await db.hasAnySendable(), isTrue);
    await db.markFailed('e1', 'OUTSIDE_RADIUS');
    expect(await db.hasAnySendable(), isFalse);
  });

  test('sendable is oldest first', () async {
    await db.insertPending(PendingSubmission.fromRequest(request(eventId: 'late'), workerId: 'w1', projectName: 'A', createdAt: DateTime.parse('2026-08-19T01:00:00Z')));
    await db.insertPending(PendingSubmission.fromRequest(request(eventId: 'early'), workerId: 'w1', projectName: 'A', createdAt: DateTime.parse('2026-08-19T00:00:00Z')));
    expect((await db.sendable('w1')).map((p) => p.eventId), ['early', 'late']);
  });

  test('a row whose project system is unknown cannot become a request', () async {
    final p = PendingSubmission.fromRequest(request(), workerId: 'w1', projectName: 'A', createdAt: DateTime.now());
    expect(p.copyWithSystem('').toRequest(), isNull);
  });

  test('the record mirror is per worker and per Manila date', () async {
    final r = AttendanceRecord(id: 'r1', workDate: '2026-08-19', status: AttendanceStatus.working, timeInAt: DateTime.parse('2026-08-18T23:45:00Z'), timeInProjectName: 'ABC');
    await db.upsertRecord('w1', r, pending: true);
    final back = (await db.recordFor('w1', '2026-08-19'))!;
    expect(back.pending, isTrue);
    expect(back.timeInAt, DateTime.parse('2026-08-18T23:45:00Z'));
    expect(await db.recordFor('w2', '2026-08-19'), isNull);
    await db.clearRecord('w1', '2026-08-19');
    expect(await db.recordFor('w1', '2026-08-19'), isNull);
  });

  test('history between two dates is newest first', () async {
    for (final d in ['2026-08-17', '2026-08-19', '2026-08-18', '2026-08-25']) {
      await db.upsertRecord('w1', AttendanceRecord(id: d, workDate: d, status: AttendanceStatus.complete, totalMinutes: 480), pending: false);
    }
    expect((await db.recordsBetween('w1', '2026-08-17', '2026-08-19')).map((r) => r.workDate), ['2026-08-19', '2026-08-18', '2026-08-17']);
  });

  test('the project cache replaces (a deactivated project disappears) and keeps fences', () async {
    await db.replaceProjects('w1', [
      const AttendanceProject(system: ProjectSystem.pc, id: 'a', name: 'Alpha', geofence: Geofence(latitude: 14.5, longitude: 121, radiusMetres: 150)),
      const AttendanceProject(system: ProjectSystem.pc, id: 'b', name: 'Beta'),
    ]);
    await db.replaceProjects('w1', [const AttendanceProject(system: ProjectSystem.pc, id: 'a', name: 'Alpha', geofence: Geofence(latitude: 14.5, longitude: 121, radiusMetres: 150))]);
    final list = await db.projects('w1');
    expect(list.map((p) => p.id), ['a']);
    expect(list.single.geofence!.radiusMetres, 150);
    expect(await db.projects('w2'), isEmpty);
  });
}
