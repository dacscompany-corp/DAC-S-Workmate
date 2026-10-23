/// How a purchase is paid, petty cash and "Company owes me" (0102, 0103), as
/// the phone reads them, and the payment checks the server would make. All of
/// it is OUTSIDE the money model: a payment never changes Spent; it only says
/// how a receipt was paid and whose money did it.
library;

import 'purchase_draft.dart' show parseMoney, round2;

double _num(Object? v) => switch (v) {
      num n => n.toDouble(),
      String s => double.tryParse(s) ?? 0,
      _ => 0,
    };

double? _numOrNull(Object? v) => v == null ? null : _num(v);

String _str(Object? v) => v == null ? '' : v.toString();

List<Map<String, dynamic>> _rows(Object? v) => [for (final r in (v as List<dynamic>? ?? const [])) Map<String, dynamic>.from(r as Map)];

/// Where the money for a payment came from (Q5). One payment, one source.
const paySources = ['petty_cash', 'own_money', 'company', 'credit'];

/// How it was handed over (Q5). A supplier credit is sent as 'other'.
const payMethods = ['cash', 'gcash', 'bank_transfer', 'check', 'other'];

/// The purchase form's "Paid by" word → a payment method (the web's methodOf).
String methodOf(String paymentMethod) {
  final m = paymentMethod.trim().toLowerCase().replaceAll(RegExp(r'\s+'), '_');
  return payMethods.contains(m) ? m : 'cash';
}

/// One purchase's payment state (`pur_pay_state`, 0102).
class PayState {
  const PayState({
    this.state = 'not_tracked',
    this.tracked = false,
    this.due = 0,
    this.paid = 0,
    this.balance = 0,
    this.excess = 0,
    this.unresolved = 0,
  });

  factory PayState.fromJson(Map<String, dynamic>? j) => j == null
      ? const PayState()
      : PayState(
          state: _str(j['state']).isEmpty ? 'not_tracked' : _str(j['state']),
          tracked: j['tracked'] == true,
          due: _num(j['due']),
          paid: _num(j['paid']),
          balance: _num(j['balance']),
          excess: _num(j['excess']),
          unresolved: _num(j['unresolved']),
        );

  /// not_tracked · unpaid · partial · paid · overpaid · void · void_paid.
  final String state;

  /// False on purchases recorded before 0102 until a payment is recorded (Q2).
  final bool tracked;
  final double due;
  final double paid;

  /// What is still to pay, never below zero.
  final double balance;
  final double excess;

  /// Over, and not yet refunded or kept as credit (the owner resolves it).
  final double unresolved;

  /// Payment is possible only on a recorded purchase (R12).
  bool get payable => state != 'void' && state != 'void_paid';

  /// The phone offers Record payment only on a purchase whose payments are
  /// tracked and that is not voided (R34): one from before 0102 stays "Payment
  /// not tracked" until the owner starts tracking it on Dacs Web (Q2).
  bool get canRecordPayment => tracked && payable;

  /// Still to pay once payments waiting on this phone are counted (Q6).
  double leftAfter(double unsent) => (round2(balance - unsent)).clamp(0, double.infinity).toDouble();

  Map<String, dynamic> toJson() => {
        'state': state,
        'tracked': tracked,
        'due': due,
        'paid': paid,
        'balance': balance,
        'excess': excess,
        'unresolved': unresolved,
      };
}

/// One payment on a purchase (`pur_payment_json`).
class PurPayment {
  const PurPayment({
    required this.id,
    this.amount = 0,
    this.paidOn = '',
    this.method = '',
    this.source = '',
    this.personName = '',
    this.creditId,
    this.authorized = true,
    this.acceptedAt,
    this.rejectedAt,
    this.rejectReason = '',
    this.proofUrl = '',
    this.note = '',
    this.createdByName = '',
    this.voidedAt,
    this.voidReason = '',
    this.canVoid = false,
    this.moved = false,
  });

  factory PurPayment.fromJson(Map<String, dynamic> j) => PurPayment(
        id: _str(j['id']),
        amount: _num(j['amount']),
        paidOn: _str(j['paid_on']),
        method: _str(j['method']),
        source: _str(j['source']),
        personName: _str(j['person_name']),
        creditId: j['credit_id'] as String?,
        authorized: j['authorized'] != false,
        acceptedAt: j['accepted_at'] as String?,
        rejectedAt: j['rejected_at'] as String?,
        rejectReason: _str(j['reject_reason']),
        proofUrl: _str(j['proof_url']),
        note: _str(j['note']),
        createdByName: _str(j['created_by_name']),
        voidedAt: j['voided_at'] as String?,
        voidReason: _str(j['void_reason']),
        canVoid: j['can_void'] == true,
        moved: j['moved'] == true,
      );

