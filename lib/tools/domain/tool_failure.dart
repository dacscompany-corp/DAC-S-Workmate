import 'dart:async';
import 'dart:io';

import 'package:http/http.dart' as http;
import 'package:supabase_flutter/supabase_flutter.dart' show AuthRetryableFetchException;

import '../../attendance/ui/attendance_copy.dart' show Bilingual;

/// Every way a tools call from the phone can be refused (0107, 0111),
/// reduced to what the person can do about it. Anything unknown is
/// [unexpected], never a guess.
enum ToolFailure {
  toolsOff,
  notCrew,
  notLeader,
  notYourTeam,
  notYourTool,
  notAvailable,
  notIssued,
  needsRepair,
  sameHolder,
  requestNeedsOffice,
  badRequestLink,
  lineClosed,
  badPerson,
  badProject,
  projectCompleted,
  badCondition,
  badKind,
  alreadyReported,
  notYours,
  laterRecords,
  badState,
  notFound,
  badNote,
  reasonRequired,

  /// The phone's own: no tool found by its number yet.
  noTool,

  /// The phone's own: the leader hasn't confirmed it is the tool in their hand.
  notConfirmed,
  opCancelled,
  appUpdateRequired,
  sessionExpired,
  noConnection,
  unexpected;

  static const _byCode = <String, ToolFailure>{
    'TOOLS_OFF': toolsOff,
    'NOT_A_REQUESTER': notCrew,
    'NOT_LEADER': notLeader,
    'NOT_YOUR_TEAM': notYourTeam,
    'NOT_YOUR_TOOL': notYourTool,
    'TOOL_NOT_AVAILABLE': notAvailable,
    'NOT_AVAILABLE': notAvailable,
    'NOT_ISSUED': notIssued,
    'NEEDS_REPAIR': needsRepair,
    'SAME_HOLDER': sameHolder,
    'REQUEST_NEEDS_OFFICE': requestNeedsOffice,
    'BAD_REQUEST_LINK': badRequestLink,
    'NOT_A_TOOL_LINE': badRequestLink,
    'ITEM_MISMATCH': badRequestLink,
    'UNIT_MISMATCH': badRequestLink,
    'LINE_CLOSED': lineClosed,
    'BAD_PERSON': badPerson,
    'PERSON_REQUIRED': badPerson,
    'BAD_PROJECT': badProject,
    'PROJECT_COMPLETED': projectCompleted,
    'BAD_CONDITION': badCondition,
    'BAD_KIND': badKind,
    'ALREADY_REPORTED': alreadyReported,
    'NOT_YOURS': notYours,
    'LATER_RECORDS': laterRecords,
    'BAD_STATE': badState,
    'NOT_FOUND': notFound,
    'BAD_NOTE': badNote,
    'REASON_REQUIRED': reasonRequired,
    'BAD_OP': unexpected,
    'OP_CANCELLED': opCancelled,
    'APP_UPDATE_REQUIRED': appUpdateRequired,
    'AUTH_REQUIRED': sessionExpired,
  };

  static ToolFailure of(Object error) {
    if (error is ToolFailureException) return error.failure;
    if (error is IOException || error is TimeoutException || error is http.ClientException || error is AuthRetryableFetchException) {
      return noConnection;
    }
    // Whole codes only: NOT_YOURS is part of no other code, but NOT_YOUR_TOOL
    // and NOT_YOUR_TEAM must never read as it.
    for (final m in RegExp(r'[A-Z][A-Z_]{2,}[A-Z]').allMatches(error.toString())) {
      final f = _byCode[m.group(0)];
      if (f != null) return f;
    }
    return unexpected;
  }

  /// The answer was lost: the server may or may not have recorded it, so the
  /// submission is kept, unchanged, until resolved (Q22). Every other
  /// failure is the server's (or the phone's, before sending) clear "no".
  bool get uncertain => this == noConnection || this == unexpected;
}

/// A refusal decided on the phone (no server code to read).
class ToolFailureException implements Exception {
  const ToolFailureException(this.failure);
  final ToolFailure failure;
  @override
  String toString() => 'ToolFailureException(${failure.name})';
}

