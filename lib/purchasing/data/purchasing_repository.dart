import 'dart:async';
import 'dart:io';
import 'dart:typed_data';

import '../../attendance/device/device_bridge.dart';
import '../../attendance/domain/event_id.dart';
import '../../attendance/domain/work_date.dart';
import '../../attendance/sync/upload_scheduler.dart';
import '../domain/pay_models.dart';
import '../domain/pur_failure.dart';
import '../domain/pur_models.dart';
import '../domain/pur_op.dart';
import '../domain/purchase_draft.dart';
import 'purchasing_api.dart';
import 'purchasing_db.dart';
import 'purchasing_remote.dart';

/// Offline-first buying (Q7). Recording happens on the phone first and is
/// sent once, whenever there is signal, from the app or the background task.
/// Claiming, releasing, Mark arranged and corrections need signal (Q5, Q6).
/// Paying (0102): a later payment and a return of petty cash are queued the
/// same way (Q6); voiding a payment, withdrawing a return and "I did not
/// receive this" need signal.
class PurchasingRepository implements PurchasingApi {
  PurchasingRepository({
    required this.db,
    required this.remote,
    required this.device,
    required this.scheduler,
    required this.currentUserId,
    required this.companyOf,
    required this.photoDir,
    this.sendNow,
    this.onBuyingOff,
    DateTime Function()? now,
    String Function()? newId,
  })  : _now = now ?? DateTime.now,
        _newId = newId ?? newEventId;

  final PurchasingDb db;
  final PurchasingRemote remote;
  final DeviceBridge device;

  /// The same WorkManager work as attendance: one background drain sends all.
  final UploadScheduler scheduler;

  /// The buyer the app let in, or ''.
  final String Function() currentUserId;

  /// The company the buyer files under, as last read (BuyerAccess); null
  /// until known — the first send then asks the server.
  final String? Function(String userId) companyOf;

  /// App-private folder for receipt photos (never the gallery).
  final Future<Directory> Function() photoDir;

  /// Drains the queue now in the live app (main.dart); null in tests.
  final Future<void> Function()? sendNow;

  /// The server said BUYER_REQUIRED (R2): the app shows Buying is turned off.
  final Future<void> Function()? onBuyingOff;
  final DateTime Function() _now;
  final String Function() _newId;

  /// Receipts read this session, by link. Kept in memory only.
  final _receipts = <String, Uint8List>{};

  @override
  String get me => currentUserId();

  String _user() {
    final u = currentUserId();
    if (u.isEmpty) throw StateError('AUTH_REQUIRED');
    return u;
  }

  /// R2: wipe the saved copy (shopping list, purchases, receipts) and tell
  /// the app. Unsent purchases stay.
  Future<void> _turnedOff() async {
    _receipts.clear();
    await db.keepCacheOnly('');
    final hook = onBuyingOff;
    if (hook != null) await hook();
  }

  /// Runs a server call; a BUYER_REQUIRED answer wipes and tells the app first.
  Future<T> _guard<T>(Future<T> Function() call) async {
    try {
      return await call();
    } catch (e) {
      if (PurFailure.of(e) == PurFailure.buyingOff) await _turnedOff();
      rethrow;
    }
  }

  Future<void> _kick() async {
    try {
      await scheduler.enqueue('purchasing');
    } catch (_) {
      // Queued on disk; the periodic sweeper is the backstop.
    }
    final now = sendNow;
    if (now != null) unawaited(Future.sync(now).catchError((Object _) {}));
  }

  List<Map<String, dynamic>> _rows(Object? body) => [for (final r in body as List<dynamic>) Map<String, dynamic>.from(r as Map)];

  // ── the shopping list ──────────────────────────────────────────────────