  final String id;
  final double amount;
  final String paidOn;
  final String method;
  final String source;
  final String personName;
  final String? creditId;

  /// Own money while "May use own money" was off is kept but not owed until
  /// the owner accepts it (Q21); a rejected one is never owed (R9).
  final bool authorized;
  final String? acceptedAt;
  final String? rejectedAt;
  final String rejectReason;
  final String proofUrl;
  final String note;
  final String createdByName;
  final String? voidedAt;
  final String voidReason;
  final bool canVoid;

  /// Carried over from the earlier version of a replaced purchase (R4).
  final bool moved;

  bool get voided => voidedAt != null;

  /// Own money the owner has not decided on yet.
  bool get toReview => source == 'own_money' && !authorized && acceptedAt == null && rejectedAt == null;
}

/// A balance with one supplier, used in parts (Q11, Q12; `pur_credits`).
class SupplierCredit {
  const SupplierCredit({required this.id, this.supplierId, this.supplier = '', this.amount = 0, this.left = 0, this.voided = false});

  factory SupplierCredit.fromJson(Map<String, dynamic> j) => SupplierCredit(
        id: _str(j['id']),
        supplierId: j['supplier_id'] as String?,
        supplier: _str(j['supplier']),
        amount: _num(j['amount']),
        left: _num(j['left']),
        voided: j['voided_at'] != null,
      );

  final String id;
  final String? supplierId;
  final String supplier;
  final double amount;
  final double left;
  final bool voided;

  bool get usable => !voided && left > 0;

  Map<String, dynamic> toJson() => {
        'id': id,
        'supplier_id': supplierId,
        'supplier': supplier,
        'amount': amount,
        'left': left,
        'voided_at': voided ? 'voided' : null,
      };
}

/// A purchase's payments as `pur_purchase_payments` gives them.
class PurchasePayments {
  const PurchasePayments({
    this.pay = const PayState(),
    this.supplierId,
    this.payments = const [],
    this.openCredits = const [],
    this.holder = false,
    this.ownMoney = false,
    this.cashHeld,
  });

  factory PurchasePayments.fromJson(Map<String, dynamic> j) {
    final me = Map<String, dynamic>.from((j['me'] as Map?) ?? const {});
    return PurchasePayments(
      pay: PayState.fromJson(j['pay'] == null ? null : Map<String, dynamic>.from(j['pay'] as Map)),
      supplierId: j['supplier_id'] as String?,
      payments: _rows(j['payments']).map(PurPayment.fromJson).toList(),
      openCredits: _rows(j['open_credits']).map(SupplierCredit.fromJson).toList(),
      holder: me['holder'] == true,
      ownMoney: me['own_money'] == true,
      cashHeld: _numOrNull(me['cash_held']),
    );
  }

  final PayState pay;
  final String? supplierId;
  final List<PurPayment> payments;

  /// Credit with this purchase's supplier that a payment may use.
  final List<SupplierCredit> openCredits;

  /// A staff buyer, who may pay from petty cash or their own money (R2).
  final bool holder;
  final bool ownMoney;

  /// Petty cash on record (may be below zero: the shortfall, Q16).
  final double? cashHeld;
}

/// Petty cash given to the buyer (`pur_cash_detail` issues).
class CashIssue {
  const CashIssue({
    required this.id,
    this.amount = 0,
    this.issuedOn = '',
    this.method = '',
    this.note = '',
    this.disputedAt,
    this.disputeNote = '',
    this.disputeClearedAt,
    this.disputeClearedNote = '',
    this.voidedAt,
    this.voidReason = '',
  });

  factory CashIssue.fromJson(Map<String, dynamic> j) => CashIssue(
        id: _str(j['id']),
        amount: _num(j['amount']),
        issuedOn: _str(j['issued_on']),
        method: _str(j['method']),
        note: _str(j['note']),
        disputedAt: j['disputed_at'] as String?,
        disputeNote: _str(j['dispute_note']),
        disputeClearedAt: j['dispute_cleared_at'] as String?,
        disputeClearedNote: _str(j['dispute_cleared_note']),
        voidedAt: j['voided_at'] as String?,
        voidReason: _str(j['void_reason']),
      );

  final String id;
  final double amount;
  final String issuedOn;
  final String method;
  final String note;
  final String? disputedAt;
  final String disputeNote;
  final String? disputeClearedAt;
  final String disputeClearedNote;
  final String? voidedAt;
  final String voidReason;

  bool get voided => voidedAt != null;

  /// "I did not receive this" is still open (Q14).
  bool get flagged => disputedAt != null && disputeClearedAt == null;

  /// One flag per entry; a voided entry is settled.
  bool get canDispute => !voided && disputedAt == null;
}

