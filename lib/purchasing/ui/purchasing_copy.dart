import 'package:flutter/material.dart';

import '../../attendance/ui/attendance_copy.dart' show Bilingual;
import '../../requests/domain/quantity.dart';
import '../../ui/theme.dart';
import '../domain/purchase_draft.dart';

// Q22: English, with the Tagalog line underneath, on the key labels and
// every message. Screen titles and small field labels stay English.

const stillToBuyLabel = Bilingual('Still to buy', 'Kulang pang bilhin');
const neededLabel = Bilingual('Needed', 'Kailangan');
const boughtLabel = Bilingual('Bought', 'Nabili');
const mineLabel = Bilingual('Mine', 'Akin');
const unassignedLabel = Bilingual('Unassigned', 'Wala pang bibili');
const othersLabel = Bilingual('Other buyers', 'Ibang bibili');
const claimLabel = Bilingual("I'll buy this", 'Ako ang bibili');
const releaseLabel = Bilingual('Release', 'Bitawan');
const arrangedLabel = Bilingual('Mark arranged', 'Naayos na');
const notArrangedLabel = Bilingual('Not arranged', 'Hindi pa naayos');
const recordLabel = Bilingual('Record purchase', 'Itala ang binili');
const noReceiptLabel = Bilingual('No receipt', 'Walang resibo');
const waitingLabel = Bilingual('Waiting to send', 'Hinihintay maipadala');

/// R38: the server has it; the list shown was read before it went (offline).
const sentLabel = Bilingual('Sent — shows in the list when it next updates', 'Naipadala na — lalabas sa listahan sa susunod na update');
const attentionLabel = Bilingual('Needs attention', 'Kailangang ayusin');
const needsSignal = Bilingual('This needs signal. Try again when you are online.', 'Kailangan ng signal. Subukan ulit kapag online ka na.');

/// What to do about each problem, next to its field (Q22: both languages).
Bilingual problemCopy(ProblemKind k) => switch (k) {
      ProblemKind.badDate => const Bilingual('Pick the date you bought it.', 'Piliin ang petsa ng pagbili.'),
      ProblemKind.noLines => const Bilingual('Add at least one item.', 'Magdagdag ng kahit isang item.'),
      ProblemKind.tooManyLines =>
        const Bilingual('Split this into two purchases (50 items at most).', 'Hatiin sa dalawang purchase (hanggang 50 item).'),
      ProblemKind.badName => const Bilingual('Name the item.', 'Pangalanan ang item.'),
      ProblemKind.badQuantity => const Bilingual('Enter a quantity above 0 (up to 3 decimals).', 'Ilagay ang dami na higit sa 0.'),
      ProblemKind.badAmount => const Bilingual('Enter the amount paid for this item.', 'Ilagay ang halagang ibinayad sa item na ito.'),
      ProblemKind.noProject => const Bilingual('Choose the project, the job or the warehouse.', 'Piliin ang project, trabaho o bodega.'),
      ProblemKind.extraReasonRequired =>
        const Bilingual('More than still needed: say why, and where the extra goes.', 'Sobra sa kailangan: sabihin kung bakit, at saan ilalagay ang sobra.'),
      ProblemKind.nameDiffers => const Bilingual('The name differs from the request. Is it the same item in other words, or a substitute?',
          'Iba ang pangalan sa request. Pareho bang item sa ibang salita, o pamalit?'),
      ProblemKind.substituteReasonRequired =>
        const Bilingual('Say why a substitute was bought.', 'Sabihin kung bakit pamalit ang binili.'),
      ProblemKind.unitNoteRequired => const Bilingual('A different unit from the request: say how much it covers (e.g. 1 box = 12 pc).',
          'Ibang unit sa request: sabihin kung gaano karami ito (hal. 1 box = 12 pc).'),
      ProblemKind.unplannedReasonRequired =>
        const Bilingual('No request for this item: say why it was bought.', 'Walang request ang item na ito: sabihin kung bakit binili.'),
      ProblemKind.badChargeAmount => const Bilingual('Enter the amount.', 'Ilagay ang halaga.'),
      ProblemKind.splitMismatch =>
        const Bilingual('The shares must add up to the amount, one per item.', 'Dapat tugma ang kabuuan ng hati sa halaga.'),
      ProblemKind.noReceipt =>
        const Bilingual('Add a receipt photo, or tap No receipt and say why.', 'Maglagay ng litrato ng resibo, o pindutin ang Walang resibo at sabihin kung bakit.'),
      ProblemKind.noReceiptReason => const Bilingual('Say why there is no receipt.', 'Sabihin kung bakit walang resibo.'),
      ProblemKind.badTotal => const Bilingual('Enter the total printed on the receipt.', 'Ilagay ang total na nakasulat sa resibo.'),
      ProblemKind.totalMismatch => const Bilingual('Items + fees − discounts do not match the receipt total.',
          'Hindi tugma ang items + bayad − diskwento sa total ng resibo.'),
      ProblemKind.paidAmount => const Bilingual('Enter how much was paid now.', 'Ilagay kung magkano ang ibinayad ngayon.'),
      ProblemKind.partNotLess => const Bilingual('A part payment is less than the receipt total. Choose Paid in full instead.',
          'Ang bahagyang bayad ay mas mababa sa total ng resibo. Piliin ang Bayad nang buo.'),
      ProblemKind.personRequired => const Bilingual('Petty cash and own money are for staff buyers. Choose Company.',
          'Ang petty cash at sariling pera ay para sa staff na bumibili. Piliin ang Kompanya.'),
      ProblemKind.badPaySource => const Bilingual('Choose where the money came from.', 'Piliin kung saan galing ang pera.'),
      ProblemKind.creditRequired => const Bilingual('Choose the supplier credit to use.', 'Piliin ang credit ng supplier na gagamitin.'),
      ProblemKind.overCredit => const Bilingual('That is more than the credit has left.', 'Mas malaki iyan sa natitirang credit.'),
    };

