import 'dart:async';
import 'dart:io';

import 'package:http/http.dart' as http;
import 'package:supabase_flutter/supabase_flutter.dart' show AuthRetryableFetchException;

import '../../attendance/ui/attendance_copy.dart' show Bilingual;

/// Every way a stock call from the phone can be refused (0104, 0105),
/// reduced to what the person can do about it. Anything unknown is
/// [unexpected], never a guess. Stock is online only (Q26): nothing is queued.
enum StockFailure {
  stockOff,
  notAllowed,
  toMatch,
  notWarehouse,
  notProject,
  moreThanAwaited,
  moreThanBought,
  moreThanIssued,
  notEnough,
  badReturn,
  badPlace,
  badItem,
  badProject,
  unplannedReasonRequired,
  requestExceeded,
  itemMismatch,
  unitMismatch,
  lineClosed,
  badRequestLink,
  badQuantity,
  badDate,
  badNote,
  reasonRequired,
  notFound,
  opCancelled,
  appUpdateRequired,
  sessionExpired,
  noConnection,
  unexpected;

  static const _byCode = <String, StockFailure>{
    'STOCK_OFF': stockOff,
    'NOT_OFFICE': notAllowed,
    'NOT_ALLOWED': notAllowed,
    'OWNER_ONLY': notAllowed,
    'TO_MATCH': toMatch,
    'NOT_WAREHOUSE': notWarehouse,
    'NOT_PROJECT': notProject,
    'MORE_THAN_AWAITED': moreThanAwaited,
    'MORE_THAN_BOUGHT': moreThanBought,
    'MORE_THAN_ISSUED': moreThanIssued,
    'NOT_ENOUGH': notEnough,
    'BAD_LOT': notEnough,
    'BAD_RETURN': badReturn,
    'BAD_LOCATION': badPlace,
    'BAD_ITEM': badItem,
    'BAD_PROJECT': badProject,
    'UNPLANNED_REASON_REQUIRED': unplannedReasonRequired,
    'REQUEST_EXCEEDED': requestExceeded,
    'ITEM_MISMATCH': itemMismatch,
    'UNIT_MISMATCH': unitMismatch,
    'LINE_CLOSED': lineClosed,
    'BAD_REQUEST_LINK': badRequestLink,
    'BAD_PORTION': badRequestLink,
    'BAD_QUANTITY': badQuantity,
    'BAD_DATE': badDate,
    'BAD_NOTE': badNote,
    'REASON_REQUIRED': reasonRequired,
    'NOT_FOUND': notFound,
    'BAD_STATE': notFound,
    'BAD_OP': unexpected,
    'OP_CANCELLED': opCancelled,
    'APP_UPDATE_REQUIRED': appUpdateRequired,
    'AUTH_REQUIRED': sessionExpired,
  };

  static StockFailure of(Object error) {
    if (error is StockFailureException) return error.failure;
    if (error is IOException || error is TimeoutException || error is http.ClientException || error is AuthRetryableFetchException) {
      return noConnection;
    }
    // Whole codes only: REASON_REQUIRED is part of longer codes.
    for (final m in RegExp(r'[A-Z][A-Z_]{2,}[A-Z]').allMatches(error.toString())) {
      final f = _byCode[m.group(0)];
      if (f != null) return f;
    }
    return unexpected;
  }

  /// Worth pressing Send again (the same operation id, so it records once).
  bool get retryable => this == noConnection || this == sessionExpired || this == unexpected;

  /// The answer was lost: the server may or may not have recorded it, so the
  /// submission is kept, unchanged, until resolved (R101). Every other
  /// failure is the server's (or the phone's, before sending) clear "no".
  bool get uncertain => this == noConnection || this == unexpected;
}

/// A refusal decided on the phone (no server code to read).
class StockFailureException implements Exception {
  const StockFailureException(this.failure);
  final StockFailure failure;
  @override
  String toString() => 'StockFailureException(${failure.name})';
}

