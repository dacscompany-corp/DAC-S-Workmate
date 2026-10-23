import 'dart:async';
import 'dart:typed_data';

import 'package:workmate/purchasing/data/purchasing_api.dart';
import 'package:workmate/purchasing/domain/pay_models.dart';
import 'package:workmate/purchasing/domain/pur_models.dart';
import 'package:workmate/purchasing/domain/purchase_draft.dart';

import 'purchasing_fakes.dart';

/// A PurchasingApi for controllers and screens: answers the test sets, every
/// call recorded.
class FakePurchasingApi implements PurchasingApi {
  @override
  String me = 'u1';

  ShoppingView shopping = ShoppingView(lines: [cement()], batches: [thisWeek, nextWeek], fetchedAt: wednesday);
  PurchaseChoices choiceList = const PurchaseChoices(destinations: [barlin], suppliers: [zzHardware]);
  MyPurchasesView mine = const MyPurchasesView();
  PurchaseDetail detail = PurchaseDetail.fromJson(const {'id': 'pu1', 'status': 'recorded'});
  List<PurchaseDraft> draftList = [];
  CorrectionOutcome correctionOutcome = CorrectionOutcome.saved;

  /// Thrown by the next call that can fail (then cleared).
  Object? error;
  Object? keepError;

  // 0102: the buyer's cash and one purchase's payments, as the test sets them.
  MyCashView cash = const MyCashView(cash: MyCash(holder: true, recorded: 1470, held: 1470));
  PurchasePayments payments = const PurchasePayments(pay: PayState(state: 'unpaid', tracked: true, due: 1000, balance: 1000), holder: true);
  String todayIs = '2026-10-21';
  List<QueuedCashAction> queuedFor = const [];

  /// While set, pay and reportReturn wait for it (a slow Save).
  Completer<void>? saveGate;
  final paid = <(String, PaymentInput, String?)>[];
  final returned = <(ReturnInput, String?)>[];

  final calls = <String>[];
  final sent = <PurchaseDraft>[];
  final saved = <PurchaseDraft>[];
  final bodies = <Map<String, dynamic>>[];
  var _ids = 0;

  void _maybeFail() {
    final e = error;
    if (e == null) return;
    error = null;
    throw e;
  }

  @override
  Future<ShoppingView> shoppingList() async {
    calls.add('shoppingList');
    _maybeFail();
    return shopping;
  }

  @override
  Future<void> claim(PurPortion portion, {double? quantity}) async {
    calls.add('claim:${portion.id}:$quantity');
    _maybeFail();
  }

  @override
  Future<void> release(PurPortion portion) async {
    calls.add('release:${portion.id}');
    _maybeFail();
  }

  @override
  Future<void> setArranged(PurPortion portion, bool arranged) async {
    calls.add('arranged:${portion.id}:$arranged');
    _maybeFail();
  }

  @override
  Future<PurchaseChoices> choices() async {
    calls.add('choices');
    _maybeFail();
    return choiceList;
  }

  @override
  PurchaseDraft newDraft({List<DraftPurchaseLine> lines = const []}) =>
      PurchaseDraft(id: 'draft${++_ids}', createdAt: wednesday, purchaseDate: '2026-10-21', lines: lines);

  @override
  String newLineKey() => 'line${++_ids}';

  @override
  Future<List<PurchaseDraft>> drafts() async => draftList;

  @override
  Future<void> saveDraft(PurchaseDraft draft) async => saved.add(draft);

  @override
  Future<void> deleteDraft(PurchaseDraft draft) async => calls.add('deleteDraft:${draft.id}');

  @override
  Future<String> keepPhoto(String draftId, String sourcePath) async => '/kept/$sourcePath';

  @override
  Future<void> discardPhoto(String path) async => calls.add('discardPhoto:$path');

  @override
  Future<void> send(PurchaseDraft draft) async {
    final problems = purchaseProblems(draft);
    if (problems.isNotEmpty) throw PurchaseInvalid(problems);
    _maybeFail();
    sent.add(draft);
  }

  @override
  Future<MyPurchasesView> myPurchases() async {
    calls.add('myPurchases');
    _maybeFail();
    return mine;
  }

  @override
  Future<bool> returnToDrafts(String draftId) async {
    calls.add('returnToDrafts:$draftId');
    return true;
  }

  @override
  Future<void> discardRefused(String draftId) async => calls.add('discardRefused:$draftId');

  @override
  Future<PurchaseDetail> purchase(String id) async {
    calls.add('purchase:$id');
    _maybeFail();
    return detail;
  }

  @override
  Future<CorrectionResult> correct(PurchaseDetail purchase, Map<String, dynamic> body, String reason,
      {required String opId, Map<String, String> newPhotos = const {}}) async {
    calls.add('correct:${purchase.id}:$reason:${newPhotos.keys.join(',')}');
    _maybeFail();
    bodies.add(body);
    return CorrectionResult(correctionOutcome, body);
  }

  @override
  Future<void> sendToOwner(PurchaseDetail purchase, Map<String, dynamic> body, String reason, {required String opId}) async {
    calls.add('owner:${purchase.id}:$reason');
    _maybeFail();
    bodies.add(body);
  }

  @override
  Future<Uint8List?> receipt(String url) async => null;

  @override
  Future<int> unsentFor(String userId) async => 0;

  @override
  String today() => todayIs;

  @override
  Future<MyCashView> myCash() async {
    calls.add('myCash');
    _maybeFail();
    return cash;
  }

  /// Thrown by every purchasePayments read while set (the purchase itself still reads).
  Object? paymentsError;

  @override
  Future<PurchasePaymentsView> purchasePayments(String purchaseId) async {
    calls.add('payments:$purchaseId');
    final e = paymentsError;
    if (e != null) throw e;
    _maybeFail();
    return PurchasePaymentsView(pay: payments, queued: [for (final q in queuedFor) if (q.purchaseId == purchaseId) q]);
  }

  @override
  Future<List<QueuedCashAction>> queuedPayments(String purchaseId) async => [for (final q in queuedFor) if (q.purchaseId == purchaseId) q];

  @override
  Future<void> pay(String purchaseId, PaymentInput payment, {String? proofPhoto}) async {
    final problems = paymentProblems(payment, today: todayIs);
    if (problems.isNotEmpty) throw PaymentInvalid(problems);
    await saveGate?.future;
    _maybeFail();
    paid.add((purchaseId, payment, proofPhoto));
  }

  @override
  Future<void> voidPayment(String paymentId, String reason, {required String opId}) async {
    calls.add('voidPayment:$paymentId:$reason');
    _maybeFail();
  }

  @override
  Future<void> reportReturn(ReturnInput r, {String? photo}) async {
    final problems = returnProblems(r, today: todayIs);
    if (problems.isNotEmpty) throw ReturnInvalid(problems);
    await saveGate?.future;
    _maybeFail();
    returned.add((r, photo));
  }

  @override
  Future<void> withdrawReturn(String returnId, {required String opId}) async {
    calls.add('withdraw:$returnId');
    _maybeFail();
  }

  @override
  Future<void> dispute(String issueId, String note, {required String opId}) async {
    calls.add('dispute:$issueId:$note');
    _maybeFail();
  }

  @override
  Future<void> discardAction(String opId) async => calls.add('discardAction:$opId');

  @override
  Future<void> keepOnly(String userId) async {
    calls.add('keepOnly:$userId');
    final e = keepError;
    if (e != null) throw e;
  }
}
