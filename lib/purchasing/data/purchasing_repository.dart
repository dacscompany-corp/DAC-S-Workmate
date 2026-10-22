import 'dart:async';
import 'dart:io';
import 'dart:typed_data';

import '../../attendance/device/device_bridge.dart';
import '../../attendance/domain/event_id.dart';
import '../../attendance/domain/work_date.dart';
import '../../attendance/sync/upload_scheduler.dart';
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
    final problems = purchaseProblems(draft);
    if (problems.isNotEmpty) throw PurchaseInvalid(problems);
    final u = _user();
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
    try {
      final fresh = await _guard(remote.myPurchases);
      docs = fresh;
      fetchedAt = _now();
      await db.putCache(u, 'my_purchases', fresh, fetchedAt);
    } catch (e) {
      if (PurFailure.of(e) == PurFailure.buyingOff) rethrow;
      error = e;
      final cached = await db.cache(u, 'my_purchases');
      if (cached != null) {
        docs = _rows(cached.body);
        fetchedAt = cached.at;
        fromCache = true;
      }
    }
    final ops = {for (final o in await db.ops(u)) o.draftId: o};
    final queued = [
      for (final d in await db.drafts(u, queued: true))
        if (ops[d.id] case final op?)
          QueuedPurchase(
            draft: d,
            state: op.failedPermanently ? QueuedState.needsAttention : QueuedState.waiting,
            failure: op.failedPermanently ? PurFailure.fromStored(op.lastError) : null,
          ),
    ];
    return MyPurchasesView(
      queued: queued,
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