/// English, then Tagalog (Q22) — the same meaning as the web's words.
Bilingual stockFailureCopy(StockFailure f) => switch (f) {
      StockFailure.stockOff => const Bilingual(
          'Stock is not switched on yet. The owner switches it on at launch.', 'Hindi pa naka-on ang stock. Bubuksan ito ng may-ari sa launch.'),
      StockFailure.notAllowed => const Bilingual(
          'Your account cannot record stock. Ask the owner.', 'Hindi puwedeng magtala ng stock ang account mo. Itanong sa may-ari.'),
      StockFailure.toMatch => const Bilingual(
          'The office has to match this purchase line to a catalogue item first (Dacs Web → Stock → Receiving).',
          'Kailangan munang itugma ng opisina ang linyang ito sa item sa catalogue.'),
      StockFailure.notWarehouse => const Bilingual(
          'That purchase line is for a project, not the warehouse. Record its leftovers instead.',
          'Para sa project ang linyang iyon, hindi sa bodega. Itala na lang ang natira.'),
      StockFailure.notProject => const Bilingual(
          'That purchase line is for the warehouse — it becomes stock by being received.',
          'Para sa bodega ang linyang iyon — nagiging stock ito kapag natanggap.'),
      StockFailure.moreThanAwaited => const Bilingual(
          'That is more than is still awaited on this line.', 'Mas marami iyan sa hinihintay pa sa linyang ito.'),
      StockFailure.moreThanBought => const Bilingual(
          'That is more than this purchase line brought (counting what is already stock).',
          'Mas marami iyan sa nabili sa linyang ito (kasama ang naitala nang stock).'),
      StockFailure.moreThanIssued => const Bilingual(
          'That is more than this issue sent and has not had back.', 'Mas marami iyan sa naipadala at hindi pa naibabalik.'),
      StockFailure.notEnough => const Bilingual(
          'There is not that much there. Refresh and check the quantity.', 'Wala nang ganoon karami doon. I-refresh at suriin ang dami.'),
      StockFailure.badReturn => const Bilingual(
          'Only a live issue from the warehouse can be returned.', 'Ang naipadala lang mula sa bodega ang puwedeng ibalik.'),
      StockFailure.badPlace => const Bilingual(
          'Choose where the goods are and where they go — two different places.',
          'Piliin kung nasaan ang gamit at saan dadalhin — dalawang magkaibang lugar.'),
      StockFailure.badItem => const Bilingual('Choose a catalogue item.', 'Pumili ng item sa catalogue.'),
      StockFailure.badProject => const Bilingual('Choose one of your projects.', 'Pumili ng isa sa mga project.'),
      StockFailure.unplannedReasonRequired => const Bilingual(
          'Goods going to a project fill a request, or say why they are needed.',
          'Ang gamit na dadalhin sa project ay para sa isang request, o sabihin kung bakit kailangan.'),
      StockFailure.requestExceeded => const Bilingual(
          'That is more than the request still needs. Send the rest separately, as unplanned with a reason.',
          'Sobra iyan sa kailangan pa ng request. Ipadala ang sobra nang hiwalay, may dahilan.'),
      StockFailure.itemMismatch => const Bilingual(
          'That request is for a different catalogue item.', 'Ibang item sa catalogue ang request na iyon.'),
      StockFailure.unitMismatch => const Bilingual(
          'That request uses another unit. Send it as unplanned with a reason.',
          'Ibang unit ang request na iyon. Ipadala bilang hindi planado, may dahilan.'),
      StockFailure.lineClosed => const Bilingual('That request was cancelled.', 'Kinansela ang request na iyon.'),
      StockFailure.badRequestLink => const Bilingual(
          'That request belongs to another project. Refresh and choose again.', 'Sa ibang project ang request na iyon. I-refresh at pumili ulit.'),
      StockFailure.badQuantity => const Bilingual(
          'Enter a quantity above 0 (at most 3 decimals).', 'Ilagay ang dami na higit sa 0 (hanggang 3 decimal).'),
      StockFailure.badDate => const Bilingual('Pick a date that has happened.', 'Pumili ng petsang lumipas na.'),
      StockFailure.badNote => const Bilingual(
          'That note is too long (300 characters at most).', 'Masyadong mahaba ang tala (hanggang 300 letra).'),
      StockFailure.reasonRequired => const Bilingual('Please give a reason.', 'Magbigay ng dahilan.'),
      StockFailure.notFound => const Bilingual(
          'That changed in the meantime. Refresh and try again.', 'Nagbago iyon. I-refresh at subukan ulit.'),
      StockFailure.opCancelled => const Bilingual(
          'This record was cancelled — nothing was recorded. Change it if needed and send it as a new one.',
          'Kinansela ang record na ito — walang naitala. Baguhin kung kailangan at ipadala bilang bago.'),
      StockFailure.appUpdateRequired => const Bilingual('Update WorkMate to send this.', 'I-update ang WorkMate para maipadala ito.'),
      StockFailure.sessionExpired => const Bilingual('Sign in again to send this.', 'Mag-sign in ulit para maipadala ito.'),
      StockFailure.noConnection => const Bilingual(
          'Stock needs signal. Press Send again when you are online — it is never recorded twice.',
          'Kailangan ng signal ang stock. Pindutin ulit ang Send kapag online ka na — hindi ito maitatala nang dalawang beses.'),
      StockFailure.unexpected => const Bilingual('Something went wrong. Try again.', 'May nasira. Subukan ulit.'),
    };
