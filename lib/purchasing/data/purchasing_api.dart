import 'dart:typed_data';

import '../domain/pay_models.dart';
import '../domain/pur_failure.dart';
import '../domain/pur_models.dart';
import '../domain/pur_op.dart';
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

  /// R38: the server has it, but the list shown was read before it went
  /// (a saved copy, offline). Shown and counted until a fresh read counts it.
  sent,
}

/// A purchase recorded on the phone that the server does not have yet.
class QueuedPurchase {
  const QueuedPurchase({required this.draft, required this.state, this.failure});
  final PurchaseDraft draft;
  final QueuedState state;
  final PurFailure? failure;
}

/// A payment or a return recorded on the phone that the server does not have
/// yet (0102, Q6): "Waiting to send", or refused ("Needs attention").
class QueuedCashAction {
  const QueuedCashAction({required this.opId, required this.kind, required this.body, required this.state, this.failure});

  final String opId;

  /// [opPay] or [opCashReturn].
  final String kind;

  /// pay: {purchase_id, payment}; cash_return: {amount, handed_on, handed_to, note}.
  final Map<String, dynamic> body;
  final QueuedState state;
  final PurFailure? failure;

  bool get isPayment => kind == opPay;
  String? get purchaseId => isPayment ? body['purchase_id'] as String? : null;
  Map<String, dynamic> get _payment => Map<String, dynamic>.from((body['payment'] as Map?) ?? const {});
  String get source => isPayment ? (_payment['source'] as String? ?? '') : '';
  double get amount => parseMoney(((isPayment ? _payment['amount'] : body['amount']) ?? '').toString()) ?? 0;
}

/// One purchase's payments read fresh (0102), with the payments on this phone
/// that read does not count (R38): both from the same read, so a payment is
/// never counted twice or missed.
class PurchasePaymentsView {
  const PurchasePaymentsView({required this.pay, this.queued = const []});
  final PurchasePayments pay;
  final List<QueuedCashAction> queued;
}

/// My purchases (Q12): what is still on the phone, then the server's list.
class MyPurchasesView {
  const MyPurchasesView(
      {this.queued = const [], this.purchases = const [], this.queuedPayments = const [], this.fetchedAt, this.fromCache = false, this.error});
  final List<QueuedPurchase> queued;
  final List<MyPurchase> purchases;

  /// Later payments still on the phone (Q6).
  final List<QueuedCashAction> queuedPayments;
  final DateTime? fetchedAt;
  final bool fromCache;
  final Object? error;

  /// Payments on [purchaseId] this list does not count yet (waiting to send,
  /// or sent after it was read): they count in what is shown as left to pay,
  /// marked as such (Q6, R38). Refused ones do not count.
  double unsentFor(String purchaseId) => queuedPayments
      .where((q) => q.purchaseId == purchaseId && q.state != QueuedState.needsAttention)
      .fold<double>(0, (a, q) => round2(a + q.amount));

  /// Whether [unsentFor] holds a payment already sent (R38): then it is "not
  /// in this list yet", never "waiting to send".
  bool sentFor(String purchaseId) => queuedPayments.any((q) => q.purchaseId == purchaseId && q.state == QueuedState.sent);
}

/// "My cash" (Q23): the buyer's own cash as last read, what is still on the
/// phone, and the supplier credits a payment may use.
class MyCashView {
  const MyCashView({this.cash, this.credits = const [], this.queued = const [], this.unsentPettyCash = 0, this.fetchedAt, this.fromCache = false, this.error});

  /// Null until it was read once (needs signal the first time).
  final MyCash? cash;
  final List<SupplierCredit> credits;

  /// Returns (and payments) waiting to send or refused.
  final List<QueuedCashAction> queued;

  /// Petty cash in payments still on the phone (purchases paid now, and
  /// later payments): it lowers cash held as shown (Q16).
  final double unsentPettyCash;
  final DateTime? fetchedAt;
  final bool fromCache;
  final Object? error;

  /// Cash held never below zero, and the shortfall (Q16), counting [unsentPettyCash].
  ({double held, double shortfall})? get figures => cash == null ? null : cashAfter(cash!, unsentPettyCash: unsentPettyCash);

  List<QueuedCashAction> get queuedReturns => [for (final q in queued) if (q.kind == opCashReturn) q];

  /// Usable credits with one supplier (Q11).
  List<SupplierCredit> creditsFor(String? supplierId) =>
      supplierId == null ? const [] : [for (final c in credits) if (c.usable && c.supplierId == supplierId) c];
}

/// Thrown by [PurchasingApi.pay] for a payment the server would refuse.
class PaymentInvalid implements Exception {
  const PaymentInvalid(this.problems);
  final List<PayProblem> problems;
  @override
  String toString() => 'PaymentInvalid($problems)';
}

/// Thrown by [PurchasingApi.reportReturn] for a return the server would refuse.
class ReturnInvalid implements Exception {
  const ReturnInvalid(this.problems);
  final List<ReturnProblem> problems;
  @override
  String toString() => 'ReturnInvalid($problems)';
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

  // ── paying, petty cash, own money (0102, 0103) ──

  /// Today in Manila, "YYYY-MM-DD": the latest day a payment or return may carry.
  String today();

  /// The buyer's own cash: fresh when online, the saved copy offline.
  Future<MyCashView> myCash();

  /// One purchase's payments and what this account may pay with, with the
  /// payments on this phone it does not count. Online only.
  Future<PurchasePaymentsView> purchasePayments(String purchaseId);

  /// Payments on [purchaseId] still on this phone (waiting, sent after the
  /// saved list was read, or refused): for when there is no signal.
  Future<List<QueuedCashAction>> queuedPayments(String purchaseId);

  /// Queues a later payment (Q6: also with no signal) and starts sending.
  /// [proofPhoto]: a kept photo (GCash screenshot, deposit slip), optional.
  /// Throws [PaymentInvalid] first.
  Future<void> pay(String purchaseId, PaymentInput payment, {String? proofPhoto});

  /// Voids a payment this account recorded, with a reason (Q7). Online only.
  Future<void> voidPayment(String paymentId, String reason, {required String opId});

  /// Queues a return of petty cash (Q17) with an optional kept photo, and
  /// starts sending. Throws [ReturnInvalid] first.
  Future<void> reportReturn(ReturnInput r, {String? photo});

  /// Takes back a return the owner has not decided yet. Online only.
  Future<void> withdrawReturn(String returnId, {required String opId});

  /// "I did not receive this" on petty cash given (Q14). Online only.
  Future<void> dispute(String issueId, String note, {required String opId});

  /// Throws a refused payment or return away, with its photo.
  Future<void> discardAction(String opId);

  /// Keeps only [userId]'s saved copy ('' keeps none). Unsent purchases are
  /// never touched.
  Future<void> keepOnly(String userId);
}