  @override
  Future<ShoppingView> shoppingList() async {
    final u = _user();
    try {
      final (batches, lines) = await _guard(() async => (await remote.batches(), await remote.shoppingList()));
      final at = _now();
      await db.putCache(u, 'batches', [for (final b in batches) b.toJson()], at);
      await db.putCache(u, 'shopping', [for (final l in lines) l.toJson()], at);
      return ShoppingView(lines: lines, batches: batches, fetchedAt: at);
    } catch (e) {
      if (PurFailure.of(e) == PurFailure.buyingOff) rethrow;
      final b = await db.cache(u, 'batches');
      final l = await db.cache(u, 'shopping');
      if (b == null || l == null) return ShoppingView(error: e);
      return ShoppingView(
        batches: _rows(b.body).map(PurBatch.fromJson).toList(),
        lines: _rows(l.body).map(ShoppingLine.fromJson).toList(),
        fetchedAt: l.at,
        fromCache: true,
        error: e,
      );
    }
  }

  @override
  Future<void> claim(PurPortion portion, {double? quantity}) async {
    final u = _user();
    await _guard(() => remote.assign(portion.id, u, quantity, userId: u));
  }

  @override
  Future<void> release(PurPortion portion) async {
    final u = _user();
    await _guard(() => remote.assign(portion.id, null, null, userId: u));
  }

  @override
  Future<void> setArranged(PurPortion portion, bool arranged) async {
    final u = _user();
    // Q6: on the phone, a buyer marks only their own portions.
    if (!portion.mine) throw const PurFailureException(PurFailure.notYourPortion);
    await _guard(() => remote.setArranged(portion.id, arranged, userId: u));
  }

  // ── choices ────────────────────────────────────────────────────────────

  @override
  Future<PurchaseChoices> choices() async {
    final u = _user();
    try {
      final (destinations, suppliers) = await _guard(() async => (await remote.destinations(), await remote.suppliers()));
      final at = _now();
      await db.putCache(u, 'destinations', [for (final d in destinations) d.toJson()], at);
      await db.putCache(u, 'suppliers', [for (final s in suppliers) s.toJson()], at);
      return PurchaseChoices(destinations: destinations, suppliers: suppliers);
    } catch (e) {
      if (PurFailure.of(e) == PurFailure.buyingOff) rethrow;
      final d = await db.cache(u, 'destinations');
      final s = await db.cache(u, 'suppliers');
      if (d == null || s == null) rethrow;
      return PurchaseChoices(
        destinations: _rows(d.body).map(PurDestination.fromJson).toList(),
        suppliers: _rows(s.body).map(Supplier.fromJson).toList(),
        fromCache: true,
      );
    }
  }

  // ── drafts ─────────────────────────────────────────────────────────────

  @override
  PurchaseDraft newDraft({List<DraftPurchaseLine> lines = const []}) {
    final at = _now();
    // The Manila date, never the phone's UTC date (PH is UTC+8).
    return PurchaseDraft(id: _newId(), createdAt: at.toUtc(), purchaseDate: isoDate(manilaDate(at)), lines: lines);
  }

  @override
  String newLineKey() => _newId();

  @override
  Future<List<PurchaseDraft>> drafts() async => db.drafts(_user(), queued: false);

  @override
  Future<void> saveDraft(PurchaseDraft draft) async => db.saveDraft(_user(), draft, _now());

  @override
  Future<void> deleteDraft(PurchaseDraft draft) async {
    final stored = await db.deleteUnsentDraft(_user(), draft.id);
    // A queued draft's photos are still owed to the server: never touch them.
    for (final p in stored?.photos.values ?? const <String>[]) {
      await discardPhoto(p);
    }
  }

  @override
  Future<String> keepPhoto(String draftId, String sourcePath) async {
    final dir = Directory('${(await photoDir()).path}${Platform.pathSeparator}$draftId');
    await dir.create(recursive: true);
    // No caption: a receipt must stay readable.
    return device.preparePhoto(source: sourcePath, target: '${dir.path}${Platform.pathSeparator}${_newId()}.jpg', caption: '');
  }