/// A return the buyer reported (`pur_cash_detail` returns; 0103 adds the photo).
class CashReturn {
  const CashReturn({
    required this.id,
    this.amount = 0,
    this.handedOn = '',
    this.handedTo = '',
    this.status = '',
    this.decisionNote = '',
    this.photoUrl = '',
    this.voidedAt,
  });

  factory CashReturn.fromJson(Map<String, dynamic> j) => CashReturn(
        id: _str(j['id']),
        amount: _num(j['amount']),
        handedOn: _str(j['handed_on']),
        handedTo: _str(j['handed_to']),
        status: _str(j['status']),
        decisionNote: _str(j['decision_note']),
        photoUrl: _str(j['photo_url']),
        voidedAt: j['voided_at'] as String?,
      );

  final String id;
  final double amount;
  final String handedOn;
  final String handedTo;

  /// reported · withdrawn · confirmed · rejected.
  final String status;
  final String decisionNote;
  final String photoUrl;
  final String? voidedAt;

  bool get waiting => status == 'reported';
}

/// The company repaying the buyer's own money.
class Repayment {
  const Repayment({required this.id, this.amount = 0, this.paidOn = '', this.method = '', this.voidedAt});

  factory Repayment.fromJson(Map<String, dynamic> j) => Repayment(
        id: _str(j['id']),
        amount: _num(j['amount']),
        paidOn: _str(j['paid_on']),
        method: _str(j['method']),
        voidedAt: j['voided_at'] as String?,
      );

  final String id;
  final double amount;
  final String paidOn;
  final String method;
  final String? voidedAt;
}

/// The buyer's own cash (`pur_my_cash`, Q23/Q24): never another buyer's.
class MyCash {
  const MyCash({
    this.holder = false,
    this.recorded = 0,
    this.held = 0,
    this.shortfall = 0,
    this.pendingReturns = 0,
    this.owes = 0,
    this.owesToReview = 0,
    this.ownMoney = false,
    this.lastGivenOn,
    this.issues = const [],
    this.returns = const [],
    this.repayments = const [],
  });

  factory MyCash.fromJson(Map<String, dynamic> j) => MyCash(
        holder: j['holder'] == true,
        recorded: _num(j['recorded']),
        held: _num(j['held']),
        shortfall: _num(j['shortfall']),
        pendingReturns: _num(j['pending_returns']),
        owes: _num(j['owes']),
        owesToReview: _num(j['owes_to_review']),
        ownMoney: j['own_money'] == true,
        lastGivenOn: j['last_given_on'] as String?,
        issues: _rows(j['issues']).map(CashIssue.fromJson).toList(),
        returns: _rows(j['returns']).map(CashReturn.fromJson).toList(),
        repayments: _rows(j['repayments']).map(Repayment.fromJson).toList(),
      );

  /// False for an owner account: only staff buyers hold petty cash (R2).
  final bool holder;

  /// Petty cash on record; below zero is a shortfall, never shown as cash (Q16).
  final double recorded;
  final double held;
  final double shortfall;

  /// Reported, not yet confirmed: never lowers [held] (Q17).
  final double pendingReturns;

  /// "Company owes me" — own money accepted or allowed, less repayments.
  final double owes;

  /// Own money paid while it was not allowed, waiting for the owner (Q21).
  final double owesToReview;

  /// "May use own money" is on (Q21).
  final bool ownMoney;
  final String? lastGivenOn;
  final List<CashIssue> issues;
  final List<CashReturn> returns;
  final List<Repayment> repayments;
}

/// What the "My cash" card shows once actions still on this phone count:
/// payments from petty cash lower it, a return waiting to send waits beside
/// it (Q17: only the owner's confirmation lowers the balance). Cash held is
/// never below zero; the rest is the shortfall (Q16).
({double held, double shortfall}) cashAfter(MyCash cash, {double unsentPettyCash = 0}) {
  final r = round2(cash.recorded - unsentPettyCash);
  return (held: r > 0 ? r : 0, shortfall: r < 0 ? -r : 0);
}

/// Q16: a warning, never a refusal — paying more petty cash than is on record.
/// Null when there is nothing to warn about (or the balance is unknown).
double? overspendBy(String amount, double? held) {
  final a = parseMoney(amount);
  if (held == null || a == null || a <= 0) return null;
  final h = held > 0 ? held : 0.0;
  return a > h ? round2(a - h) : null;
}

/// Why a payment would be refused — the server's codes (the web's
/// paymentProblems, the same order).
enum PayProblem { badAmount, badDate, badSource, badMethod, creditRequired, overCredit }

/// One payment being entered: in "Paid now?" (Q3) or Record payment (Q6).
class PaymentInput {
  const PaymentInput({
    this.amount = '',
    required this.paidOn,
    this.method = 'cash',
    this.source = 'company',
    this.creditId,
    this.note = '',
    this.proofUrl,
  });

