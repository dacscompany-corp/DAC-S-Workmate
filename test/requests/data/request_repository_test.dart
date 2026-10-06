import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import 'package:workmate/requests/data/request_repository.dart';
import 'package:workmate/requests/data/requests_api.dart';
import 'package:workmate/requests/data/requests_db.dart';
import 'package:workmate/requests/domain/remote_request.dart';
import 'package:workmate/requests/domain/request_draft.dart';
import 'package:workmate/requests/domain/request_op.dart';
import 'package:workmate/requests/domain/request_status.dart';
import 'package:workmate/requests/sync/request_sync.dart';

import '../../attendance/fakes.dart';
import '../domain/request_models_test.dart' show requestDoc;
import '../request_fakes.dart';

void main() {
  late RequestsDb db;
  late FakeRequestRemote remote;
  late Directory dir;
  late RequestRepository repo;
  var worker = 'u1';
  var ids = 0;
  var kicks = 0;

  setUpAll(sqfliteFfiInit);
  setUp(() async {
    db = await RequestsDb.open(databaseFactoryFfi, inMemoryDatabasePath, singleInstance: false);
    remote = FakeRequestRemote();
    dir = await Directory.systemTemp.createTemp('req-repo');
    worker = 'u1';
    ids = 0;
    kicks = 0;
    repo = RequestRepository(
      db: db,
      remote: remote,
      device: FakeDevice(),
      scheduler: FakeScheduler(),
      currentWorkerId: () => worker,
      photoDir: () async => dir,
      sendNow: () async => kicks++,
      now: () => DateTime.utc(2026, 10, 5, 2),
      newId: () => 'id${++ids}',
    );
  });
  tearDown(() async {
    await db.close();
    await dir.delete(recursive: true);
  });

  RequestDraft ready() => repo.newDraft().copyWith(destination: site, lines: [DraftLine.fromCatalog('x1', pipe).copyWith(quantity: '10')]);

  test('choices are cached, and served from the cache with no signal', () async {
    final fresh = await repo.references();
    expect(fresh.fromCache, isFalse);
    expect(fresh.destinations, [site, fence]);
    remote.readError = const SocketException('down');
    final cached = await repo.references();
    expect(cached.fromCache, isTrue);
    expect(cached.destinations, [site, fence]);
    expect(cached.teams.single.iLead, isTrue);
    expect(cached.catalog.map((c) => c.id), ['c1', 'c2']);
    worker = 'u2';
    await expectLater(repo.references(), throwsA(isA<SocketException>()), reason: 'never another worker\'s cache');
  });

  test('a draft is saved, listed, and discarded with its photos', () async {
    final raw = File('${dir.path}/raw.jpg')..writeAsBytesSync([1]);
    final kept = await repo.keepPhoto('d-x', raw.path);
    expect(kept, startsWith(dir.path));
    File(kept).writeAsBytesSync([1]); // FakeDevice returns the target without writing it
    final d = ready().copyWith(lines: [DraftLine.fromCatalog('x1', pipe).copyWith(quantity: '1', photos: [kept])]);
    await repo.saveDraft(d);
    expect((await repo.drafts()).single.id, d.id);
    await repo.deleteDraft(d);
    expect(await repo.drafts(), isEmpty);
    expect(File(kept).existsSync(), isFalse);
  });

  test('an incomplete draft is refused before it is queued', () async {
    final d = repo.newDraft();
    await expectLater(repo.send(d), throwsA(isA<DraftInvalid>()));
    expect(await db.sendable('u1'), isEmpty);
  });

  test('sending queues the submit and one op per photo, then starts sending', () async {
    final d = ready().copyWith(lines: [DraftLine.fromCatalog('x1', pipe).copyWith(quantity: '10', photos: ['/p/a.jpg', '/p/b.jpg'])]);
    await repo.send(d);
    final queue = await db.sendable('u1');
    expect(queue.map((o) => o.kind), [OpKind.submit, OpKind.photo, OpKind.photo]);
    expect(queue.first.body['folder_id'], 'f1');
    expect(queue[1].linePosition, 0);
    expect(queue[1].photoId, isNot(queue[2].photoId));
    expect(await repo.drafts(), isEmpty, reason: 'a queued draft is no longer editable');
    expect(kicks, 1);
  });

  test('the list shows a sent draft as Pending until the server has it', () async {
    await repo.send(ready());
    remote.requestsError = const SocketException('down');
    var view = await repo.myRequests();
    expect(view.entries.single.state, SyncState.pending);
    expect(view.entries.single.draft, isNotNull);
    expect(view.error, isA<SocketException>());

    remote.requestsError = null;
    await RequestSync(db: db, remote: remote).drain('u1');
    remote.requests = [requestDoc(id: 'r1')];
    view = await repo.myRequests();
    expect(view.entries.single.remote!.id, 'r1');
    expect(view.entries.single.state, SyncState.received);
    expect(await db.drafts('u1', queued: true), isEmpty, reason: 'the phone copy is forgotten once the server shows it');
  });

  test('a refused draft shows Failed and can go back to drafts', () async {
    await repo.send(ready());
    remote.writeError = Exception('DESTINATION_CLOSED');
    await RequestSync(db: db, remote: remote).drain('u1');
    final view = await repo.myRequests();
    expect(view.entries.single.state, SyncState.failed);
    expect(view.entries.single.failedOps.single.lastError, 'destinationClosed');
    expect(await repo.returnToDrafts(view.entries.single.draft!.id), isTrue);
    expect((await repo.drafts()).single.lines.single.quantity, '10');
    expect((await repo.myRequests()).entries, isEmpty);
  });

  test('edits chain their base versions and show as pending on the request', () async {
    remote.requests = [requestDoc(id: 'r1')];
    final r = RemoteRequest.fromJson(requestDoc(id: 'r1'));
    final l = r.lines.single; // version 2
    await repo.changeQuantity(r, l, 8);
    await repo.changeQuantity(r, l, 6);
    final queue = await db.sendable('u1');
    expect(queue.map((o) => o.baseVersion), [2, 3]);
    final entry = (await repo.myRequests()).entries.single;
    expect(entry.state, SyncState.pending);
    expect(entry.pendingQuantity(l.id), 6);
    await repo.cancelLine(r, l);
    await repo.cancelRequest(r);
    final entry2 = (await repo.myRequests()).entries.single;
    expect(entry2.cancelPending(l.id), isTrue);
    expect(kicks, 4);
  });

  test('a refused photo can be dismissed, and its file goes with it', () async {
    final f = File('${dir.path}/p.jpg')..writeAsBytesSync([1]);
    await db.addOps([
      RequestOp(
        opId: 'ph',
        workerId: 'u1',
        kind: OpKind.photo,
        createdAt: DateTime.utc(2026),
        requestId: 'r1',
        body: {'local_path': f.path, 'photo_id': 'p'},
      ),
    ]);
    await repo.dismissFailed((await db.op('ph'))!);
    expect(await db.op('ph'), isNotNull, reason: 'a sendable op is never dismissed');
    await db.markFailed('ph', 'unexpected');
    await repo.dismissFailed((await db.op('ph'))!);
    expect(await db.op('ph'), isNull);
    expect(f.existsSync(), isFalse);
  });

  test('a second Send of the same draft queues nothing', () async {
    final d = ready();
    await repo.send(d);
    await repo.send(d);
    expect((await db.sendable('u1')).where((o) => o.kind == OpKind.submit).length, 1);
    expect(kicks, 1);
  });

  test('deleting a draft that was already sent touches neither it nor its photos', () async {
    final f = File('${dir.path}/owed.jpg')..writeAsBytesSync([1]);
    final d = ready().copyWith(lines: [DraftLine.fromCatalog('x1', pipe).copyWith(quantity: '1', photos: [f.path])]);
    await repo.send(d);
    await repo.deleteDraft(d);
    expect(f.existsSync(), isTrue);
    expect((await db.drafts('u1', queued: true)).single.id, d.id);
  });

  test('a refused submit is not dismissed (it goes back to Drafts instead)', () async {
    await repo.send(ready());
    final submit = (await db.sendable('u1')).first;
    await db.markFailed(submit.opId, 'destinationClosed');
    await repo.dismissFailed((await db.op(submit.opId))!);
    expect(await db.op(submit.opId), isNotNull);
  });

  test('nobody signed in: nothing is read or written', () async {
    worker = '';
    await expectLater(repo.myRequests(), throwsA(isA<StateError>()));
    await expectLater(repo.saveDraft(ready()), throwsA(isA<StateError>()));
  });
}
