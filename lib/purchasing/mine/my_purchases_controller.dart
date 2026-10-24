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

  /// Refreshes started so far; only the latest may change what is shown.
  int _refreshes = 0;

  /// A refresh has answered (fresh, or its saved copy after the time limit).
  /// Until then the saved copy is shown at once.
  bool _answered = false;

  /// F3 (0.8.1): the list and the card in one refresh (read at the same
  /// time, with one time limit). A refresh that finishes after a newer one
  /// started changes nothing: its answer is older.
  Future<void> refresh() async {
    final mine = ++_refreshes;
    loading = true;
    notifyListeners();
    try {
      final d = await api.drafts();
      if (mine == _refreshes) drafts = d;
      // F3 (rev 2): what the phone already has, at once — the list never
      // waits for the network (opening the app with no signal).
      if (!_answered) {
        final saved = await api.savedPurchasesAndCash();
        if (mine == _refreshes && !_answered) {
          view = saved.purchases;
          cash = saved.cash;
          notifyListeners();
        }
      }
      final both = await api.myPurchasesAndCash();
      if (mine != _refreshes) return;
      view = both.purchases;
      cash = both.cash;
      _answered = true;
    } catch (e) {
      if (mine == _refreshes) notice = purFailureCopy(PurFailure.of(e));
    } finally {
      if (mine == _refreshes) {
        loading = false;
        notifyListeners();
      }
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