/// The four receipt slots, as the Purchasing tab names them.
const receiptSlotLabels = {
  'supplier_invoice_url': 'Supplier invoice / official receipt',
  'payment_receipt_url': 'Payment receipt',
  'delivery_receipt_url': 'Delivery receipt',
  'po_image_url': 'Purchase order',
};

/// "₱1,250.50".
String peso(num v) {
  final fixed = v.toStringAsFixed(2);
  final parts = fixed.split('.');
  final whole = parts[0].replaceAllMapped(RegExp(r'\B(?=(\d{3})+(?!\d))'), (_) => ',');
  return '₱$whole.${parts[1]}';
}

/// "6 bag".
String qtyUnit(num v, String unit) => unit.trim().isEmpty ? formatQuantity(v) : '${formatQuantity(v)} ${unit.trim()}';

/// A label in English with its Tagalog line under it.
class BilingualText extends StatelessWidget {
  const BilingualText(this.text, {super.key, this.style, this.align = CrossAxisAlignment.start});
  final Bilingual text;
  final TextStyle? style;
  final CrossAxisAlignment align;

  @override
  Widget build(BuildContext context) => Column(crossAxisAlignment: align, mainAxisSize: MainAxisSize.min, children: [
        Text(text.english, style: style ?? const TextStyle(fontWeight: FontWeight.w700)),
        Text(text.tagalog, style: const TextStyle(fontSize: 11.5, color: WmColors.textMuted)),
      ]);
}

/// A button whose label is bilingual.
Widget bilingualButton(Bilingual label, VoidCallback? onPressed, {bool filled = false, Key? key}) {
  final child = Padding(
    padding: const EdgeInsets.symmetric(vertical: 4),
    child: Column(mainAxisSize: MainAxisSize.min, children: [
      Text(label.english, style: const TextStyle(fontWeight: FontWeight.w800)),
      Text(label.tagalog, style: const TextStyle(fontSize: 11, fontWeight: FontWeight.w400)),
    ]),
  );
  return filled
      ? FilledButton(key: key, onPressed: onPressed, style: FilledButton.styleFrom(minimumSize: const Size(0, 52)), child: child)
      : OutlinedButton(key: key, onPressed: onPressed, child: child);
}
