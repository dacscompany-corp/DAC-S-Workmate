import 'package:flutter/foundation.dart';

import '../../attendance/ui/attendance_copy.dart' show Bilingual;
import '../data/purchasing_api.dart';
import '../domain/pur_failure.dart';
import '../domain/pur_models.dart';
import '../domain/purchase_draft.dart';

/// One portion as the list shows it, with its request line.
class ShoppingEntry {
  const ShoppingEntry(this.line, this.portion);
  final ShoppingLine line;
  final PurPortion portion;
}

/// The list as the screen shows it (Q4): Mine at the top, then Unassigned,
/// then other buyers' portions (read-only), each in the server's order —
/// urgent and needed-by first.
class ShoppingSections {
  const ShoppingSections({this.mine = const [], this.unassigned = const [], this.others = const []});
  final List<ShoppingEntry> mine;
  final List<ShoppingEntry> unassigned;
  final List<ShoppingEntry> others;
  bool get isEmpty => mine.isEmpty && unassigned.isEmpty && others.isEmpty;
}

/// Which batches the list shows: this week's (the default, Q4) or all.
enum BatchScope { thisWeek, all }

class ShoppingController extends ChangeNotifier {
  ShoppingController({required this.api, DateTime Function()? now}) : _now = now ?? DateTime.now;

  final PurchasingApi api;
  final DateTime Function() _now;

  ShoppingView _view = const ShoppingView();
  ShoppingView get view => _view;

  bool loading = false;
  BatchScope scope = BatchScope.thisWeek;

  /// A project id, or null for every project.
  String? project;

  /// Portions waiting on the server right now.
  final busy = <String>{};

  /// Mine portions picked for "Record purchase", by portion id.
  final selected = <String>{};

  /// What the last action could not do, in both languages.
  Bilingual? notice;

  Future<void> refresh() async {
    loading = true;
    notifyListeners();
    try {
      _view = await api.shoppingList();
    } catch (e) {
      // BUYER_REQUIRED: the app leaves this screen (R2). Anything else keeps
      // what is shown and says why.
      notice = purFailureCopy(PurFailure.of(e));
    } finally {
      loading = false;
      // A portion no longer mine is no longer picked.
      selected.retainWhere((id) => sections.mine.any((e) => e.portion.id == id));
      notifyListeners();
    }
  }

  PurBatch? get currentBatch => PurBatch.current(_view.batches, _now());

  /// Projects on the list, for the filter: (id, name), by name.
  List<(String, String)> get projects {
    final seen = <String, String>{};
    for (final l in _view.lines) {
      seen.putIfAbsent(l.projectId, () => l.projectName);
    }
    return seen.entries.map((e) => (e.key, e.value)).toList()..sort((a, b) => a.$2.toLowerCase().compareTo(b.$2.toLowerCase()));
  }

  ShoppingSections get sections {
    final batch = currentBatch;
    final mine = <ShoppingEntry>[];
    final unassigned = <ShoppingEntry>[];
    final others = <ShoppingEntry>[];
    for (final l in _view.lines) {
      if (project != null && l.projectId != project) continue;
      for (final p in l.portions) {
        if (p.stillToBuy <= 0) continue;
        if (scope == BatchScope.thisWeek && (batch == null || p.batchId != batch.id)) continue;
        final e = ShoppingEntry(l, p);
        if (p.mine) {
          mine.add(e);
        } else if (p.unassigned) {
          unassigned.add(e);
        } else {
          others.add(e);
        }
      }
    }
    return ShoppingSections(mine: mine, unassigned: unassigned, others: others);
  }

  void setScope(BatchScope s) {
    scope = s;
    notifyListeners();
  }

  void setProject(String? id) {
    project = id;
    notifyListeners();
  }

  void toggle(ShoppingEntry e) {
    if (!e.portion.mine) return;
    if (!selected.remove(e.portion.id)) selected.add(e.portion.id);
    notifyListeners();
  }

  void dismissNotice() {
    notice = null;
    notifyListeners();
  }

  Future<void> _act(ShoppingEntry e, Future<void> Function() call) async {
    if (busy.contains(e.portion.id)) return;
    busy.add(e.portion.id);
    notice = null;
    notifyListeners();
    try {
      await call();
      busy.remove(e.portion.id);
      await refresh();
    } catch (err) {
      busy.remove(e.portion.id);
      notice = purFailureCopy(PurFailure.of(err));
      notifyListeners();
    }
  }

  /// "I'll buy this" (Q5): all of it, or [quantity] of it. Online only.
  Future<void> claim(ShoppingEntry e, {double? quantity}) =>
      _act(e, () => api.claim(e.portion, quantity: quantity != null && quantity < e.portion.stillToBuy ? quantity : null));

  Future<void> release(ShoppingEntry e) => _act(e, () async {
        selected.remove(e.portion.id);
        await api.release(e.portion);
      });

  /// Q6: own portions only.
  Future<void> setArranged(ShoppingEntry e, bool arranged) => _act(e, () => api.setArranged(e.portion, arranged));

  /// The picked portions as purchase lines: one line per request line.
  List<DraftPurchaseLine> linesForSelected() {
    final byLine = <String, (ShoppingLine, List<PurPortion>)>{};
    for (final e in sections.mine) {
      if (!selected.contains(e.portion.id)) continue;
      byLine.putIfAbsent(e.line.lineId, () => (e.line, <PurPortion>[])).$2.add(e.portion);
    }
    return [for (final v in byLine.values) DraftPurchaseLine.fromShopping(api.newLineKey(), v.$1, v.$2)];
  }

  void clearSelection() {
    selected.clear();
    notifyListeners();
  }
}
