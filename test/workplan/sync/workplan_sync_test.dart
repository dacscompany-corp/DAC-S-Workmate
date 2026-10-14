import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import 'package:workmate/attendance/sync/submission_sync.dart';
import 'package:workmate/workplan/data/workplan_db.dart';
import 'package:workmate/workplan/domain/wp_failure.dart';
import 'package:workmate/workplan/domain/wp_op.dart';
import 'package:workmate/workplan/sync/workplan_sync.dart';
import 'package:workmate/workplan/ui/workplan_copy.dart';

import '../workplan_fakes.dart';

void main() {
  late WorkPlanDb db;
  late FakeWorkPlanRemote remote;
  var n = 0;

  setUpAll(sqfliteFfiInit);
  setUp(() async {
    db = await WorkPlanDb.open(databaseFactoryFfi, inMemoryDatabasePath, singleInstance: false);
    remote = FakeWorkPlanRemote();
    n = 0;
  });
  tearDown(() => db.close());

  WpOp op(WpOpKind kind, {String worker = 'u1', String? parent, Map<String, dynamic> body = const {}}) => WpOp(
        opId: 'o${++n}',
        workerId: worker,
        kind: kind,
        createdAt: DateTime.utc(2026, 10, 14),
        taskId: 't1',
        parentOpId: parent,
        body: body,
      );

  test('nothing is sent under nobody, nor another worker\'s actions', () async {
    await db.addOps([op(WpOpKind.start, worker: 'u2')]);
    final s = WorkPlanSync(db: db, remote: remote);
    expect(await s.drain(''), SyncResult.done);
    expect(await s.drain('u1'), SyncResult.done);
    expect(remote.calls, isEmpty);
    expect(await db.sendable('u2'), hasLength(1));
  });

  test('a session problem waits; it never gives the action up', () async {
    remote.failOn['start'] = StateError('AUTH_REQUIRED');
    await db.addOps([op(WpOpKind.start)]);
    final s = WorkPlanSync(db: db, remote: remote);
    for (var i = 0; i < 15; i++) {
      expect(await s.drain('u1'), SyncResult.retry);
    }
    expect((await db.sendable('u1')).single.attempts, 0);
  });

  test('ten unexpected failures in a row give one action up, so the queue moves on', () async {
    remote.failOn['start'] = StateError('weird');
    await db.addOps([op(WpOpKind.start), op(WpOpKind.done)]);
    final s = WorkPlanSync(db: db, remote: remote);
    for (var i = 0; i < maxWpAttempts - 1; i++) {
      expect(await s.drain('u1'), SyncResult.retry);
    }
    expect(await s.drain('u1'), SyncResult.done);
    expect(remote.calls.last, 'done:t1');
    final failed = (await db.ops('u1')).where((o) => o.failedPermanently).single;
    expect(failed.kind, WpOpKind.start);
    expect(WpFailure.fromStored(failed.lastError), WpFailure.unexpected);
  });

  test('an unreadable photo file is given up after the cap, so it cannot hold the queue', () async {
    final file = File('${Directory.systemTemp.path}/wp-unreadable.jpg')..writeAsBytesSync([1]);
    addTearDown(() => file.deleteSync());
    final report = op(WpOpKind.progress, body: {'note': 'x'});
    await db.addOps([
      report,
      op(WpOpKind.photo, parent: report.opId, body: {'local_path': file.path, 'photo_id': 'p1'}),
      op(WpOpKind.done),
    ]);
    remote.failOn['photo'] = const FileSystemException('unreadable');
    final s = WorkPlanSync(db: db, remote: remote);
    for (var i = 0; i < maxWpAttempts - 1; i++) {
      expect(await s.drain('u1'), SyncResult.retry);
    }
    expect(await s.drain('u1'), SyncResult.done);
    expect(remote.calls.last, 'done:t1');
    expect((await db.ops('u1')).where((o) => o.failedPermanently).single.kind, WpOpKind.photo);
  });

  test('a photo whose file is gone is flagged, with its own words', () async {
    final report = op(WpOpKind.progress, body: {'note': 'x'});
    await db.addOps([report, op(WpOpKind.photo, parent: report.opId, body: {'local_path': '/nope.jpg', 'photo_id': 'p1'})]);
    await WorkPlanSync(db: db, remote: remote).drain('u1');
    final photo = (await db.ops('u1')).single;
    expect(photo.lastError, 'PHOTO_MISSING');
    expect(opFailureCopy(photo), photoNotSentCopy);
  });
}