  @override
  Future<void> discardPhoto(String path) async {
    try {
      await File(path).delete();
    } catch (_) {
      // Already gone.
    }
  }

  @override
  Future<void> send(PurchaseDraft draft) async {
    final u = _user();
    // "Paid now?" (0102, Q3): petty cash and own money need a staff buyer
    // (unknown before the first read: the server decides); a credit, what it has left.
    final cash = await db.cache(u, 'my_cash');
    final holder = cash == null || (cash.body as Map)['holder'] == true;
    final left = draft.paidFrom == 'credit' ? await _creditLeft(u, draft.paidCredit) : null;
    final problems = [...purchaseProblems(draft), ...paidNowProblems(draft, holder: holder, creditLeft: left)];
    if (problems.isNotEmpty) throw PurchaseInvalid(problems);
    final op = PurOp(
      opId: _newId(),
      userId: u,
      createdAt: _now().toUtc(),
      draftId: draft.id,
      purchase: purchaseBody(draft),
      companyId: companyOf(u),
      receipts: {
        if (!draft.noReceipt)
          for (final e in draft.photos.entries) e.key: ReceiptUpload(local: e.value, photoId: _newId()),
      },
    );
    // A second Send of the same draft (a double tap) queues nothing.
    if (await db.queueDraft(u, draft, op, _now())) await _kick();
  }

  // ── my purchases ───────────────────────────────────────────────────────

  @override
  Future<MyPurchasesView> myPurchases() async {
    final u = _user();
    List<Map<String, dynamic>>? docs;
    Object? error;
    DateTime? fetchedAt;
    var fromCache = false;
    var counted = <String>{};
    try {
      final (fresh, covers) = await _guard(() => _fresh(u, remote.myPurchases));
      docs = fresh;
      counted = covers;
      fetchedAt = _now();
      await db.putCache(u, 'my_purchases', fresh, fetchedAt, covers: covers);
      await _forgetCounted(u);
    } catch (e) {
      if (PurFailure.of(e) == PurFailure.buyingOff) rethrow;
      error = e;
      final cached = await db.cache(u, 'my_purchases');
      if (cached != null) {
        docs = _rows(cached.body);
        fetchedAt = cached.at;
        fromCache = true;
        counted = cached.covers;
      }
    }
    final allOps = await _notCounted(u, counted);
    final ops = {for (final o in allOps) if (o.draftId != null) o.draftId: o};
    final drafts = [...await db.drafts(u, queued: true), ...await db.sentDrafts(u)]..sort((a, b) => b.createdAt.compareTo(a.createdAt));
    final queued = [
      for (final d in drafts)
        if (ops[d.id] case final op?)
          QueuedPurchase(draft: d, state: _state(op), failure: op.failedPermanently ? PurFailure.fromStored(op.lastError) : null),
    ];
    return MyPurchasesView(
      queued: queued,
      queuedPayments: [for (final a in _cashActions(allOps)) if (a.isPayment) a],
      purchases: [for (final d in docs ?? const <Map<String, dynamic>>[]) MyPurchase.fromJson(d)],
      fetchedAt: fetchedAt,
      fromCache: fromCache,
      error: (docs == null || fromCache) ? error : null,
    );
  }

  @override
  Future<bool> returnToDrafts(String draftId) => db.unqueueDraft(_user(), draftId);

  @override
  Future<void> discardRefused(String draftId) async {
    final stored = await db.discardRefused(_user(), draftId);
    for (final p in stored?.photos.values ?? const <String>[]) {
      await discardPhoto(p);
    }
  }

  @override
  Future<PurchaseDetail> purchase(String id) async {
    _user();
    return PurchaseDetail.fromJson(await _guard(() => remote.purchase(id)));
  }

