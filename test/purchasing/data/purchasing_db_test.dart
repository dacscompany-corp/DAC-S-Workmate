import 'dart:io';

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

  test('R38: sent — never sent again and no longer waiting, but kept with its draft until forgotten', () async {
    await db.queueDraft('u1', d('d1'), op('o1', 'd1'), now);
    await db.markSent('o1', 'd1', now);
    expect([await db.ops('u1'), await db.sendable('u1'), await db.drafts('u1', queued: true)], [isEmpty, isEmpty, isEmpty]);
    expect([await db.hasAnySendable(), await db.unsentCount('u1')], [false, 0]);
    expect([for (final o in await db.sentOps('u1')) '${o.opId} ${o.sent}'], ['o1 true']);
    expect((await db.sentDrafts('u1')).map((x) => x.id), ['d1']);
    // Never back to editing, thrown away, rewritten or queued again.
    expect(await db.unqueueDraft('u1', 'd1'), isFalse);
    expect(await db.discardRefused('u1', 'd1'), isNull);
    await db.saveDraft('u1', d('d1'), now);
    expect(await db.drafts('u1', queued: false), isEmpty);
    expect(await db.queueDraft('u1', d('d1'), op('o9', 'd1'), now), isFalse);
    await db.forgetSent('u2', ['o1']);
    expect(await db.sentOps('u1'), hasLength(1), reason: 'only its own account forgets it');
    await db.forgetSent('u1', ['o1']);
    expect([await db.sentOps('u1'), await db.sentDrafts('u1')], [isEmpty, isEmpty]);
  });

  test('R38: forgetting never touches an op not sent yet', () async {
    await db.queueDraft('u1', d('d1'), op('o1', 'd1'), now);
    await db.forgetSent('u1', ['o1']);
    expect((await db.sendable('u1')).single.opId, 'o1');
    expect((await db.drafts('u1', queued: true)).single.id, 'd1');
  });

  test('R38: a saved copy keeps which sent ops it counts', () async {
    await db.putCache('u1', 'my_cash', const {'held': 1}, now, covers: ['o1', 'o2']);
    expect((await db.cache('u1', 'my_cash'))!.covers, {'o1', 'o2'});
    await db.putCache('u1', 'my_cash', const {'held': 2}, now);
    expect((await db.cache('u1', 'my_cash'))!.covers, isEmpty);
  });

  test('a 0.7.1 database (version 1) is upgraded in place: its queue and saved copies kept', () async {
    final dir = await Directory.systemTemp.createTemp('pur-db-v1');
    final path = '${dir.path}/p.db';
    final v1 = await databaseFactoryFfi.openDatabase(path,
        options: OpenDatabaseOptions(
          version: 1,
          onCreate: (x, _) async {
            await x.execute('create table pur_draft (id text primary key, user_id text not null, body text not null, '
                'queued integer not null default 0, created_at integer not null, updated_at integer not null)');
            await x.execute('create table pur_op (op_id text primary key, user_id text not null, kind text not null, draft_id text, '
                'body text not null, seq integer not null, attempts integer not null default 0, last_error text, '
                'failed_permanently integer not null default 0, created_at integer not null)');
            await x.execute('create table pur_cache (user_id text not null, name text not null, body text not null, '
                'fetched_at integer not null, primary key (user_id, name))');
          },
        ));
    await v1.insert('pur_op', {...op('o1', 'd1').toMap(), 'seq': 1});
    await v1.insert('pur_cache', {'user_id': 'u1', 'name': 'my_purchases', 'body': '[]', 'fetched_at': 0});
    await v1.close();
    final up = await PurchasingDb.open(databaseFactoryFfi, path, singleInstance: false);
    expect((await up.sendable('u1')).single.opId, 'o1');
    expect((await up.cache('u1', 'my_purchases'))!.covers, isEmpty);
    await up.markSent('o1', 'd1', now);
    expect((await up.sentOps('u1')).single.sent, isTrue);
    await up.close();
    await dir.delete(recursive: true);
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
