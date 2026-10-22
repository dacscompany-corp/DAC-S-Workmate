import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import 'package:workmate/purchasing/data/purchasing_db.dart';
import 'package:workmate/purchasing/domain/pur_op.dart';
import 'package:workmate/purchasing/domain/purchase_draft.dart';

PurchaseDraft d(String id) => PurchaseDraft(id: id, createdAt: DateTime.utc(2026, 10, 21), purchaseDate: '2026-10-21');

PurOp op(String id, String draftId, {String user = 'u1'}) =>
    PurOp(opId: id, userId: user, createdAt: DateTime.utc(2026, 10, 21), draftId: draftId, purchase: const {'source': 'workmate'});

void main() {
  late PurchasingDb db;
  final now = DateTime.utc(2026, 10, 21, 3);

  setUpAll(sqfliteFfiInit);
  setUp(() async => db = await PurchasingDb.open(databaseFactoryFfi, inMemoryDatabasePath, singleInstance: false));
  tearDown(() => db.close());

  test('a draft is kept per account', () async {
    await db.saveDraft('u1', d('d1'), now);
    await db.saveDraft('u2', d('d2'), now);
    expect((await db.drafts('u1', queued: false)).map((x) => x.id), ['d1']);
    expect(await db.draft('u2', 'd1'), isNull);
  });

  test('a purchase is queued once: a second Send records nothing more', () async {
    expect(await db.queueDraft('u1', d('d1'), op('o1', 'd1'), now), isTrue);
    expect(await db.queueDraft('u1', d('d1'), op('o2', 'd1'), now), isFalse);
    expect((await db.sendable('u1')).map((o) => o.opId), ['o1']);
    // A queued draft can no longer be edited by a stray save.
    await db.saveDraft('u1', d('d1'), now);
    expect(await db.drafts('u1', queued: false), isEmpty);
  });

  test('back to editing only once refused; never while it could still be sent', () async {
    await db.queueDraft('u1', d('d1'), op('o1', 'd1'), now);
    expect(await db.unqueueDraft('u1', 'd1'), isFalse);
    await db.markFailed('o1', 'lineClosed');
    expect(await db.unqueueDraft('u1', 'd1'), isTrue);
    expect((await db.drafts('u1', queued: false)).map((x) => x.id), ['d1']);
    expect(await db.ops('u1'), isEmpty);
  });

  test('throwing a refused purchase away takes its op and draft; a sendable one stays', () async {
    await db.queueDraft('u1', d('d1'), op('o1', 'd1'), now);
    expect(await db.discardRefused('u1', 'd1'), isNull);
    await db.markFailed('o1', 'lineClosed');
    expect((await db.discardRefused('u1', 'd1'))!.id, 'd1');
    expect(await db.unsentCount('u1'), 0);
  });

  test('recorded: op and draft go together', () async {
    await db.queueDraft('u1', d('d1'), op('o1', 'd1'), now);
    await db.finishRecord('o1', 'd1');
    expect(await db.ops('u1'), isEmpty);
    expect(await db.drafts('u1', queued: true), isEmpty);
  });

  test('progress is kept between attempts', () async {
    await db.queueDraft('u1', d('d1'), op('o1', 'd1'), now);
    final o = (await db.sendable('u1')).single
        .copyWith(companyId: 'c1', receipts: {'supplier_invoice_url': const ReceiptUpload(local: '/a.jpg', photoId: 'x', url: 'https://u')});
    await db.updateOpBody('o1', o.bodyJson);
    final back = (await db.sendable('u1')).single;
    expect(back.companyId, 'c1');
    expect(back.receipts['supplier_invoice_url']!.url, 'https://u');
  });

  test('only unexpected failures count toward giving up', () async {
    await db.queueDraft('u1', d('d1'), op('o1', 'd1'), now);
    await db.recordAttempt('o1', 'unexpected');
    await db.recordAttempt('o1', 'unexpected');
    expect((await db.sendable('u1')).single.attempts, 2);
    await db.recordAttempt('o1', 'noConnection', countsTowardCap: false);
    expect((await db.sendable('u1')).single.attempts, 0);
  });

  test('unsent counts drafts being edited, waiting or refused', () async {
    await db.saveDraft('u1', d('d1'), now);
    await db.queueDraft('u1', d('d2'), op('o2', 'd2'), now);
    expect(await db.unsentCount('u1'), 2);
    expect(await db.unsentCount('u2'), 0);
    expect(await db.hasAnySendable(), isTrue);
  });

  test('the saved copy keeps only one account; drafts are never touched', () async {
    await db.putCache('u1', 'shopping', const [1], now);
    await db.putCache('u2', 'shopping', const [2], now);
    await db.saveDraft('u2', d('d2'), now);
    await db.keepCacheOnly('u1');
    expect(await db.cache('u2', 'shopping'), isNull);
    expect((await db.cache('u1', 'shopping'))!.body, [1]);
    await db.keepCacheOnly('');
    expect(await db.cache('u1', 'shopping'), isNull);
    expect(await db.unsentCount('u2'), 1);
  });
}
