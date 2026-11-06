import '../../attendance/ui/attendance_copy.dart' show Bilingual;
import '../../attendance/ui/formats.dart' show clockTime, dayMonth;
import '../domain/tool_models.dart';

// As stock (Q22): English, with the Tagalog line underneath, on the key labels
// and every message. Screen titles and small field labels stay English.

const myToolsTitle = Bilingual('My tools', 'Mga tool na hawak ko');
const issueToolLabel = Bilingual('Issue a tool', 'Magpahiram ng tool');
const handoverLabel = Bilingual('Hand over', 'Ipasa sa iba');
const returnToolLabel = Bilingual('Return', 'Ibalik');
const reportLabel = Bilingual('Report a problem', 'Mag-ulat ng problema');
const undoLabel = Bilingual('Undo', 'I-undo');
const sendLabel = Bilingual('Send', 'Ipadala');
const findLabel = Bilingual('Find', 'Hanapin');
const toolsNeedSignal = Bilingual('Tools need signal. Pull down to try again.', 'Kailangan ng signal ang tools. Hilahin pababa para subukan ulit.');
const toolsOffNow = Bilingual('Tools are not switched on.', 'Hindi naka-on ang tools.');
const confirmToolLabel = Bilingual('This is the tool in my hand', 'Ito ang tool na hawak ko');
const lostPendingCopy = Bilingual('Reported lost — waiting for the owner.', 'Iniulat na nawala — hinihintay ang may-ari.');
const needsRepairStays = Bilingual('It needs repair, so it stays with them until the office marks it repaired. Return it instead.',
    'Kailangan itong ayusin, kaya mananatili ito sa kanila hanggang markahan ng opisina na naayos na. Ibalik na lang ito.');
const damagedAsksOwner = Bilingual('Damaged beyond repair: the owner decides whether to retire it. It can\'t be issued meanwhile.',
    'Sira na at hindi na maaayos: ang may-ari ang magpapasya kung itatabi na ito. Hindi ito maipapahiram habang hinihintay.');
const historyNeedsSignal = Bilingual('Its history needs signal.', 'Kailangan ng signal para makita ang kasaysayan nito.');
const officeFixes = Bilingual('A mistake you can\'t undo here? The office fixes it on Dacs Web (Requests → Tools).',
    'May mali na hindi ma-undo dito? Aayusin ito ng opisina sa Dacs Web (Requests → Tools).');

// Lost answers: the same words as stock (R101–R104).
const notSureLabel = Bilingual('Not sure this was recorded — the answer was lost. Send it again unchanged, check, or cancel it.',
    'Hindi sigurado kung naitala — nawala ang sagot. Ipadala ulit nang walang binago, i-check, o kanselahin.');
const sendAgainLabel = Bilingual('Send again', 'Ipadala ulit');
const checkLabel = Bilingual('Check', 'I-check');
const cancelLabel = Bilingual('Cancel it', 'Kanselahin');
const cancelChangeLabel = Bilingual('Cancel it and change', 'Kanselahin at baguhin');
const notYetCopy = Bilingual('Not recorded yet — it may still arrive. Send it again, or cancel it.',
    'Hindi pa naitatala — baka dumating pa. Ipadala ulit, o kanselahin.');
const finishFirst = Bilingual('First finish the tool record that is not sure (top of the Tools screen).',
    'Tapusin muna ang tool record na hindi sigurado (sa itaas ng Tools).');
const unreadableLabel = Bilingual(
    "A saved tool record on this phone is damaged — its details can't be read. Check whether it was recorded, or cancel it so it never records.",
    'May sirang tool record na naka-save sa phone na ito — hindi mabasa ang detalye. I-check kung naitala, o kanselahin para hindi na maitala.');
const unreadablePendingCopy = Bilingual('Not recorded yet — it may still arrive. Cancel it to settle it.',
    'Hindi pa naitatala — baka dumating pa. Kanselahin para matapos ito.');
const recoveryLabel = Bilingual(
    "Saved tool records on this phone can't be read. New tool records are paused on this phone — nothing was deleted. Ask the office for help before recording tools here.",
    'Hindi mabasa ang mga tool record na naka-save sa phone na ito. Nakahinto ang bagong tool record sa phone na ito — walang binura. Humingi ng tulong sa opisina bago magtala ng tools dito.');

/// A Send again refused while the first Send might still arrive.
Bilingual retryRefusedCopy(Bilingual refusal) => Bilingual('${refusal.english} The first Send may still arrive — check, or cancel it.',
    '${refusal.tagalog} Baka dumating pa ang unang pinadala — i-check, o kanselahin.');

Bilingual conditionCopy(ToolCondition c) => switch (c) {
      ToolCondition.good => const Bilingual('Good', 'Maayos'),
      ToolCondition.needsRepair => const Bilingual('Needs repair', 'Kailangang ayusin'),
      ToolCondition.missingParts => const Bilingual('Missing parts', 'Kulang ang piyesa'),
      ToolCondition.damaged => const Bilingual('Damaged beyond repair', 'Sira na, hindi na maaayos'),
    };

Bilingual problemCopy(ProblemKind k) => switch (k) {
      ProblemKind.dontHave => const Bilingual("I don't have this", 'Wala sa akin ito'),
      ProblemKind.broken => const Bilingual("It's broken", 'Sira ito'),
    };

const _kind = {
  'register': 'Registered',
  'issue': 'Issued',
  'handover': 'Handed over',
  'return': 'Returned',
  'repaired': 'Repaired',
  'lost': 'Reported lost',
  'found': 'Found',
  'retire': 'Retire request',
};

String recordKind(String kind) => _kind[kind] ?? kind;

/// A record's state, or null when it simply happened.
String? recordState({required String status, required bool reversed}) {
  if (reversed) return 'Undone';
  return switch (status) {
    'pending' => 'Waiting for the owner',
    'rejected' => 'Rejected',
    'withdrawn' => 'Withdrawn',
    _ => null,
  };
}

/// "6 Nov, 7:42 AM", Manila time.
String recordTime(DateTime? at) => at == null ? '' : '${dayMonth(at)}, ${clockTime(at)}';

/// "3 days", "since today".
String heldFor(int? days) => switch (days) {
      null => '',
      0 => 'since today',
      1 => '1 day',
      _ => '$days days',
    };
