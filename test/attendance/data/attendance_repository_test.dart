import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import 'package:workmate/attendance/data/attendance_db.dart';
import 'package:workmate/attendance/data/attendance_remote.dart';
import 'package:workmate/attendance/data/attendance_repository.dart';
import 'package:workmate/attendance/data/submission_request.dart';
import 'package:workmate/attendance/device/device_bridge.dart';
import 'package:workmate/attendance/domain/attendance_record.dart';
import 'package:workmate/attendance/domain/location_verification.dart';
import 'package:workmate/attendance/domain/work_date.dart';
import 'package:workmate/attendance/sync/upload_scheduler.dart';

class FakeDevice implements DeviceBridge {
  bool online = false;
  String? lastCaption;
  bool? lastMirror;
  @override
  Future<DeviceClockReading> clock() async => const DeviceClockReading(uptimeMillis: 0, bootCount: null);
  @override
  Future<bool> isOnline() async => online;
  @override
  Future<DeviceFix> currentFix() async => const DeviceFix();
  @override
  Future<String> preparePhoto({required String source, required String target, required String caption, bool mirror = false}) async {
    lastCaption = caption;
    lastMirror = mirror;
    await File(source).copy(target);
    await File(source).delete();
    return target;
  }

  @override
  Future<void> openLocationSettings() async {}
}

class FakeRemote implements AttendanceRemote {
  Object? todayError;
  AttendanceRecord? todayRow;
  Object? historyError;
  List<AttendanceRecord> historyRows = [];
  Object? projectsError;
  List<AttendanceProject> projectRows = [];
  @override
  Future<AttendanceRecord> submit(SubmissionRequest r, {required String workerId}) => throw UnimplementedError();
  @override
  Future<AttendanceRecord?> today(String workDate) async {
    if (todayError != null) throw todayError!;
    return todayRow;
  }
  @override
  Future<List<AttendanceRecord>> history(String from, String to) async {
    if (historyError != null) throw historyError!;
    return historyRows;
  }
  @override
  Future<List<AttendanceProject>> activeProjects() async {
    if (projectsError != null) throw projectsError!;
    return projectRows;
  }
}

class FakeScheduler implements UploadScheduler {
  final enqueued = <String>[];
  bool failEnqueue = false;
  @override
  Future<void> enqueue(String eventId) async {
    if (failEnqueue) throw StateError('workmanager down');
    enqueued.add(eventId);
  }
  @override
  Future<void> sendNow() async {}
  @override
  Future<void> ensureSweeper() async {}
}

