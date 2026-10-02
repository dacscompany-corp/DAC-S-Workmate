import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import 'package:workmate/attendance/data/attendance_db.dart';
import 'package:workmate/attendance/data/submission_request.dart';
import 'package:workmate/attendance/domain/attendance_record.dart';
import 'package:workmate/attendance/domain/work_date.dart';
import 'package:workmate/widget/widget_bridge.dart';
import 'package:workmate/widget/widget_publisher.dart';
import 'package:workmate/widget/widget_snapshot.dart';

class RecordingBridge implements WidgetBridge {
  final pushed = <Map<String, Object?>>[];
  Object? error;
  @override
  Future<void> push(WidgetSnapshot snapshot) async {
    if (error != null) throw error!;
    pushed.add(snapshot.toMap());
  }
}

void main() {
  late AttendanceDb db;
  late RecordingBridge bridge;
  final now = DateTime.parse('2026-09-11T02:00:00Z'); // 10:00, Friday 11 Sep, Manila
  final timeIn = DateTime.parse('2026-09-11T00:52:00Z');

  WidgetPublisher publisher() => WidgetPublisher(bridge, now: () => now);

  setUpAll(sqfliteFfiInit);
  setUp(() async {
    db = await AttendanceDb.open(databaseFactoryFfi, inMemoryDatabasePath, singleInstance: false);
    bridge = RecordingBridge();
  });
  tearDown(() async {
    try {
      await db.close();
    } catch (_) {}
  });

  test('nobody signed in: the sign-in state, and nothing about the last worker', () async {
    await db.upsertRecord('w1', AttendanceRecord(id: 'r', workDate: '2026-09-11', status: AttendanceStatus.working, timeInAt: timeIn), pending: false);
    final s = await publisher().snapshotFor(db, '');
    expect(s.toMap(), {
      'signedIn': false,
      'workDate': null,
      'status': null,
      'timeInAt': null,
      'timeOutAt': null,
      'notSentYet': false,
      'readFailed': false,
    });
  });

  test('no record today: today, no status', () async {
    final s = await publisher().snapshotFor(db, 'w1');
    expect(s.signedIn, isTrue);
    expect(s.workDate, '2026-09-11');
    expect(s.status, isNull);
    expect(s.notSentYet, isFalse);
  });

  test("an open day carries its Time In, and a queued row says not sent yet", () async {
    await db.upsertRecord('w1', AttendanceRecord(id: 'r', workDate: '2026-09-11', status: AttendanceStatus.working, timeInAt: timeIn), pending: true);
    await db.insertPending(PendingSubmission.fromRequest(
      SubmissionRequest(
          direction: TimeDirection.timeIn, projectSystem: ProjectSystem.pc, projectId: 'p1', capturedAt: timeIn,
          trustedAt: null, photoPath: '/x/e1.jpg', description: null, eventId: 'e1'),
      workerId: 'w1',
      projectName: 'ABC',
      createdAt: timeIn,
    ));
    final m = (await publisher().snapshotFor(db, 'w1')).toMap();
    expect(m['status'], 'working');
    expect(m['timeInAt'], timeIn.millisecondsSinceEpoch);
    expect(m['notSentYet'], isTrue);
  });

  test("another worker's day is not this worker's", () async {
    await db.upsertRecord('w2', AttendanceRecord(id: 'r', workDate: '2026-09-11', status: AttendanceStatus.complete), pending: false);
    expect((await publisher().snapshotFor(db, 'w1')).status, isNull);
  });

  test('a mirror that cannot be read says so, rather than "not timed in"', () async {
    await db.close();
    final s = await publisher().snapshotFor(db, 'w1');
    expect(s.signedIn, isTrue);
    expect(s.readFailed, isTrue);
  });

  test('a sign-out requested after a worker publish lands last', () async {
    await db.upsertRecord('w1', AttendanceRecord(id: 'r', workDate: '2026-09-11', status: AttendanceStatus.working, timeInAt: timeIn), pending: false);
    final p = publisher();
    final a = p.publish(db, 'w1');
    final b = p.publish(db, '');
    await Future.wait([a, b]);
    expect(bridge.pushed.length, 2);
    expect(bridge.pushed[0]['signedIn'], isTrue);
    expect(bridge.pushed.last['signedIn'], isFalse);
  });

  test('publishIfCurrent skips when the worker is no longer the one let in', () async {
    await publisher().publishIfCurrent(db, 'w1', () => 'w2');
    expect(bridge.pushed, isEmpty);
  });

  test('publishIfCurrent pushes when the worker is still the one let in', () async {
    await publisher().publishIfCurrent(db, 'w1', () => 'w1');
    expect(bridge.pushed.length, 1);
    expect(bridge.pushed.single['signedIn'], isTrue);
  });

  test('publishIfCurrent skips, without throwing, when the current worker cannot be read', () async {
    await publisher().publishIfCurrent(db, 'w1', () => throw StateError('not ready'));
    expect(bridge.pushed, isEmpty);
  });

  test('publish pushes the snapshot, and a bridge failure never escapes', () async {
    await publisher().publish(db, 'w1');
    expect(bridge.pushed.single['workDate'], '2026-09-11');
    bridge.error = StateError('no widget host');
    await publisher().publish(db, 'w1'); // must not throw
  });
}
