import 'dart:io';

import '../../attendance/domain/work_date.dart';
import '../../attendance/sync/submission_sync.dart' show SyncResult;
import '../data/purchasing_db.dart';
import '../data/purchasing_remote.dart';
import '../domain/pur_failure.dart';
import '../domain/pur_op.dart';

/// A sane ceiling for one pass.
const _maxPerRun = 50;

/// Sends purchases recorded on the phone (Q7): for each, its receipt photos
/// (each once: the link is kept between attempts), then pur_record with the
/// op id minted at Send, so it is recorded once however often it is tried.
/// One account's queue, in order; stops at the first failure worth retrying.
class PurchasingSync {
  PurchasingSync({required this.db, required this.remote, DateTime Function()? now}) : _now = now ?? DateTime.now;

  final PurchasingDb db;
  final PurchasingRemote remote;
  final DateTime Function() _now;

  /// Purchases the last [drain] finished with: recorded, or refused for good.
  int settled = 0;

  Future<SyncResult> drain(String userId) async {
    settled = 0;
    // With no session nothing may be sent: it would file under whoever signs in next.
    if (userId.isEmpty) return SyncResult.done;
    for (var i = 0; i < _maxPerRun; i++) {
      final queue = await db.sendable(userId);
      if (queue.isEmpty) return SyncResult.done;
      if (await _send(queue.first, userId) == SyncResult.retry) return SyncResult.retry;
      settled++;
    }
    return SyncResult.done;
  }

  Future<SyncResult> _send(PurOp op, String userId) async {
    var o = op;
    try {
      if (o.companyId == null && o.receipts.isNotEmpty) {
        o = o.copyWith(companyId: await remote.company(userId));
        await db.updateOpBody(o.opId, o.bodyJson);
      }
      final docs = <String, String>{};
      for (final e in o.receipts.entries) {
        var r = e.value;
        final done = r.url;
        if (done != null) {
          docs[e.key] = done;
          continue;
        }
        final file = File(r.local);
        if (!file.existsSync()) throw const PurFailureException(PurFailure.photoMissing);
        if (r.path == null) {
          r = r.withPath(receiptPath(companyId: o.companyId!, manilaNow: manilaFields(_now()), photoId: r.photoId));
          o = o.copyWith(receipts: {...o.receipts, e.key: r});
          await db.updateOpBody(o.opId, o.bodyJson);
        }
        final url = await remote.uploadReceipt(path: r.path!, localPath: file.path, companyId: o.companyId!, userId: userId);
        o = o.copyWith(receipts: {...o.receipts, e.key: r.withUrl(url)});
        await db.updateOpBody(o.opId, o.bodyJson);
        docs[e.key] = url;
      }
      await remote.record(o.opId, {...o.purchase, 'docs': docs}, userId: userId);
      await db.finishRecord(o.opId, o.draftId);
      for (final r in o.receipts.values) {
        _discard(File(r.local)); // only now is the photo safe to delete
      }
      return SyncResult.done;
    } catch (error) {
      final failure = PurFailure.of(error);
      await db.recordAttempt(o.opId, failure.name, countsTowardCap: failure.countsTowardCap);
      final givingUp = failure.countsTowardCap && o.attempts + 1 >= maxPurchaseAttempts;
      if (failure.retryable && !givingUp) return SyncResult.retry;
      // Kept, flagged and shown ("Needs attention"): never let a buyer
      // believe it was recorded.
      await db.markFailed(o.opId, failure.name);
      return SyncResult.done;
    }
  }

  void _discard(File photo) {
    try {
      photo.deleteSync();
    } catch (_) {}
  }
}
