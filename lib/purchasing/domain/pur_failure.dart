import 'dart:async';
import 'dart:io';

import 'package:http/http.dart' as http;
import 'package:supabase_flutter/supabase_flutter.dart' show AuthRetryableFetchException;

import '../../attendance/ui/attendance_copy.dart' show Bilingual;

/// Every way a purchasing call can be refused (0096, 0097, 0101), reduced to
/// what the buyer can do about it. Anything unknown is [unexpected], never a
/// guess.
enum PurFailure {
  /// BUYER_REQUIRED (and the account checks before it): the Buyer switch is off (R2).
  buyingOff,
  completedProject,
  ownerApprovalNeeded,
  lineClosed,
  assignedToOther,
  notYourPortion,
  nothingToBuy,
  reductionPending,
  requestLinkChanged,
  extraReasonRequired,
  unplannedReasonRequired,
  substituteReasonRequired,
  splitMismatch,
  discountTooLarge,
  totalMismatch,
  badProject,
  badSupplier,
  noReceipt,
  notFound,
  alreadyVoided,
  linesChanged,
  alreadyPending,
  reasonRequired,
  invalid,

  /// A receipt photo of an unsent purchase is no longer on the phone.
  photoMissing,

  /// The company to file receipts under is not known yet (needs signal).
  noCompany,
  appUpdateRequired,
  sessionExpired,
  noConnection,
  unexpected;

  static const _byCode = <String, PurFailure>{
    'BUYER_REQUIRED': buyingOff,
    'NOT_OFFICE': buyingOff,
    'NOT_ALLOWED': buyingOff,
    'OFFICE_ONLY': buyingOff,
    'COMPLETED_PROJECT': completedProject,
    'OWNER_APPROVAL_NEEDED': ownerApprovalNeeded,
    'LINE_CLOSED': lineClosed,
    'ASSIGNED_TO_OTHER': assignedToOther,
    'NOT_YOUR_PORTION': notYourPortion,
    'NOTHING_TO_BUY': nothingToBuy,
    'REDUCTION_PENDING': reductionPending,
    'BAD_REQUEST_LINK': requestLinkChanged,
    'BAD_PORTION': requestLinkChanged,
    'EXTRA_REASON_REQUIRED': extraReasonRequired,
    'UNPLANNED_REASON_REQUIRED': unplannedReasonRequired,
    'SUBSTITUTE_REASON_REQUIRED': substituteReasonRequired,
    'SPLIT_MISMATCH': splitMismatch,
    'DISCOUNT_TOO_LARGE': discountTooLarge,
    'TOTAL_MISMATCH': totalMismatch,
    'BAD_PROJECT': badProject,
    'BAD_DESTINATION': badProject,
    'AW_NO_PERIOD': badProject,
    'BAD_SUPPLIER': badSupplier,
    'NO_RECEIPT': noReceipt,
    'NOT_FOUND': notFound,
    'BAD_STATE': alreadyVoided,
    'LINES_CHANGED': linesChanged,
    'ALREADY_PENDING': alreadyPending,
    'REASON_REQUIRED': reasonRequired,
    'BAD_DATE': invalid,
    'BAD_AMOUNT': invalid,
    'BAD_LINES': invalid,
    'BAD_CHARGES': invalid,
    'BAD_QUANTITY': invalid,
    'BAD_NAME': invalid,
    'BAD_EXTRA': invalid,
    'BAD_DOCS': invalid,
    'BAD_REASON': invalid,
    'BAD_BUYER': invalid,
    'BAD_SOURCE': invalid,
    'BAD_KIND': invalid,
    'BAD_OP': invalid,
    'PHOTO_MISSING': photoMissing,
    'NO_COMPANY': noCompany,
    'APP_UPDATE_REQUIRED': appUpdateRequired,
    'AUTH_REQUIRED': sessionExpired,
  };

  static PurFailure of(Object error) {
    if (error is PurFailureException) return error.failure;
    if (error is IOException ||
        error is TimeoutException ||
        error is http.ClientException ||
        error is AuthRetryableFetchException) {
      return noConnection;
    }
    // Whole codes only: REASON_REQUIRED is part of three longer codes.
    for (final m in RegExp(r'[A-Z][A-Z_]{2,}[A-Z]').allMatches(error.toString())) {
      final f = _byCode[m.group(0)];
      if (f != null) return f;
    }
    return unexpected;
  }

  /// A stored failure name back to the failure.
  static PurFailure fromStored(String? name) => values.where((f) => f.name == name).firstOrNull ?? unexpected;

  /// Worth sending again later: the connection, the session or the moment —
  /// never the purchase's own content, which would be refused again.
  bool get retryable => switch (this) {
        noConnection || sessionExpired || appUpdateRequired || noCompany || unexpected => true,
        _ => false,
      };

  /// Only these count toward [maxPurchaseAttempts]: waiting for signal, a
  /// session or an update never gives a purchase up.
  bool get countsTowardCap => this == unexpected;
}

/// An [unexpected] failure this many times in a row stops being retried, so
/// one bad purchase cannot block the queue forever. It stays on the phone.
const maxPurchaseAttempts = 10;

/// A failure decided on the phone (no server code to read).
class PurFailureException implements Exception {
  const PurFailureException(this.failure);
  final PurFailure failure;
  @override
  String toString() => 'PurFailureException(${failure.name})';
}

