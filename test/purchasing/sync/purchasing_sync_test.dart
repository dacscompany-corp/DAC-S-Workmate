import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import 'package:workmate/attendance/sync/submission_sync.dart' show SyncResult;
import 'package:workmate/purchasing/data/purchasing_db.dart';
import 'package:workmate/purchasing/domain/pur_failure.dart';
import 'package:workmate/purchasing/domain/pur_op.dart';
import 'package:workmate/purchasing/domain/purchase_draft.dart';
import 'package:workmate/purchasing/sync/purchasing_sync.dart';

import '../purchasing_fakes.dart';

void main() {
  late PurchasingDb db;
  late FakePurchasingRemote remote;
  late PurchasingSync sync;
  late Directory dir;

  setUpAll(sqfliteFfiInit);
  setUp(() async {
    db = await PurchasingDb.open(databaseFactoryFfi, inMemoryDatabasePath, singleInstance: false);
    remote = FakePurchasingRemote();
    sync = PurchasingSync(db: db, remote: remote, now: () => wednesday);
    dir = await Directory.systemTemp.createTemp('pur-sync');
  });
  tearDown(() async {
    await db.close();
    await dir.delete(recursive: true);
  });

  Future<String> queue({String user = 'u1', String opId = 'op1', String? company = 'o1', bool photo = true}) async {
    final f = File('${dir.path}/$opId.jpg')..writeAsBytesSync([1]);
    final draft = PurchaseDraft(id: 'd-$opId', createdAt: wednesday, purchaseDate: '2026-10-21');
    await db.queueDraft(
      user,
      draft,
      PurOp(
        opId: opId,
        userId: user,
        createdAt: wednesday,
        draftId: draft.id,
        purchase: const {'source': 'workmate', 'lines': []},
        companyId: company,
        receipts: {if (photo) 'supplier_invoice_url': ReceiptUpload(local: f.path, photoId: 'ph-$opId')},
      ),
      wednesday,
    );
    return f.path;
  }

  test('receipts first, then the purchase with their links, recorded once with the Send op id', () async {
    final local = await queue();
    expect(await sync.drain('u1'), SyncResult.done);
    expect(remote.uploads, ['purchases/o1/2026-10/ph-op1.jpg']);
    expect(remote.recordOps, ['op1']);
    expect(remote.recorded.single['docs'], {'supplier_invoice_url': 'https://x.supabase.co/storage/v1/object/public/uploads/purchases/o1/2026-10/ph-op1.jpg'});
    expect(await db.ops('u1'), isEmpty);
    expect(await db.unsentCount('u1'), 0);
    expect(File(local).existsSync(), isFalse, reason: 'the photo goes only once recorded');
    expect(sync.settled, 1);
  });

  test('no signal while recording: the uploaded receipt is not uploaded again, and the same op id retries', () async {
    final local = await queue();
    remote.writeError = const SocketException('down');
    expect(await sync.drain('u1'), SyncResult.retry);
    expect(remote.uploads.length, 1);
    expect(File(local).existsSync(), isTrue);
    expect(await sync.drain('u1'), SyncResult.done);
    expect(remote.uploads.length, 1);
    expect(remote.calls.where((c) => c == 'record:op1').length, 2);
    expect(remote.recordOps, ['op1']);
  });

  test('no signal while uploading: the path stays fixed for the retry', () async {
    await queue();
    remote.uploadError = const SocketException('down');
    expect(await sync.drain('u1'), SyncResult.retry);
    final kept = (await db.sendable('u1')).single.receipts['supplier_invoice_url']!;
    expect(kept.path, 'purchases/o1/2026-10/ph-op1.jpg');
    expect(kept.url, isNull);
    expect(await sync.drain('u1'), SyncResult.done);
    expect(remote.uploads, ['purchases/o1/2026-10/ph-op1.jpg']);
  });

  test('a company this phone did not know is asked once, then kept', () async {
    await queue(company: null);
    remote.writeError = const SocketException('down');
    await sync.drain('u1');
    expect((await db.sendable('u1')).single.companyId, 'o1');
    await sync.drain('u1');
    expect(remote.calls.where((c) => c == 'company').length, 1);
  });

  test('refused: kept and flagged, never retried, and the queue moves on (Q7)', () async {
    await queue(opId: 'op1');
    await queue(opId: 'op2');
    remote.writeError = refusal('LINE_CLOSED');
    expect(await sync.drain('u1'), SyncResult.done);
    final ops = await db.ops('u1');
    expect(ops.firstWhere((o) => o.opId == 'op1').failedPermanently, isTrue);
    expect(ops.firstWhere((o) => o.opId == 'op1').lastError, 'lineClosed');
    expect(remote.recordOps, ['op2']);
  });

  test('buying turned off: kept as Needs attention, sendable again once returned to editing (R2)', () async {
    await queue();
    remote.writeError = refusal('BUYER_REQUIRED');
    await sync.drain('u1');
    final op = (await db.ops('u1')).single;
    expect(op.failedPermanently, isTrue);
    expect(PurFailure.fromStored(op.lastError), PurFailure.buyingOff);
  });

  test('a receipt photo no longer on the phone: Needs attention, nothing recorded', () async {
    final local = await queue();
    File(local).deleteSync();
    await sync.drain('u1');
    expect((await db.ops('u1')).single.lastError, 'photoMissing');
    expect(remote.recordOps, isEmpty);
  });

  test('an unexpected failure ten times in a row stops being retried', () async {
    await queue();
    remote
      ..writeError = Exception('weird')
      ..writeErrorSticky = true;
    for (var i = 0; i < maxPurchaseAttempts - 1; i++) {
      expect(await sync.drain('u1'), SyncResult.retry);
    }
    expect(await sync.drain('u1'), SyncResult.done);
    expect((await db.ops('u1')).single.failedPermanently, isTrue);
  });

  test('only the signed-in account\'s purchases are sent; nobody, nothing', () async {
    await queue(user: 'u2');
    expect(await sync.drain(''), SyncResult.done);
    expect(await sync.drain('u1'), SyncResult.done);
    expect(remote.recordOps, isEmpty);
    await sync.drain('u2');
    expect(remote.recordOps, ['op1']);
  });
}
