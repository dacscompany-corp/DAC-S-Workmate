import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import 'package:workmate/purchasing/data/purchasing_api.dart';
import 'package:workmate/purchasing/data/purchasing_db.dart';
import 'package:workmate/purchasing/data/purchasing_repository.dart';
import 'package:workmate/purchasing/domain/pur_failure.dart';
import 'package:workmate/purchasing/domain/pur_models.dart';
import 'package:workmate/purchasing/domain/purchase_draft.dart';
import 'package:workmate/purchasing/sync/purchasing_sync.dart';

import '../../attendance/fakes.dart';
import '../domain/purchase_draft_test.dart' show linked, unplanned;
import '../purchasing_fakes.dart';

void main() {
  late PurchasingDb db;
  late FakePurchasingRemote remote;
  late Directory dir;
  late PurchasingRepository repo;
  var user = 'u1';
  String? company = 'o1';
  var ids = 0;
  var kicks = 0;
  var turnedOff = 0;

  setUpAll(sqfliteFfiInit);
  setUp(() async {
    db = await PurchasingDb.open(databaseFactoryFfi, inMemoryDatabasePath, singleInstance: false);
    remote = FakePurchasingRemote();
    dir = await Directory.systemTemp.createTemp('pur-repo');
    user = 'u1';
    company = 'o1';
    ids = 0;
    kicks = 0;
    turnedOff = 0;
    repo = PurchasingRepository(
      db: db,
      remote: remote,
      device: FakeDevice(),
      scheduler: FakeScheduler(),
      currentUserId: () => user,
      companyOf: (_) => company,
      photoDir: () async => dir,
      sendNow: () async => kicks++,
      onBuyingOff: () async => turnedOff++,
      now: () => wednesday,
      newId: () => 'id${++ids}',
    );
  });
  tearDown(() async {
    await db.close();
    await dir.delete(recursive: true);
  });

  Future<String> photo(String name) async {
    final f = File('${dir.path}/$name');
    await f.writeAsBytes([1, 2, 3]);
    return f.path;
  }

  Future<PurchaseDraft> ready() async =>
      repo.newDraft(lines: [unplanned()]).copyWith(receiptTotal: '500', photos: {'supplier_invoice_url': await photo('r.jpg')});

  group('the shopping list', () {
    test('is saved, and served from the saved copy with no signal', () async {
      final fresh = await repo.shoppingList();
      expect(fresh.fromCache, isFalse);
      expect(fresh.lines.single.description, 'Cement');
      expect(fresh.batches.map((b) => b.id), ['b1', 'b2']);
      remote.readError = const SocketException('down');
      final cached = await repo.shoppingList();
      expect(cached.fromCache, isTrue);
      expect(cached.lines.single.lineId, 'l1');
      expect(cached.error, isA<SocketException>());
    });

    test('with no signal and nothing saved: an empty list that says why', () async {
      remote.readError = const SocketException('down');
      final v = await repo.shoppingList();
      expect(v.lines, isEmpty);
      expect(v.error, isNotNull);
    });

    test('BUYER_REQUIRED wipes the saved copy and tells the app (R2)', () async {
      await repo.shoppingList();
      remote.readError = refusal('BUYER_REQUIRED');
      await expectLater(repo.shoppingList(), throwsA(isA<Object>()));
      expect(turnedOff, 1);
      expect(await db.cache('u1', 'shopping'), isNull);
    });
  });

  group('claim, release, Mark arranged (online, Q5 Q6)', () {
    test('claim all, or part; release mine', () async {
      await repo.claim(portion('p1'));
      await repo.claim(portion('p1'), quantity: 4);
      await repo.release(portion('p1', buyer: 'u1', mine: true));
      expect(remote.calls, ['assign:p1:u1:null', 'assign:p1:u1:4.0', 'assign:p1:null:null']);
    });

    test('Mark arranged only on my own portions (Q6)', () async {
      await repo.setArranged(portion('p1', buyer: 'u1', mine: true), true);
      expect(remote.calls, ['arranged:p1:true']);
      expect(() => repo.setArranged(portion('p2', buyer: 'u9'), true),
          throwsA(isA<PurFailureException>().having((e) => e.failure, 'failure', PurFailure.notYourPortion)));
    });

    test('a refusal reaches the screen', () async {
      remote.writeError = refusal('ASSIGNED_TO_OTHER');
      expect(() => repo.claim(portion('p1')), throwsA(predicate((e) => PurFailure.of(e!) == PurFailure.assignedToOther)));
    });

    test('nobody signed in: nothing is sent', () async {
      user = '';
      expect(() => repo.claim(portion('p1')), throwsA(isA<StateError>()));
      expect(remote.calls, isEmpty);
    });
  });

  group('recording', () {
    test('a new purchase is dated in Manila, never by the phone\'s UTC date', () {
      final late = PurchasingRepository(
        db: db,
        remote: remote,
        device: FakeDevice(),
        scheduler: FakeScheduler(),
        currentUserId: () => user,
        companyOf: (_) => company,
        photoDir: () async => dir,
        now: () => DateTime.utc(2026, 10, 21, 17),
      );
      expect(late.newDraft().purchaseDate, '2026-10-22');
    });

    test('a draft with problems is not queued', () async {
      final d = repo.newDraft(lines: [unplanned()]);
      await expectLater(repo.send(d), throwsA(isA<PurchaseInvalid>()));
      expect(await db.sendable('u1'), isEmpty);
    });

    test('Send queues once and starts sending; a double tap queues nothing more', () async {
      final d = await ready();
      await repo.send(d);
      await repo.send(d);
      expect((await db.sendable('u1')).length, 1);
      expect(kicks, 1);
      final op = (await db.sendable('u1')).single;
      expect(op.companyId, 'o1');
      expect(op.receipts.keys, ['supplier_invoice_url']);
      expect(op.purchase['source'], 'workmate');
    });

    test('"No receipt" sends no photo', () async {
      final d = (await ready()).copyWith(noReceipt: true, noReceiptReason: 'Store gave none');
      await repo.send(d);
      expect((await db.sendable('u1')).single.receipts, isEmpty);
    });

    test('deleting a draft deletes its photos', () async {
      final d = await ready();
      await repo.saveDraft(d);
      await repo.deleteDraft(d);
      expect(File(d.photos.values.single).existsSync(), isFalse);
      expect(await repo.drafts(), isEmpty);
    });
  });

  group('My purchases (Q12)', () {
    test('what is still on the phone, then the server\'s list (saved for offline)', () async {
      remote.mine = [
        {'id': 'pu1', 'status': 'recorded', 'receipt_total': 500, 'projects': ['Barlin Residence']},
      ];
      await repo.send(await ready());
      final v = await repo.myPurchases();
      expect(v.queued.single.state, QueuedState.waiting);
      expect(v.purchases.single.id, 'pu1');
      remote.readError = const SocketException('down');
      final offline = await repo.myPurchases();
      expect(offline.fromCache, isTrue);
      expect(offline.purchases.single.id, 'pu1');
    });

    test('a refused purchase shows why and can go back to editing (Q7)', () async {
      await repo.send(await ready());
      remote.writeError = refusal('LINE_CLOSED');
      await PurchasingSync(db: db, remote: remote, now: () => wednesday).drain('u1');
      final v = await repo.myPurchases();
      expect(v.queued.single.state, QueuedState.needsAttention);
      expect(v.queued.single.failure, PurFailure.lineClosed);
      expect(await repo.returnToDrafts(v.queued.single.draft.id), isTrue);
      expect((await repo.drafts()).single.id, v.queued.single.draft.id);
    });

    test('a refused purchase thrown away takes its photos', () async {
      final d = await ready();
      await repo.send(d);
      remote.writeError = refusal('LINE_CLOSED');
      await PurchasingSync(db: db, remote: remote, now: () => wednesday).drain('u1');
      await repo.discardRefused(d.id);
      expect((await repo.myPurchases()).queued, isEmpty);
      expect(File(d.photos.values.single).existsSync(), isFalse);
    });
  });

  group('corrections (Q13)', () {
    final p = PurchaseDetail.fromJson(const {'id': 'pu1', 'status': 'recorded'});

    test('new photos are uploaded first, then the correction goes with their links', () async {
      final r = await repo.correct(p, {'lines': []}, 'Wrong price', opId: 'op1', newPhotos: {'payment_receipt_url': await photo('n.jpg')});
      expect(r.outcome, CorrectionOutcome.saved);
      expect(remote.uploads.single, startsWith('purchases/o1/2026-10/'));
      expect(remote.calls.last, 'correct:op1:pu1:Wrong price');
      expect((r.body['docs'] as Map).keys, ['payment_receipt_url']);
    });

    test('only the owner may: nothing changes, and the same body can go to the owner', () async {
      remote.writeError = refusal('COMPLETED_PROJECT');
      final r = await repo.correct(p, {'lines': []}, 'Wrong price', opId: 'op1');
      expect(r.outcome, CorrectionOutcome.needsOwner);
      await repo.sendToOwner(p, r.body, 'Wrong price', opId: 'op2');
      expect(remote.calls.last, 'owner:op2:pu1:Wrong price');
    });

    test('the company is asked once when this phone does not know it', () async {
      company = null;
      await repo.correct(p, {'lines': []}, 'x', opId: 'op1', newPhotos: {'po_image_url': await photo('n.jpg')});
      expect(remote.calls, contains('company'));
    });
  });

  test('a receipt is read once per session', () async {
    await repo.receipt('https://x/a.jpg');
    await repo.receipt('https://x/a.jpg');
    expect(remote.calls.where((c) => c.startsWith('receipt:')).length, 1);
  });

  test('a linked line keeps its request through Send', () async {
    final d = repo.newDraft(lines: [linked()]).copyWith(receiptTotal: '500', photos: {'po_image_url': await photo('r.jpg')});
    await repo.send(d);
    final line = ((await db.sendable('u1')).single.purchase['lines'] as List).single as Map;
    expect(line['request_line_id'], 'l1');
  });
}
