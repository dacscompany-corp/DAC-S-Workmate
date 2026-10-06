import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import 'package:workmate/requests/data/requests_db.dart';
import 'package:workmate/requests/domain/request_draft.dart';
import 'package:workmate/requests/domain/request_op.dart';

final t0 = DateTime.utc(2026, 10, 5, 1);

RequestDraft draft(String id) => RequestDraft(id: id, createdAt: t0, lines: const [DraftLine(id: 'x1', description: 'Sand', unit: 'bag', quantity: '5')]);

RequestOp op(String id, OpKind kind, {String worker = 'u1', String? draftId, int? pos, String? lineId}) => RequestOp(
      opId: id,
      workerId: worker,
      kind: kind,
      createdAt: t0,
      draftId: draftId,
      linePosition: pos,
      lineId: lineId,
      body: kind == OpKind.photo ? {'local_path': '/p/$id.jpg', 'photo_id': 'ph-$id'} : const {},
    );

void main() {
  late RequestsDb db;
  setUpAll(sqfliteFfiInit);
  setUp(() async => db = await RequestsDb.open(databaseFactoryFfi, inMemoryDatabasePath, singleInstance: false));
  tearDown(() => db.close());

  test('drafts are per worker and split by queued', () async {
    await db.saveDraft('u1', draft('d1'), t0);
    await db.saveDraft('u2', draft('d2'), t0);
    expect((await db.drafts('u1', queued: false)).map((d) => d.id), ['d1']);
    expect(await db.drafts('u1', queued: true), isEmpty);
    expect(await db.draft('u2', 'd1'), isNull, reason: 'another worker never sees it');
    await db.deleteDraft('u1', 'd1');
    expect(await db.drafts('u1', queued: false), isEmpty);
  });

  test('queueing a draft writes the draft and its ops together, in order', () async {
    await db.addOps([op('old', OpKind.quantity)]);
    await db.queueDraft('u1', draft('d1'), [op('s', OpKind.submit, draftId: 'd1'), op('p', OpKind.photo, draftId: 'd1', pos: 0)], t0);
    expect((await db.drafts('u1', queued: true)).single.id, 'd1');
    final queue = await db.sendable('u1');
    expect(queue.map((o) => o.opId), ['old', 's', 'p']);
    expect(queue.map((o) => o.seq), [1, 2, 3]);
    expect(await db.sendable('u2'), isEmpty);
    expect(await db.hasAnySendable(), isTrue);
    expect(await db.queueDraft('u1', draft('d1'), [op('s2', OpKind.submit, draftId: 'd1')], t0), isFalse);
    expect((await db.sendable('u1')).map((o) => o.opId), ['old', 's', 'p'], reason: 'a second queue of the same draft writes nothing');
  });

  test('a landed submit links its photos to the request and their lines', () async {
    await db.queueDraft('u1', draft('d1'), [
      op('s', OpKind.submit, draftId: 'd1'),
      op('p0', OpKind.photo, draftId: 'd1', pos: 0),
      op('p1', OpKind.photo, draftId: 'd1', pos: 1),
    ], t0);
    await db.link('u1', 'd1', 'r1', ['l0', 'l1']);
    expect(await db.links('u1'), {'d1': 'r1'});
    final photos = (await db.sendable('u1')).where((o) => o.kind == OpKind.photo).toList();
    expect(photos.map((o) => (o.requestId, o.lineId)), [('r1', 'l0'), ('r1', 'l1')]);
    await db.deleteLink('d1');
    expect(await db.links('u1'), isEmpty);
  });

  test('attempts, refusals, rebases and deletes', () async {
    await db.addOps([op('a', OpKind.quantity, lineId: 'l1'), op('b', OpKind.quantity, lineId: 'l1')]);
    await db.recordAttempt('a', 'noConnection');
    await db.setBase('b', 7);
    expect((await db.op('a'))!.attempts, 1);
    expect((await db.op('b'))!.baseVersion, 7);
    await db.markFailed('a', 'lineClosed');
    expect((await db.sendable('u1')).map((o) => o.opId), ['b']);
    expect((await db.ops('u1')).map((o) => o.opId), ['a', 'b']);
    await db.deleteOp('b');
    expect(await db.sendable('u1'), isEmpty);
    expect(await db.hasAnySendable(), isFalse);
  });

  test('a refused draft goes back to editing only when nothing of it can still be sent', () async {
    await db.queueDraft('u1', draft('d1'), [op('s', OpKind.submit, draftId: 'd1'), op('p', OpKind.photo, draftId: 'd1', pos: 0)], t0);
    expect(await db.unqueueDraft('u1', 'd1'), isFalse);
    await db.markFailed('s', 'destinationClosed');
    await db.failDraftOps('d1', 'destinationClosed');
    expect((await db.op('p'))!.failedPermanently, isTrue);
    expect(await db.unqueueDraft('u1', 'd1'), isTrue);
    expect(await db.ops('u1'), isEmpty);
    expect((await db.drafts('u1', queued: false)).single.id, 'd1');
  });

  test('the cache keeps the last answer per worker', () async {
    await db.putCache('u1', 'requests', [
      {'id': 'r1'},
    ], t0);
    final c = await db.cache('u1', 'requests');
    expect(c!.body, [
      {'id': 'r1'},
    ]);
    expect(c.at, t0);
    expect(await db.cache('u2', 'requests'), isNull);
  });

  test('a draft whose request already landed never goes back to editing', () async {
    await db.queueDraft('u1', draft('d1'), [op('s', OpKind.submit, draftId: 'd1'), op('p', OpKind.photo, draftId: 'd1', pos: 0)], t0);
    await db.link('u1', 'd1', 'r1', ['l0']);
    await db.deleteOp('s');
    await db.markFailed('p', 'PHOTO_MISSING');
    expect(await db.unqueueDraft('u1', 'd1'), isFalse);
    expect((await db.drafts('u1', queued: true)).single.id, 'd1');
  });

  test('saving never turns a queued draft back into an editable one', () async {
    await db.queueDraft('u1', draft('d1'), [op('s', OpKind.submit, draftId: 'd1')], t0);
    await db.saveDraft('u1', draft('d1'), t0);
    expect(await db.drafts('u1', queued: false), isEmpty);
    expect((await db.drafts('u1', queued: true)).single.id, 'd1');
  });
}