  factory PaymentInput.fromJson(Map<String, dynamic> j) => PaymentInput(
        amount: _str(j['amount']),
        paidOn: _str(j['paid_on']),
        method: _str(j['method']).isEmpty ? 'cash' : _str(j['method']),
        source: _str(j['source']).isEmpty ? 'company' : _str(j['source']),
        creditId: j['credit_id'] as String?,
        note: _str(j['note']),
        proofUrl: j['proof_url'] as String?,
      );

  final String amount;
  final String paidOn;
  final String method;
  final String source;
  final String? creditId;
  final String note;
  final String? proofUrl;

  PaymentInput copyWith({String? amount, String? paidOn, String? method, String? source, Object? creditId = _keep, String? note, Object? proofUrl = _keep}) =>
      PaymentInput(
        amount: amount ?? this.amount,
        paidOn: paidOn ?? this.paidOn,
        method: method ?? this.method,
        source: source ?? this.source,
        creditId: identical(creditId, _keep) ? this.creditId : creditId as String?,
        note: note ?? this.note,
        proofUrl: identical(proofUrl, _keep) ? this.proofUrl : proofUrl as String?,
      );

  Map<String, dynamic> toJson() =>
      {'amount': amount, 'paid_on': paidOn, 'method': method, 'source': source, 'credit_id': creditId, 'note': note, 'proof_url': proofUrl};
}

const _keep = Object();

/// [today] is Manila's "YYYY-MM-DD"; [creditLeft] what the chosen credit has
/// left (null: unknown — the server checks it).
List<PayProblem> paymentProblems(PaymentInput p, {required String today, double? creditLeft}) {
  final out = <PayProblem>[];
  final a = parseMoney(p.amount);
  if (a == null || a <= 0) out.add(PayProblem.badAmount);
  if (!RegExp(r'^\d{4}-\d{2}-\d{2}$').hasMatch(p.paidOn) || p.paidOn.compareTo(today) > 0 || p.paidOn.compareTo('2020-01-01') < 0) {
    out.add(PayProblem.badDate);
  }
  if (!paySources.contains(p.source)) out.add(PayProblem.badSource);
  if (p.source != 'credit' && !payMethods.contains(p.method)) out.add(PayProblem.badMethod);
  if (p.source == 'credit') {
    if ((p.creditId ?? '').isEmpty) {
      out.add(PayProblem.creditRequired);
    } else if (a != null && a > 0 && creditLeft != null && a > creditLeft) {
      out.add(PayProblem.overCredit);
    }
  }
  return out;
}

/// The `pur_pay` / `pur_record` body of one payment (the web's paymentBody).
/// A buyer's petty cash and own money are their own: the server fills in the
/// person, so none is sent (R2).
Map<String, dynamic> paymentBody(PaymentInput p) => {
      // Two decimals as text: pur_money reads text, never a float's digits.
      'amount': round2(parseMoney(p.amount) ?? 0).toStringAsFixed(2),
      'paid_on': p.paidOn,
      'source': p.source,
      'method': p.source == 'credit' ? 'other' : p.method,
      'note': p.note.trim(),
      if (p.source == 'credit') 'credit_id': p.creditId,
      if ((p.proofUrl ?? '').isNotEmpty) 'proof_url': p.proofUrl,
    };

/// A return of petty cash the buyer reports (Q17). Only the owner's
/// confirmation lowers cash held, on the confirmation day (Q18).
class ReturnInput {
  const ReturnInput({this.amount = '', required this.handedOn, this.handedTo = '', this.note = ''});

  final String amount;
  final String handedOn;
  final String handedTo;
  final String note;

  Map<String, dynamic> toJson() => {
        // Two decimals as text, as pur_money reads it.
        'amount': round2(parseMoney(amount) ?? 0).toStringAsFixed(2),
        'handed_on': handedOn,
        'handed_to': handedTo.trim(),
        'note': note.trim(),
      };
}

enum ReturnProblem { badAmount, badDate }

/// What pur_cash_report_return would refuse: an amount above zero and a day
/// handed over, never in the future, from 2020 on. A return is never capped
/// by what is held (R11): it is real money the owner confirms.
List<ReturnProblem> returnProblems(ReturnInput r, {required String today}) => [
      if ((parseMoney(r.amount) ?? 0) <= 0) ReturnProblem.badAmount,
      if (!RegExp(r'^\d{4}-\d{2}-\d{2}$').hasMatch(r.handedOn) || r.handedOn.compareTo(today) > 0 || r.handedOn.compareTo('2020-01-01') < 0)
        ReturnProblem.badDate,
    ];