void main() {
  late AttendanceDb db;
  late Directory tmp;
  late FakeDevice device;
  late FakeRemote remote;
  late FakeScheduler scheduler;
  late AttendanceRepository repo;
  var now = DateTime.parse('2026-08-19T02:00:00Z'); // 10:00 Manila, 19 Aug

  setUpAll(sqfliteFfiInit);
  setUp(() async {
    db = await AttendanceDb.open(databaseFactoryFfi, inMemoryDatabasePath, singleInstance: false);
    tmp = await Directory.systemTemp.createTemp('wmrepo');
    device = FakeDevice();
    remote = FakeRemote();
    scheduler = FakeScheduler();
    now = DateTime.parse('2026-08-19T02:00:00Z');
    repo = AttendanceRepository(
      db: db,
      remote: remote,
      device: device,
      scheduler: scheduler,
      currentWorkerId: () => 'w1',
      photoDir: () async => tmp,
      now: () => now,
    );
    await db.replaceProjects('w1', [const AttendanceProject(system: ProjectSystem.pc, id: 'p1', name: 'ABC Building Project')]);
  });
  tearDown(() async {
    await db.close();
    await tmp.delete(recursive: true);
  });

  Future<SubmissionRequest> request(TimeDirection d, String captured, {String eventId = 'e1'}) async {
    final raw = File('${tmp.path}/raw-$eventId.jpg')..writeAsBytesSync([1, 2, 3]);
    return SubmissionRequest(
      direction: d,
      projectSystem: ProjectSystem.pc,
      projectId: 'p1',
      capturedAt: DateTime.parse(captured),
      trustedAt: null,
      photoPath: raw.path,
      description: null,
      eventId: eventId,
    );
  }

  test('SUBMIT is durable on the phone before anything leaves it', () async {
    final mirror = await repo.submit(await request(TimeDirection.timeIn, '2026-08-18T23:45:00Z'));
    expect(mirror.pending, isTrue);
    expect(mirror.status, AttendanceStatus.working);
    expect(mirror.workDate, '2026-08-19');
    final row = (await db.sendable('w1')).single;
    expect(row.photoLocalPath, endsWith('e1.jpg'));
    expect(File(row.photoLocalPath).existsSync(), isTrue);
    expect(row.wasOffline, isTrue, reason: 'decided at capture, not at upload');
    expect(device.lastCaption, 'ABC Building Project · 19 Aug 2026 · 7:45 AM');
    expect(scheduler.enqueued, ['e1']);
  });

  test('an empty worker is refused before anything is queued or mirrored', () async {
    final anon = AttendanceRepository(
      db: db, remote: remote, device: device, scheduler: scheduler,
      currentWorkerId: () => '', photoDir: () async => tmp, now: () => now,
    );
    await expectLater(anon.submit(await request(TimeDirection.timeIn, '2026-08-18T23:45:00Z')), throwsA(isA<StateError>()));
    expect(await db.sendable(''), isEmpty);
    expect(await db.recordFor('', '2026-08-19'), isNull);
  });

  test('a failed enqueue does not fail a saved submit', () async {
    scheduler.failEnqueue = true;
    final mirror = await repo.submit(await request(TimeDirection.timeIn, '2026-08-18T23:45:00Z'));
    expect(mirror.pending, isTrue);
    expect((await db.sendable('w1')).single.eventId, 'e1');
  });

  test('a Time Out completes the mirror with optimistic minutes', () async {
    await repo.submit(await request(TimeDirection.timeIn, '2026-08-18T23:45:00Z'));
    final out = await repo.submit(await request(TimeDirection.timeOut, '2026-08-19T09:30:00Z', eventId: 'e2'));
    expect(out.status, AttendanceStatus.complete);
    expect(out.totalMinutes, 585);
    expect(out.timeOutProjectName, 'ABC Building Project');
  });

  test("today: the server's row wins and is mirrored", () async {
    remote.todayRow = AttendanceRecord(id: 's1', workDate: '2026-08-19', status: AttendanceStatus.complete, totalMinutes: 480);
    final t = (await repo.today())!;
    expect(t.id, 's1');
    expect((await db.recordFor('w1', '2026-08-19'))!.totalMinutes, 480);
  });

  test('today offline: what the phone remembers, still marked pending', () async {
    await repo.submit(await request(TimeDirection.timeIn, '2026-08-18T23:45:00Z'));
    remote.todayError = const SocketException('down');
    final t = (await repo.today())!;
    expect(t.status, AttendanceStatus.working);
    expect(t.pending, isTrue);
  });

  test('today: a queued Time In survives the server saying "nothing yet"', () async {
    await repo.submit(await request(TimeDirection.timeIn, '2026-08-18T23:45:00Z'));
    remote.todayRow = null;
    expect((await repo.today())!.pending, isTrue);
  });

  test('today offline with nothing cached is an error, not an empty day', () async {
    remote.todayError = const SocketException('down');
    await expectLater(repo.today(), throwsA(isA<SocketException>()));
  });

  test('today: no row anywhere and nothing queued clears a stale mirror', () async {
    await db.upsertRecord('w1', AttendanceRecord(id: 'x', workDate: '2026-08-19', status: AttendanceStatus.working), pending: false);
    expect(await repo.today(), isNull);
    expect(await db.recordFor('w1', '2026-08-19'), isNull);
  });

  test('history is mirrored when fetched and served offline', () async {
    remote.historyRows = [AttendanceRecord(id: 'h', workDate: '2026-08-18', status: AttendanceStatus.complete, totalMinutes: 500)];
    expect((await repo.history('2026-08-17', '2026-08-19')).single.id, 'h');
    remote.historyError = const SocketException('down');
    expect((await repo.history('2026-08-17', '2026-08-19')).single.totalMinutes, 500);
  });

  Future<void> queueInAndOut() async {
    await repo.submit(await request(TimeDirection.timeIn, '2026-08-18T23:45:00Z'));
    await repo.submit(await request(TimeDirection.timeOut, '2026-08-19T09:30:00Z', eventId: 'e2'));
  }

  test("today: a queued Time Out is not overwritten by the server's older row", () async {
    await queueInAndOut();
    remote.todayRow = AttendanceRecord(id: 's1', workDate: '2026-08-19', status: AttendanceStatus.working);
    final t = (await repo.today())!;
    expect(t.status, AttendanceStatus.complete);
    expect(t.pending, isTrue);
    expect((await db.recordFor('w1', '2026-08-19'))!.status, AttendanceStatus.complete);
  });

  test('history: a day with a queued Time Out keeps the phone row', () async {
    await queueInAndOut();
    remote.historyRows = [AttendanceRecord(id: 's1', workDate: '2026-08-19', status: AttendanceStatus.working)];
    final list = await repo.history('2026-08-17', '2026-08-19');
    expect(list.single.status, AttendanceStatus.complete);
    expect(list.single.pending, isTrue);
    expect((await db.recordFor('w1', '2026-08-19'))!.status, AttendanceStatus.complete);
  });

  test('history: a queue-only day in range appears in the online result', () async {
    await queueInAndOut();
    remote.historyRows = [AttendanceRecord(id: 'h', workDate: '2026-08-18', status: AttendanceStatus.complete, totalMinutes: 500)];
    final list = await repo.history('2026-08-17', '2026-08-19');
    expect(list.map((r) => r.workDate), ['2026-08-19', '2026-08-18']);
    expect(list.first.pending, isTrue);
  });

  test('history offline with an empty mirror is an error, never "you never worked"', () async {
    remote.historyError = const SocketException('down');
    await expectLater(repo.history('2026-08-01', '2026-08-02'), throwsA(isA<SocketException>()));
  });

  test('projects: a fresh list replaces the cache; offline serves the cache', () async {
    remote.projectRows = [const AttendanceProject(system: ProjectSystem.pc, id: 'p2', name: 'New Site')];
    expect((await repo.activeProjects()).single.id, 'p2');
    remote.projectsError = const SocketException('down');
    expect((await repo.activeProjects()).single.name, 'New Site');
  });

  test('a front-camera photo is filed mirrored, as the worker saw it', () async {
    await repo.submit(await request(TimeDirection.timeIn, '2026-08-18T23:45:00Z'), mirrorPhoto: true);
    expect(device.lastMirror, isTrue);
  });

  test('a back-camera photo is filed as taken', () async {
    await repo.submit(await request(TimeDirection.timeIn, '2026-08-18T23:45:00Z'));
    expect(device.lastMirror, isFalse);
  });

  test("refused submissions are this worker's failed rows only", () async {
    await repo.submit(await request(TimeDirection.timeIn, '2026-08-18T23:45:00Z'));
    expect(await repo.refusedSubmissions(), isEmpty);
    await db.markFailed('e1', 'outsideRadius');
    final refused = await repo.refusedSubmissions();
    expect(refused.single.eventId, 'e1');
    expect(refused.single.lastError, 'outsideRadius');
  });

  test('dismissing a refused submission deletes the row and its photo', () async {
    await repo.submit(await request(TimeDirection.timeIn, '2026-08-18T23:45:00Z'));
    final photo = (await db.sendable('w1')).single.photoLocalPath;
    await db.markFailed('e1', 'outsideRadius');
    await repo.dismissRefused('e1');
    expect(await db.pendingById('e1'), isNull);
    expect(File(photo).existsSync(), isFalse);
  });

  test('a row still owed to the server cannot be dismissed', () async {
    await repo.submit(await request(TimeDirection.timeIn, '2026-08-18T23:45:00Z'));
    await repo.dismissRefused('e1');
    expect(await db.pendingById('e1'), isNotNull);
  });

  test("another worker's refused row is neither listed nor dismissed", () async {
    await repo.submit(await request(TimeDirection.timeIn, '2026-08-18T23:45:00Z'));
    await db.markFailed('e1', 'outsideRadius');
    final other = AttendanceRepository(
      db: db,
      remote: remote,
      device: device,
      scheduler: scheduler,
      currentWorkerId: () => 'w2',
      photoDir: () async => tmp,
      now: () => now,
    );
    expect(await other.refusedSubmissions(), isEmpty);
    await other.dismissRefused('e1');
    expect(await db.pendingById('e1'), isNotNull);
  });
}
