import 'dart:typed_data';

import '../domain/pur_failure.dart';
import '../domain/pur_models.dart';
import '../domain/purchase_draft.dart';

/// The shopping list as last read: fresh when online, the saved copy offline.
class ShoppingView {
  const ShoppingView({this.lines = const [], this.batches = const [], this.fetchedAt, this.fromCache = false, this.error});
  final List<ShoppingLine> lines;
  final List<PurBatch> batches;
  final DateTime? fetchedAt;
  final bool fromCache;

  /// Why the server could not be read just now; null when it was.
  final Object? error;
}

/// Where a purchase may go and who it may be from (Q11), fresh or saved.
class PurchaseChoices {
  const PurchaseChoices({this.destinations = const [], this.suppliers = const [], this.fromCache = false});
  final List<PurDestination> destinations;
  final List<Supplier> suppliers;
  final bool fromCache;
}

enum QueuedState {
  /// Saved on the phone, not yet counted anywhere (Q7).
  waiting,

  /// The server refused it; it stays here with the reason until the buyer
  /// fixes it or throws it away (Q7). Never silently dropped.
  needsAttention,
}

/// A purchase recorded on the phone that the server does not have yet.
class QueuedPurchase {
  const QueuedPurchase({required this.draft, required this.state, this.failure});
  final PurchaseDraft draft;
  final QueuedState state;
  final PurFailure? failure;
}

/// My purchases (Q12): what is still on the phone, then the server's list.
class MyPurchasesView {
  const MyPurchasesView({this.queued = const [], this.purchases = const [], this.fetchedAt, this.fromCache = false, this.error});
  final List<QueuedPurchase> queued;
  final List<MyPurchase> purchases;
  final DateTime? fetchedAt;
  final bool fromCache;
  final Object? error;
}

/// Thrown by [PurchasingApi.send] for a draft the server would refuse.
class PurchaseInvalid implements Exception {
  const PurchaseInvalid(this.problems);
  final List<PurchaseProblem> problems;
  @override
  String toString() => 'PurchaseInvalid($problems)';
}

enum CorrectionOutcome { saved, needsOwner }

/// What a correction did, and the body it sent (with any new receipt links),
/// to send to the owner unchanged when only the owner may make it (Q13).
class CorrectionResult {
  const CorrectionResult(this.outcome, this.body);
  final CorrectionOutcome outcome;
  final Map<String, dynamic> body;
}

/// What the buying screens need. An interface so every controller and screen
/// tests with a fake instead of a database and a server.
abstract interface class PurchasingApi {
  /// The signed-in buyer, or '' — the scope of every read and write.
  String get me;

  Future<ShoppingView> shoppingList();

  // Online only (Q5, Q6): each throws when the server cannot be reached.
  Future<void> claim(PurPortion portion, {double? quantity});
  Future<void> release(PurPortion portion);
  Future<void> setArranged(PurPortion portion, bool arranged);

  Future<PurchaseChoices> choices();

  PurchaseDraft newDraft({List<DraftPurchaseLine> lines = const []});
  String newLineKey();

  /// Unsent drafts still being edited, newest first.
  Future<List<PurchaseDraft>> drafts();
  Future<void> saveDraft(PurchaseDraft draft);

  /// Discards an unsent draft and its photos.
  Future<void> deleteDraft(PurchaseDraft draft);

  /// Files a camera or gallery photo for [draftId]: upright, scaled,
  /// compressed, in app-private storage. Returns the stored path.
  Future<String> keepPhoto(String draftId, String sourcePath);
  Future<void> discardPhoto(String path);

  /// Queues the draft (throws [PurchaseInvalid] first) and starts sending.
  Future<void> send(PurchaseDraft draft);

  Future<MyPurchasesView> myPurchases();

  /// A refused purchase back to editing. False while it could still be sent.
  Future<bool> returnToDrafts(String draftId);

  /// Throws a refused purchase away, with its photos.
  Future<void> discardRefused(String draftId);

  /// One purchase in full. Online only.
  Future<PurchaseDetail> purchase(String id);

  /// Corrects the buyer's own purchase (Q13), uploading [newPhotos] (slot →
  /// file) first. [opId] is minted once per correction form, so a retry
  /// corrects once. When only the owner may make the change, nothing is
  /// changed and [CorrectionOutcome.needsOwner] comes back.
  Future<CorrectionResult> correct(PurchaseDetail purchase, Map<String, dynamic> body, String reason,
      {required String opId, Map<String, String> newPhotos = const {}});

  /// Sends the change to the owner instead (pur_request_change).
  Future<void> sendToOwner(PurchaseDetail purchase, Map<String, dynamic> body, String reason, {required String opId});

  /// A stored receipt photo, or null.
  Future<Uint8List?> receipt(String url);

  /// Purchases on the phone for [userId] not yet recorded (R2's screen).
  Future<int> unsentFor(String userId);

  /// Keeps only [userId]'s saved copy ('' keeps none). Unsent purchases are
  /// never touched.
  Future<void> keepOnly(String userId);
}