  /// New receipt photos of a correction, uploaded now (corrections are online).
  Future<Map<String, String>> _upload(String u, Map<String, String> photos) async {
    if (photos.isEmpty) return const {};
    final company = companyOf(u) ?? await remote.company(u);
    final out = <String, String>{};
    for (final e in photos.entries) {
      final path = receiptPath(companyId: company, manilaNow: manilaFields(_now()), photoId: _newId());
      out[e.key] = await remote.uploadReceipt(path: path, localPath: e.value, companyId: company, userId: u);
    }
    return out;
  }

  @override
  Future<CorrectionResult> correct(PurchaseDetail purchase, Map<String, dynamic> body, String reason,
      {required String opId, Map<String, String> newPhotos = const {}}) async {
    final u = _user();
    final docs = await _guard(() => _upload(u, newPhotos));
    final sent = {...body, 'docs': {...?(body['docs'] as Map<String, dynamic>?), ...docs}};
    try {
      await _guard(() => remote.correct(opId, purchase.id, sent, reason, userId: u));
    } catch (e) {
      final f = PurFailure.of(e);
      if (f == PurFailure.ownerApprovalNeeded || f == PurFailure.completedProject) {
        return CorrectionResult(CorrectionOutcome.needsOwner, sent);
      }
      rethrow;
    }
    for (final p in newPhotos.values) {
      await discardPhoto(p);
    }
    return CorrectionResult(CorrectionOutcome.saved, sent);
  }

  @override
  Future<void> sendToOwner(PurchaseDetail purchase, Map<String, dynamic> body, String reason, {required String opId}) async {
    final u = _user();
    await _guard(() => remote.requestChange(opId, purchase.id, body, reason, userId: u));
  }

  // ── paying, petty cash, own money (0102, 0103) ─────────────────────────

  @override
  String today() => isoDate(manilaDate(_now()));

  List<QueuedCashAction> _cashActions(List<PurOp> ops) => [
        for (final o in ops)
          if (o.draftId == null && (o.kind == opPay || o.kind == opCashReturn))
            QueuedCashAction(
              opId: o.opId,
              kind: o.kind,
              body: o.purchase,
              state: _state(o),
              failure: o.failedPermanently ? PurFailure.fromStored(o.lastError) : null,
            ),
      ];

  QueuedState _state(PurOp o) => o.failedPermanently
      ? QueuedState.needsAttention
      : o.sent
          ? QueuedState.sent
          : QueuedState.waiting;

  /// R38: what a list read with [counted] does not count — every op not sent
  /// yet (refused ones included, shown but never counted), and every sent op
  /// outside [counted]. In queue order.
  Future<List<PurOp>> _notCounted(String u, Set<String> counted) async =>
      [...await db.ops(u), for (final o in await db.sentOps(u)) if (!counted.contains(o.opId)) o]..sort((a, b) => a.seq.compareTo(b.seq));

  /// Petty cash in payments the balance shown does not count (purchases paid
  /// now from petty cash, later petty-cash payments); refused ones are not counted.
  double _unsentPetty(List<PurOp> ops) {
    var sum = 0.0;
    for (final o in ops.where((o) => !o.failedPermanently)) {
      final payments = switch (o.kind) {
        opPay => [o.purchase['payment']],
        opRecord => (o.purchase['payments'] as List<dynamic>?) ?? const [],
        _ => const [],
      };
      for (final p in payments.whereType<Map<dynamic, dynamic>>()) {
        if (p['source'] == 'petty_cash') sum = round2(sum + (parseMoney('${p['amount']}') ?? 0));
      }
    }
    return sum;
  }

  /// R38: an operation the server accepted but whose answer never came back
  /// is still queued here. Ask the server which queued ops it already has and
  /// mark them sent, as the sync would (never sent again, photos deleted).
  /// Throws with no signal.
  Future<void> _reconcile(String u) async {
    final live = [for (final o in await db.ops(u)) if (!o.failedPermanently) o];
    for (var i = 0; i < live.length; i += 200) {
      final chunk = live.sublist(i, i + 200 > live.length ? live.length : i + 200);
      final done = (await remote.opsDone([for (final o in chunk) o.opId])).toSet();
      for (final o in chunk.where((o) => done.contains(o.opId))) {
        await db.markSent(o.opId, o.draftId, _now());
        for (final r in o.receipts.values) {
          await discardPhoto(r.local);
        }
      }
    }
  }