/// English, then Tagalog (Q22).
Bilingual purFailureCopy(PurFailure f) => switch (f) {
      PurFailure.buyingOff => const Bilingual(
          'Buying is turned off for your account.', 'Naka-off ang pagbili sa account mo.'),
      PurFailure.completedProject => const Bilingual(
          'That project is completed. Only the owner can change it: send it to the owner.',
          'Tapos na ang project na iyon. Ang may-ari lang ang puwedeng magbago: ipadala sa may-ari.'),
      PurFailure.ownerApprovalNeeded => const Bilingual(
          'Only the owner can make this change: send it to the owner.',
          'Ang may-ari lang ang puwedeng gumawa ng pagbabagong ito: ipadala sa may-ari.'),
      PurFailure.lineClosed => const Bilingual(
          'That request was cancelled. Remove it from this purchase, or record it as unplanned.',
          'Kinansela ang request na iyon. Alisin ito sa purchase, o itala bilang hindi planado.'),
      PurFailure.assignedToOther => const Bilingual(
          'Another buyer has that item now. Refresh the list.', 'May ibang bumibili na niyan. I-refresh ang listahan.'),
      PurFailure.notYourPortion => const Bilingual(
          'Only the buyer who has it can release it.', 'Ang bumibili lang nito ang puwedeng mag-release.'),
      PurFailure.nothingToBuy => const Bilingual(
          'Nothing is left to buy on that item. Refresh the list.', 'Wala nang kulang na bibilhin diyan. I-refresh ang listahan.'),
      PurFailure.reductionPending => const Bilingual(
          'The office is checking a smaller quantity on this item. Try again later.',
          'Sinusuri ng opisina ang binawasang dami nito. Subukan ulit mamaya.'),
      PurFailure.requestLinkChanged => const Bilingual(
          'The request changed since you picked it. Refresh the list and record again.',
          'Nagbago ang request mula nang piliin mo. I-refresh ang listahan at itala ulit.'),
      PurFailure.extraReasonRequired => const Bilingual(
          'You bought more than is still needed. Say why, and where the extra goes.',
          'Sobra ang nabili sa kailangan. Sabihin kung bakit, at saan mapupunta ang sobra.'),
      PurFailure.unplannedReasonRequired => const Bilingual(
          'An item with no request needs a reason.', 'Kailangan ng dahilan ang item na walang request.'),
      PurFailure.substituteReasonRequired => const Bilingual(
          'A substitute needs a reason.', 'Kailangan ng dahilan ang pamalit.'),
      PurFailure.splitMismatch => const Bilingual(
          'The fee or discount split does not add up. Check the shares.',
          'Hindi tugma ang hati ng bayad o diskwento. Suriin ang mga hati.'),
      PurFailure.discountTooLarge => const Bilingual(
          'A discount is bigger than the item it is on. Check the split.',
          'Mas malaki ang diskwento kaysa sa item. Suriin ang hati.'),
      PurFailure.totalMismatch => const Bilingual(
          'The lines, fees and discounts do not add up to the receipt total.',
          'Hindi tugma ang kabuuan ng mga item, bayad at diskwento sa total ng resibo.'),
      PurFailure.badProject => const Bilingual(
          'That project or job is no longer open. Choose another.', 'Sarado na ang project o trabahong iyon. Pumili ng iba.'),
      PurFailure.badSupplier => const Bilingual(
          'That supplier is no longer on the list. Choose another or type the name.',
          'Wala na sa listahan ang supplier na iyon. Pumili ng iba o i-type ang pangalan.'),
      PurFailure.noReceipt => const Bilingual(
          'Add a receipt photo, or tap No receipt and say why.', 'Maglagay ng litrato ng resibo, o pindutin ang Walang resibo at sabihin kung bakit.'),
      PurFailure.notFound => const Bilingual(
          'That is no longer there. Refresh and try again.', 'Wala na iyon. I-refresh at subukan ulit.'),
      PurFailure.alreadyVoided => const Bilingual(
          'That purchase is no longer recorded (it was voided or replaced).',
          'Hindi na nakatala ang purchase na iyon (na-void o napalitan).'),
      PurFailure.linesChanged => const Bilingual(
          'The purchase changed on the office side. Open it again.', 'Nagbago ang purchase sa opisina. Buksan ulit.'),
      PurFailure.alreadyPending => const Bilingual(
          'A change for this purchase is already waiting for the owner.', 'May pagbabago nang naghihintay sa may-ari para dito.'),
      PurFailure.reasonRequired => const Bilingual(
          'Say why you are changing it.', 'Sabihin kung bakit mo ito binabago.'),
      PurFailure.invalid => const Bilingual(
          'Something on the purchase is not filled in correctly. Check each line.',
          'May mali sa pagkakapuno ng purchase. Suriin ang bawat linya.'),
      PurFailure.photoMissing => const Bilingual(
          'A receipt photo is no longer on this phone. Take it again.', 'Wala na sa phone ang litrato ng resibo. Kunan ulit.'),
      PurFailure.noCompany => const Bilingual(
          'Connect to the internet once so WorkMate can file your receipts.',
          'Kumonekta muna sa internet para mai-file ng WorkMate ang mga resibo mo.'),
      PurFailure.appUpdateRequired => const Bilingual(
          'Update WorkMate to send this.', 'I-update ang WorkMate para maipadala ito.'),
      PurFailure.sessionExpired => const Bilingual(
          'Sign in again to send this.', 'Mag-sign in ulit para maipadala ito.'),
      PurFailure.noConnection => const Bilingual(
          'No signal right now. Try again in a moment.', 'Walang signal ngayon. Subukan ulit mamaya.'),
      PurFailure.unexpected => const Bilingual(
          'Something went wrong. Try again.', 'May nasira. Subukan ulit.'),
    };
