import 'package:flutter/foundation.dart';

import '../../attendance/ui/attendance_copy.dart' show Bilingual;
import '../data/purchasing_api.dart';
import '../domain/pur_failure.dart';
import '../domain/purchase_draft.dart';

/// My purchases (Q12): drafts still being written, purchases waiting on the
/// phone or needing attention (Q7), then what the server has — the last 60
/// days of what this buyer bought or recorded.
class MyPurchasesController extends ChangeNotifier {
  MyPurchasesController({required this.api});

  final PurchasingApi api;

  MyPurchasesView view = const MyPurchasesView();

  /// The "My cash" card (0102, Q23): the buyer's own cash, fresh or saved.
  MyCashView cash = const MyCashView();
  List<PurchaseDraft> drafts = const [];
  bool loading = false;
  Bilingual? notice;

  /// Needs attention: shown as a number on the tab (refused payments and
  /// returns too: each needs the buyer to look).
  int get attention =>
      view.queued.where((q) => q.state == QueuedState.needsAttention).length +
      view.queuedPayments.where((q) => q.state == QueuedState.needsAttention).length +
      cash.queuedReturns.where((q) => q.state == QueuedState.needsAttention).length;

  Future<void> refresh() async {
    loading = true;
    notifyListeners();
    try {
      drafts = await api.drafts();
      view = await api.myPurchases();
      try {
        cash = await api.myCash();
      } catch (_) {
        // The card waits for the first read; the purchases still show.
      }
    } catch (e) {
      notice = purFailureCopy(PurFailure.of(e));
    } finally {
      loading = false;
      notifyListeners();
    }
  }

  /// A refused purchase back to editing; null when it could not be.
  Future<PurchaseDraft?> edit(QueuedPurchase q) async {
    if (!await api.returnToDrafts(q.draft.id)) return null;
    await refresh();
    return q.draft;
  }

  Future<void> throwAway(QueuedPurchase q) async {
    await api.discardRefused(q.draft.id);
    await refresh();
  }

  /// A refused payment thrown away (with its proof photo).
  Future<void> throwAwayPayment(QueuedCashAction q) async {
    await api.discardAction(q.opId);
    await refresh();
  }

  Future<void> deleteDraft(PurchaseDraft d) async {
    await api.deleteDraft(d);
    await refresh();
  }

  void dismissNotice() {
    notice = null;
    notifyListeners();
  }
}