  /// R38: one fresh read, and exactly which sent ops it already counts.
  /// Ops the server has are marked sent first; those sent before the read
  /// began are in it. An op that went during the read (sent by the
  /// background send, or found by the check after it) may or may not be in
  /// it, so the read is done again — it is sent before that one begins. Not
  /// settled after three reads, or no signal for the check after it: the
  /// read is not used, and the saved copy is shown (exact, as it says what
  /// it counts).
  Future<(T, Set<String>)> _fresh<T>(String u, Future<T> Function() read) async {
    for (var round = 0; round < 3; round++) {
      await _reconcile(u);
      final before = await _queueState(u);
      final value = await read();
      await _reconcile(u);
      final after = await _queueState(u);
      final wentDuring = {...after.sent.difference(before.sent), ...before.waiting.difference(after.waiting).difference(after.refused)};
      if (wentDuring.isEmpty) return (value, before.sent);
    }
    throw const PurFailureException(PurFailure.noConnection);
  }

  Future<({Set<String> waiting, Set<String> refused, Set<String> sent})> _queueState(String u) async {
    final ops = await db.ops(u);
    return (
      waiting: {for (final o in ops) if (!o.failedPermanently) o.opId},
      refused: {for (final o in ops) if (o.failedPermanently) o.opId},
      sent: {for (final o in await db.sentOps(u)) o.opId},
    );
  }

  /// A sent op is forgotten once every saved copy that shows it (My purchases,
  /// My cash) counts it; until then a copy read before it went still shows it.
  Future<void> _forgetCounted(String u) async {
    final copies = [await db.cache(u, 'my_purchases'), await db.cache(u, 'my_cash')];
    await db.forgetSent(u, [
      for (final o in await db.sentOps(u))
        if (copies.every((c) => c == null || c.covers.contains(o.opId))) o.opId,
    ]);
  }

  /// What a credit had left when last read on this phone, or null.
  Future<double?> _creditLeft(String u, String? creditId) async {
    final saved = await db.cache(u, 'credits');
    if (saved == null || creditId == null) return null;
    for (final c in _rows(saved.body).map(SupplierCredit.fromJson)) {
      if (c.id == creditId) return c.left;
    }
    return null;
  }

  @override
  Future<MyCashView> myCash() async {
    final u = _user();
    MyCash? cash;
    var credits = const <SupplierCredit>[];
    Object? error;
    DateTime? at;
    var fromCache = false;
    var counted = <String>{};
    try {
      final ((mine, creditRows), covers) = await _guard(() => _fresh(u, () async => (await remote.myCash(), await remote.credits())));
      at = _now();
      counted = covers;
      await db.putCache(u, 'my_cash', mine, at, covers: covers);
      await db.putCache(u, 'credits', creditRows, at, covers: covers);
      await _forgetCounted(u);
      cash = MyCash.fromJson(mine);
      credits = creditRows.map(SupplierCredit.fromJson).toList();
    } catch (e) {
      if (PurFailure.of(e) == PurFailure.buyingOff) rethrow;
      error = e;
      final saved = await db.cache(u, 'my_cash');
      if (saved != null) {
        cash = MyCash.fromJson(Map<String, dynamic>.from(saved.body as Map));
        at = saved.at;
        fromCache = true;
        counted = saved.covers;
      }
      final savedCredits = await db.cache(u, 'credits');
      if (savedCredits != null) credits = _rows(savedCredits.body).map(SupplierCredit.fromJson).toList();
    }
    final ops = await _notCounted(u, counted);
    return MyCashView(
      cash: cash,
      credits: credits,
      queued: _cashActions(ops),
      unsentPettyCash: _unsentPetty(ops),
      fetchedAt: at,
      fromCache: fromCache,
      error: (cash == null || fromCache) ? error : null,
    );
  }

