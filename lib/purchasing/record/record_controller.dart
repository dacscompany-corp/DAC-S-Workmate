import 'dart:async';

import 'package:flutter/foundation.dart';

import '../../attendance/ui/attendance_copy.dart' show Bilingual;
import '../../requests/domain/quantity.dart';
import '../data/purchasing_api.dart';
import '../domain/pur_failure.dart';
import '../domain/pur_models.dart';
import '../domain/purchase_draft.dart';

/// A place a purchase line may go (Q11): a project, one of its open
/// Additional Works jobs, or the warehouse ([folderId] null).
class PlaceOption {
  const PlaceOption(this.folderId, this.label);
  final String? folderId;
  final String label;
  bool get warehouse => folderId == null;
}

/// The Record purchase form (Q7–Q11). Every change is saved on the phone at
/// once; Send queues it to be recorded when there is signal.
class RecordController extends ChangeNotifier {
  RecordController({required this.api, required PurchaseDraft draft}) : _draft = draft;

  final PurchasingApi api;
  PurchaseDraft _draft;
  PurchaseDraft get draft => _draft;

  PurchaseChoices? choices;

  /// Problems are shown once the buyer has tried to send.
  bool _tried = false;
  List<PurchaseProblem> get problems => _tried ? purchaseProblems(_draft) : const [];

  bool sending = false;
  Bilingual? notice;

  Future<void> load() async {
    try {
      choices = await api.choices();
    } catch (e) {
      notice = purFailureCopy(PurFailure.of(e));
    }
    notifyListeners();
  }

  void _set(PurchaseDraft d) {
    _draft = d;
    unawaited(api.saveDraft(d).catchError((Object _) {}));
    notifyListeners();
  }

  /// Where an unplanned line may go: every open project and job, then the warehouse.
  List<PlaceOption> get places => [
        for (final d in choices?.destinations ?? const <PurDestination>[]) ...[
          PlaceOption(d.folderId, d.name),
          for (final w in d.works) PlaceOption(w.folderId, '${d.name} · ${w.name}'),
        ],
        const PlaceOption(null, 'Warehouse'),
      ];

  List<Supplier> get suppliers => [for (final s in choices?.suppliers ?? const <Supplier>[]) if (s.active) s];

  // ── the purchase ───────────────────────────────────────────────────────

  void setDate(String iso) => _set(_draft.copyWith(purchaseDate: iso));

  /// A supplier from the list, or (null) one typed by name.
  void setSupplier(Supplier? s) => _set(_draft.copyWith(supplierId: s?.id, supplierName: s?.label ?? ''));

  void setSupplierName(String name) => _set(_draft.copyWith(supplierId: null, supplierName: name));

  void setPayment(String method) => _set(_draft.copyWith(paymentMethod: method));

  void setNotes(String notes) => _set(_draft.copyWith(notes: notes));

  void setTotal(String total) => _set(_draft.copyWith(receiptTotal: total));

  // ── lines ──────────────────────────────────────────────────────────────

  /// An item with no request (Q11): needs a reason and a place.
  void addLine() => _set(_draft.copyWith(
        lines: [..._draft.lines, DraftPurchaseLine(key: api.newLineKey(), quantity: '1', category: 'Materials')],
        // A new line changes the split: an adjusted one must be redone.
        charges: [for (final c in _draft.charges) c.copyWith(shares: null)],
      ));

  void updateLine(int i, DraftPurchaseLine line) {
    final lines = [..._draft.lines]..[i] = line;
    _set(_draft.copyWith(lines: lines));
  }

  void setPlace(int i, PlaceOption place) => updateLine(
        i,
        _draft.lines[i].copyWith(
          destination: place.warehouse ? 'warehouse' : 'project',
          folderId: place.folderId,
          folderLabel: place.label,
        ),
      );

  void removeLine(int i) {
    final lines = [..._draft.lines]..removeAt(i);
    _set(_draft.copyWith(lines: lines, charges: [for (final c in _draft.charges) c.copyWith(shares: null)]));
  }

  // ── fees and discounts (Q9) ────────────────────────────────────────────

  void addCharge(String kind) => _set(_draft.copyWith(charges: [..._draft.charges, DraftCharge(kind: kind)]));

  void updateCharge(int i, DraftCharge c) {
    final charges = [..._draft.charges]..[i] = c;
    _set(_draft.copyWith(charges: charges));
  }

  void removeCharge(int i) {
    final charges = [..._draft.charges]..removeAt(i);
    _set(_draft.copyWith(charges: charges));
  }

  /// The buyer adjusts the split, starting from the server's default one.
  void adjustSplit(int i, bool on) {
    final c = _draft.charges[i];
    if (!on) return updateCharge(i, c.copyWith(shares: null));
    final split = prorate(parseMoney(c.amount) ?? 0, [for (final l in _draft.lines) parseMoney(l.amount) ?? 0]);
    updateCharge(i, c.copyWith(shares: [for (final s in split) s.toStringAsFixed(2)]));
  }

  // ── receipt (Q8) ───────────────────────────────────────────────────────

  Future<void> addPhoto(String slot, String sourcePath) async {
    final kept = await api.keepPhoto(_draft.id, sourcePath);
    final old = _draft.photos[slot];
    _set(_draft.copyWith(photos: {..._draft.photos, slot: kept}, noReceipt: false));
    if (old != null) await api.discardPhoto(old);
  }

  Future<void> removePhoto(String slot) async {
    final old = _draft.photos[slot];
    _set(_draft.copyWith(photos: {..._draft.photos}..remove(slot)));
    if (old != null) await api.discardPhoto(old);
  }

  void setNoReceipt(bool on) => _set(_draft.copyWith(noReceipt: on));

  void setNoReceiptReason(String reason) => _set(_draft.copyWith(noReceiptReason: reason));

  /// "Items + fees − discounts", for the total check (Q9).
  String get computedTotalText => formatQuantity(_draft.computedTotal);

  // ── send ───────────────────────────────────────────────────────────────

  /// True once queued (it goes out when there is signal, Q7); false when the
  /// form still has problems, now shown.
  Future<bool> send() async {
    _tried = true;
    if (purchaseProblems(_draft).isNotEmpty || sending) {
      notifyListeners();
      return false;
    }
    sending = true;
    notice = null;
    notifyListeners();
    try {
      await api.send(_draft);
      return true;
    } on PurchaseInvalid {
      return false;
    } catch (e) {
      notice = purFailureCopy(PurFailure.of(e));
      return false;
    } finally {
      sending = false;
      notifyListeners();
    }
  }

  /// Throws the draft away, with its photos.
  Future<void> discard() => api.deleteDraft(_draft);
}
