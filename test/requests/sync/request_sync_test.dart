import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import 'package:workmate/attendance/sync/submission_sync.dart' show SyncResult;
import 'package:workmate/requests/data/request_remote.dart';
import 'package:workmate/requests/data/requests_db.dart';
import 'package:workmate/requests/domain/request_draft.dart';
import 'package:workmate/requests/domain/request_failure.dart';
import 'package:workmate/requests/domain/request_op.dart';
import 'package:workmate/requests/sync/request_sync.dart';

import '../request_fakes.dart';

final t0 = DateTime.utc(2026, 10, 5, 1);

void main() {
  late RequestsDb db;
  late FakeRequestRemote remote;
  late RequestSync sync;
  late Directory dir;

  setUpAll(sqfliteFfiInit);
  setUp(() async {
    db = await RequestsDb.open(databaseFactoryFfi, inMemoryDatabasePath, singleInstance: false);
    remote = FakeRequestRemote();
    sync = RequestSync(db: db, remote: remote);
    dir = await Directory.systemTemp.createTemp('req-sync');
  });
  tearDown(() async {
    await db.close();
    await dir.delete(recursive: true);
  });

  Future<String> photo(String name) async {
    final f = File('${dir.path}/$name.jpg');
    await f.writeAsBytes([1, 2, 3]);
    return f.path;
  }

  Future<void> queueDraft({List<String> photos = const []}) async {
    final d = RequestDraft(id: 'd1', createdAt: t0, destination: site, lines: [
      DraftLine.fromCatalog('x1', pipe).copyWith(quantity: '10', photos: photos),
    ]);
    await db.queueDraft('u1', d, [
      RequestOp(opId: 'sub', workerId: 'u1', kind: OpKind.submit, createdAt: t0, draftId: 'd1', body: submitPayload(d)),
      for (var i = 0; i < photos.length; i++)
        RequestOp(
          opId: 'ph$i',
          workerId: 'u1',
          kind: OpKind.photo,
          createdAt: t0,
          draftId: 'd1',
          linePosition: 0,
          body: {'local_path': photos[i], 'photo_id': 'pid$i'},
        ),
    ], t0);
  }

  RequestOp edit(String id, {String line = 'l1', double qty = 8, int base = 1, OpKind kind = OpKind.quantity}) =>
      RequestOp(opId: id, workerId: 'u1', kind: kind, createdAt: t0, requestId: 'r9', lineId: line, baseVersion: base, body: {'quantity': qty});

  test('a draft lands, then its photos attach to its line and leave the phone', () async {
    final p = await photo('a');
    await queueDraft(photos: [p]);
    expect(await sync.drain('u1'), SyncResult.done);
    expect(remote.calls, ['submit:sub', 'photo:r1:r1-l0']);
    expect(remote.attached, ['u1/r1/pid0.jpg']);
    expect(await db.links('u1'), {'d1': 'r1'});
    expect(await db.sendable('u1'), isEmpty);
    expect(sync.settled, 2);
    expect(File(p).existsSync(), isFalse, reason: 'deleted only after the attach landed');
  });

  test('no signal: everything waits, in order, and nothing is lost', () async {
    final p = await photo('a');
    await queueDraft(photos: [p]);
    remote.writeError = const SocketException('down');
    expect(await sync.drain('u1'), SyncResult.retry);
    expect((await db.sendable('u1')).map((o) => o.opId), ['sub', 'ph0']);
    expect(File(p).existsSync(), isTrue);
    expect(await sync.drain('u1'), SyncResult.done);
    expect(remote.submits, 1);
  });

  test('a refused draft is kept, with its photos, for the worker to fix', () async {
    final p = await photo('a');
    await queueDraft(photos: [p]);
    remote.writeError = Exception('DESTINATION_CLOSED');
    expect(await sync.drain('u1'), SyncResult.done);
    final ops = await db.ops('u1');
    expect(ops.every((o) => o.failedPermanently), isTrue);
    expect(ops.first.lastError, 'destinationClosed');
    expect(remote.calls, ['submit:sub'], reason: 'its photo is never sent');
    expect(File(p).existsSync(), isTrue);
  });

  test('a lost photo file fails that photo, not the request', () async {
    await queueDraft(photos: ['${dir.path}/gone.jpg']);
    expect(await sync.drain('u1'), SyncResult.done);
    final ops = await db.ops('u1');
    expect(ops.single.lastError, 'PHOTO_MISSING');
    expect(await db.links('u1'), {'d1': 'r1'});
  });

  test('two queued edits of one line: the second rides on the first answer', () async {
    await db.addOps([edit('e1', qty: 8, base: 1), edit('e2', qty: 6, base: 2)]);
    remote.quantityResult = {'status': 'applied', 'version': 5, 'needed': 8};
    await sync.drain('u1');
    expect(remote.quantityBases, [1, 5]);
  });

  test('after a conflict, the later edit of that line conflicts too', () async {
    await db.addOps([edit('e1', base: 1), edit('e2', qty: 6, base: 2), edit('e3', line: 'l2', base: 4)]);
    remote.quantityResult = {'status': 'conflict', 'version': 3, 'needed': 12};
    await sync.drain('u1');
    expect(remote.quantityBases, [1, 0, 4]);
  });

  test('a refused edit does not push the next edit into a false conflict', () async {
    await db.addOps([edit('e1', qty: 20, base: 3), edit('e2', qty: 6, base: 4)]);
    remote.writeError = Exception('DESTINATION_CLOSED');
    await sync.drain('u1');
    expect((await db.op('e1'))!.failedPermanently, isTrue);
    expect(remote.quantityBases, [3], reason: 'e1 was refused; e2 went with e1\'s base 3');
    expect(await db.sendable('u1'), isEmpty);
  });

  test('a no-op answer still hands its version on, edit by edit', () async {
    await db.addOps([edit('e1', qty: 10, base: 2), edit('e2', qty: 8, base: 3), edit('e3', qty: 6, base: 4)]);
    remote.quantityResult = {'status': 'applied', 'version': 2, 'needed': 10};
    await sync.drain('u1');
    expect(remote.quantityBases, [2, 2, 2]);
  });

  test('another worker\'s ops are never sent under this session', () async {
    await db.addOps([RequestOp(opId: 'x', workerId: 'u2', kind: OpKind.cancelRequest, createdAt: t0, requestId: 'r9')]);
    expect(await sync.drain('u1'), SyncResult.done);
    expect(await sync.drain(''), SyncResult.done);
    expect(remote.calls, isEmpty);
  });

  test('an unexpected failure is retried, then given up so the queue moves', () async {
    await db.addOps([edit('e1'), RequestOp(opId: 'c', workerId: 'u1', kind: OpKind.cancelRequest, createdAt: t0, requestId: 'r9')]);
    remote
      ..writeError = Exception('boom')
      ..writeErrorSticky = true;
    for (var i = 0; i < 9; i++) {
      expect(await sync.drain('u1'), SyncResult.retry);
    }
    remote.writeErrorSticky = false;
    remote.writeError = Exception('boom');
    expect(await sync.drain('u1'), SyncResult.done);
    expect((await db.op('e1'))!.failedPermanently, isTrue);
    expect(remote.calls.last, 'cancelRequest:r9');
  });

  test('waiting offline never counts toward giving up', () async {
    await db.addOps([edit('e1')]);
    for (var i = 0; i < 9; i++) {
      remote.writeError = const SocketException('down');
      expect(await sync.drain('u1'), SyncResult.retry);
    }
    remote.writeError = Exception('boom');
    expect(await sync.drain('u1'), SyncResult.retry);
    final op = (await db.op('e1'))!;
    expect(op.failedPermanently, isFalse);
    expect(op.attempts, 1);
  });

  test('a photo the server never sees counts toward giving up; an app update never does', () async {
    final p = await photo('a');
    await queueDraft(photos: [p]);
    // Land the submit, then make every photo attach fail PHOTO_NOT_UPLOADED.
    final photoSync = RequestSync(db: db, remote: _PhotoNeverSeen(remote));
    for (var i = 0; i < maxUnexpectedAttempts - 1; i++) {
      expect(await photoSync.drain('u1'), SyncResult.retry);
    }
    expect(await photoSync.drain('u1'), SyncResult.done);
    final ph = (await db.op('ph0'))!;
    expect(ph.failedPermanently, isTrue);
    expect(ph.lastError, 'photoNotUploaded');

    await db.addOps([edit('e1')]);
    remote
      ..writeError = Exception('APP_UPDATE_REQUIRED')
      ..writeErrorSticky = true;
    for (var i = 0; i < maxUnexpectedAttempts + 2; i++) {
      expect(await sync.drain('u1'), SyncResult.retry);
    }
    final e1 = (await db.op('e1'))!;
    expect(e1.failedPermanently, isFalse);
    expect(e1.attempts, 0);
  });

  test('a photo path is exactly what the upload policy accepts', () {
    expect(requestPhotoPath(workerId: 'u1', requestId: 'r1', photoId: 'p1'), 'u1/r1/p1.jpg');
    expect(quantityParams('o', 'l', 3, 8), {'p_op': 'o', 'p_line': 'l', 'p_base_version': 3, 'p_quantity': 8.0});
    expect(attachParams('o', 'r', null, 'u1/r/p.jpg'), {'p_op': 'o', 'p_request': 'r', 'p_line': null, 'p_path': 'u1/r/p.jpg'});
  });
}

/// The submit goes through; every photo attach is refused PHOTO_NOT_UPLOADED.
class _PhotoNeverSeen extends FakeRequestRemote {
  _PhotoNeverSeen(this._inner);
  final FakeRequestRemote _inner;

  @override
  Future<Map<String, dynamic>> submit(String opId, Map<String, dynamic> payload, {required String workerId}) =>
      _inner.submit(opId, payload, workerId: workerId);

  @override
  Future<void> attachPhoto({
    required String opId,
    required String requestId,
    required String? lineId,
    required String photoId,
    required String localPath,
    required String workerId,
  }) async =>
      throw Exception('PHOTO_NOT_UPLOADED');
}
