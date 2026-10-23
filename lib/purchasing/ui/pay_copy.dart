import '../../attendance/ui/attendance_copy.dart' show Bilingual;
import '../domain/pay_models.dart';

// Q22: English, with the Tagalog line underneath. The words match Dacs Web's
// Purchasing tab (purchasing-admin-core.js PAY_STATE / PAY_SOURCE / PAY_METHOD).

/// A purchase's payment state (0102).
Bilingual payStateCopy(String state) => switch (state) {
      'unpaid' => const Bilingual('Unpaid', 'Hindi pa bayad'),
      'partial' => const Bilingual('Partially paid', 'Bahagyang bayad'),
      'paid' => const Bilingual('Paid', 'Bayad na'),
      'overpaid' => const Bilingual('Overpaid', 'Sobra ang bayad'),
      'void' => const Bilingual('Void', 'Void'),
      'void_paid' => const Bilingual('Voided — paid, to recover', 'Na-void — may bayad, babawiin'),
      _ => const Bilingual('Payment not tracked', 'Hindi naitala ang bayad'),
    };

/// Where the money came from (Q5).
Bilingual paySourceCopy(String source) => switch (source) {
      'petty_cash' => const Bilingual('Petty cash', 'Petty cash'),
      'own_money' => const Bilingual('My own money', 'Sariling pera'),
      'company' => const Bilingual('Company (paid directly)', 'Kompanya (direktang bayad)'),
      'credit' => const Bilingual('Supplier credit', 'Credit sa supplier'),
      _ => Bilingual(source, source),
    };

/// How it was handed over (Q5).
String payMethodLabel(String method) => switch (method) {
      'cash' => 'Cash',
      'gcash' => 'GCash',
      'bank_transfer' => 'Bank transfer',
      'check' => 'Check',
      'other' => 'Other',
      _ => method,
    };

/// "Paid now?" (Q3).
Bilingual paidNowCopy(String paidNow) => switch (paidNow) {
      'full' => const Bilingual('Paid in full', 'Bayad nang buo'),
      'part' => const Bilingual('Paid part (deposit)', 'Bahagyang bayad (deposito)'),
      _ => const Bilingual('Not paid yet', 'Hindi pa bayad'),
    };

/// What to do about each payment problem, before sending.
Bilingual payProblemCopy(PayProblem p) => switch (p) {
      PayProblem.badAmount => const Bilingual('Enter the amount paid.', 'Ilagay ang halagang ibinayad.'),
      PayProblem.badDate =>
        const Bilingual('Pick the day it was paid (not in the future).', 'Piliin ang araw ng pagbayad (hindi sa hinaharap).'),
      PayProblem.badSource => const Bilingual('Choose where the money came from.', 'Piliin kung saan galing ang pera.'),
      PayProblem.badMethod => const Bilingual('Choose how it was paid.', 'Piliin kung paano ibinayad.'),
      PayProblem.creditRequired => const Bilingual('Choose the supplier credit to use.', 'Piliin ang credit ng supplier na gagamitin.'),
      PayProblem.overCredit => const Bilingual('That is more than the credit has left.', 'Mas malaki iyan sa natitirang credit.'),
    };

const paidNowLabel = Bilingual('Paid now?', 'Binayaran na ba?');
const paidFromLabel = Bilingual('Paid from', 'Saan galing ang pera');
const recordPaymentLabel = Bilingual('Record payment', 'Itala ang bayad');
const paymentsLabel = Bilingual('Payments', 'Mga bayad');
const myCashLabel = Bilingual('My cash', 'Pera ko');
const cashHeldLabel = Bilingual('Petty cash held', 'Hawak na petty cash');
const returnWaitingLabel = Bilingual('Return waiting for the owner', 'Ibinalik, hinihintay ang may-ari');
const companyOwesMeLabel = Bilingual('Company owes me', 'Utang ng kompanya sa akin');
const reportReturnLabel = Bilingual('Report a return', 'Iulat ang ibinalik');
const notReceivedLabel = Bilingual('I did not receive this', 'Hindi ko ito natanggap');
const waitingToSendPayLabel = Bilingual('Waiting to send', 'Hinihintay maipadala');

/// "Unreconciled shortfall ₱530 — paid beyond the petty cash recorded" (Q16).
Bilingual shortfallCopy(String amount) => Bilingual('Shortfall $amount — paid beyond the petty cash recorded. The owner checks it.',
    'Kulang na $amount — lumampas ang bayad sa petty cash na naitala. Susuriin ng may-ari.');

/// Q16: the warning before paying more petty cash than is on record — never a refusal.
Bilingual overspendCopy(String held, String amount) => Bilingual(
    'You hold $held of petty cash on record. This payment is $amount. It is saved, and the owner sees the difference as a shortfall to check.',
    'May hawak kang $held na petty cash sa tala. Ang bayad na ito ay $amount. Maitatala ito, at makikita ng may-ari ang kulang para suriin.');

/// Own money paid while it was not allowed (Q21) — kept, but the owner decides.
const ownMoneyToReviewCopy = Bilingual('Paid with your own money while it was not allowed: the owner reviews it before the company owes it.',
    'Binayaran ng sariling pera kahit hindi pinayagan: susuriin muna ng may-ari bago ito maging utang ng kompanya.');