  @override
  Future<PurchasePaymentsView> purchasePayments(String purchaseId) async {
    final u = _user();
    final (json, covers) = await _guard(() => _fresh(u, () => remote.purchasePayments(purchaseId)));
    return PurchasePaymentsView(
      pay: PurchasePayments.fromJson(json),
      queued: [for (final a in _cashActions(await _notCounted(u, covers))) if (a.purchaseId == purchaseId) a],
    );
  }

  @override
  Future<List<QueuedCashAction>> queuedPayments(String purchaseId) async {
    final u = _user();
    final saved = await db.cache(u, 'my_purchases');
    return [for (final a in _cashActions(await _notCounted(u, saved?.covers ?? const {}))) if (a.purchaseId == purchaseId) a];
  }

  @override
  Future<void> pay(String purchaseId, PaymentInput payment, {String? proofPhoto}) async {
    final u = _user();
    final left = payment.source == 'credit' ? await _creditLeft(u, payment.creditId) : null;
    final problems = paymentProblems(payment, today: today(), creditLeft: left);
    if (problems.isNotEmpty) throw PaymentInvalid(problems);
    await db.queueOp(PurOp(
      opId: _newId(),
      userId: u,
      kind: opPay,
      createdAt: _now().toUtc(),
      // The proof's link is added once it is uploaded (purchasing_sync).
      purchase: {'purchase_id': purchaseId, 'payment': paymentBody(payment.copyWith(proofUrl: null))},
      companyId: companyOf(u),
      receipts: {if (proofPhoto != null) 'proof': ReceiptUpload(local: proofPhoto, photoId: _newId())},
    ));
    await _kick();
  }

  @override
  Future<void> voidPayment(String paymentId, String reason, {required String opId}) async {
    final u = _user();
    if (reason.trim().isEmpty) throw const PurFailureException(PurFailure.reasonRequired);
    await _guard(() => remote.voidPayment(opId, paymentId, reason.trim(), userId: u));
  }

  @override
  Future<void> reportReturn(ReturnInput r, {String? photo}) async {
    final u = _user();
    final problems = returnProblems(r, today: today());
    if (problems.isNotEmpty) throw ReturnInvalid(problems);
    await db.queueOp(PurOp(
      opId: _newId(),
      userId: u,
      kind: opCashReturn,
      createdAt: _now().toUtc(),
      purchase: r.toJson(),
      companyId: companyOf(u),
      receipts: {if (photo != null) 'photo': ReceiptUpload(local: photo, photoId: _newId())},
    ));
    await _kick();
  }

  @override
  Future<void> withdrawReturn(String returnId, {required String opId}) async {
    final u = _user();
    await _guard(() => remote.withdrawReturn(opId, returnId, userId: u));
  }

  @override
  Future<void> dispute(String issueId, String note, {required String opId}) async {
    final u = _user();
    await _guard(() => remote.dispute(opId, issueId, note.trim(), userId: u));
  }

  @override
  Future<void> discardAction(String opId) async {
    final op = await db.discardFailedOp(_user(), opId);
    for (final r in op?.receipts.values ?? const <ReceiptUpload>[]) {
      await discardPhoto(r.local);
    }
  }

  @override
  Future<Uint8List?> receipt(String url) async {
    final hit = _receipts[url];
    if (hit != null) return hit;
    final bytes = await remote.receipt(url);
    if (bytes != null) _receipts[url] = bytes;
    return bytes;
  }

  @override
  Future<int> unsentFor(String userId) => db.unsentCount(userId);

  @override
  Future<void> keepOnly(String userId) async {
    if (userId != currentUserId() || userId.isEmpty) _receipts.clear();
    await db.keepCacheOnly(userId);
  }
}