/// English, then Tagalog — the same meaning as the web's words.
Bilingual toolFailureCopy(ToolFailure f) => switch (f) {
      ToolFailure.toolsOff => const Bilingual('Tools are not switched on yet.', 'Hindi pa naka-on ang tools.'),
      ToolFailure.notCrew => const Bilingual(
          'Tools here are for workers and team leaders.', 'Para sa mga worker at team leader ang tools dito.'),
      ToolFailure.notLeader => const Bilingual("You're not leading a team right now. The office names team leaders.",
          'Hindi ka nangunguna sa isang team ngayon. Ang opisina ang pumipili ng team leader.'),
      ToolFailure.notYourTeam => const Bilingual('Only for people in the teams you lead. Ask the office.',
          'Para lang sa mga tao sa mga team na pinangungunahan mo. Itanong sa opisina.'),
      ToolFailure.notYourTool => const Bilingual("That tool isn't with you now. Pull down to refresh.",
          'Wala na sa iyo ang tool na iyan. Hilahin pababa para i-refresh.'),
      ToolFailure.notAvailable => const Bilingual('Not available to issue — check the number, or ask the office.',
          'Hindi puwedeng ipahiram — suriin ang numero, o itanong sa opisina.'),
      ToolFailure.notIssued => const Bilingual("That tool isn't out with anyone now. Pull down to refresh.",
          'Wala nang may hawak ng tool na iyan. Hilahin pababa para i-refresh.'),
      ToolFailure.needsRepair => const Bilingual(
          'A tool that needs repair stays with its person until the office marks it repaired. Return it instead.',
          'Ang tool na kailangang ayusin ay mananatili sa may hawak hanggang markahan ng opisina na naayos na. Ibalik na lang ito.'),
      ToolFailure.sameHolder => const Bilingual('They already have it on that project. Choose another person or project.',
          'Nasa kanila na ito sa project na iyan. Pumili ng ibang tao o project.'),
      ToolFailure.requestNeedsOffice => const Bilingual(
          'The office links that request on Dacs Web. Issue it without the request, or ask the office.',
          'Ang opisina ang magli-link ng request na iyan sa Dacs Web. Ipahiram nang walang request, o itanong sa opisina.'),
      ToolFailure.badRequestLink => const Bilingual("That request can't take this tool. Choose again, or issue it without a request.",
          'Hindi puwede ang tool na ito sa request na iyan. Pumili ulit, o ipahiram nang walang request.'),
      ToolFailure.lineClosed => const Bilingual(
          'That request was closed or cancelled. Choose again, or issue it without a request.',
          'Isinara o kinansela na ang request na iyan. Pumili ulit, o ipahiram nang walang request.'),
      ToolFailure.badPerson => const Bilingual('Choose someone from your team.', 'Pumili ng tao mula sa team mo.'),
      ToolFailure.badProject => const Bilingual('Choose one of the projects.', 'Pumili ng isa sa mga project.'),
      ToolFailure.projectCompleted => const Bilingual(
          'That project is completed. Choose an open one.', 'Tapos na ang project na iyan. Pumili ng bukas pa.'),
      ToolFailure.badCondition => const Bilingual("Choose the tool's condition.", 'Piliin ang kondisyon ng tool.'),
      ToolFailure.badKind => const Bilingual("Choose what's wrong.", 'Piliin kung ano ang problema.'),
      ToolFailure.alreadyReported =>
        const Bilingual('Already reported — the office will check it.', 'Naiulat na ito — titingnan ito ng opisina.'),
      ToolFailure.notYours => const Bilingual(
          'Only the person who recorded it can undo it here. Ask the office.', 'Ang nagtala lang ang puwedeng mag-undo nito dito. Itanong sa opisina.'),
      ToolFailure.laterRecords => const Bilingual(
          "Something was recorded on this tool after it, so it can't be undone here. Ask the office.",
          'May naitala sa tool na ito pagkatapos, kaya hindi ito ma-undo dito. Itanong sa opisina.'),
      ToolFailure.badState => const Bilingual("That can't be undone here. Ask the office.", 'Hindi ito ma-undo dito. Itanong sa opisina.'),
      ToolFailure.notFound => const Bilingual('That changed in the meantime. Refresh and try again.', 'Nagbago iyon. I-refresh at subukan ulit.'),
      ToolFailure.badNote => const Bilingual('That note is too long (300 characters at most).', 'Masyadong mahaba ang tala (hanggang 300 letra).'),
      ToolFailure.reasonRequired => const Bilingual('Please give a reason.', 'Magbigay ng dahilan.'),
      ToolFailure.noTool => const Bilingual(
          "Type the tool's number and press Find.", 'I-type ang numero ng tool at pindutin ang Hanapin.'),
      ToolFailure.notConfirmed => const Bilingual(
          'Check the tool in your hand, then tick the box to confirm it.', 'Tingnan ang tool na hawak mo, saka i-tsek ang kahon para kumpirmahin.'),
      ToolFailure.opCancelled => const Bilingual(
          'This record was cancelled — nothing was recorded. Change it if needed and send it as a new one.',
          'Kinansela ang record na ito — walang naitala. Baguhin kung kailangan at ipadala bilang bago.'),
      ToolFailure.appUpdateRequired => const Bilingual('Update WorkMate to send this.', 'I-update ang WorkMate para maipadala ito.'),
      ToolFailure.sessionExpired => const Bilingual('Sign in again to send this.', 'Mag-sign in ulit para maipadala ito.'),
      ToolFailure.noConnection => const Bilingual(
          'Tools need signal. Press Send again when you are online — it is never recorded twice.',
          'Kailangan ng signal ang tools. Pindutin ulit ang Send kapag online ka na — hindi ito maitatala nang dalawang beses.'),
      ToolFailure.unexpected => const Bilingual('Something went wrong. Try again.', 'May nasira. Subukan ulit.'),
    };
