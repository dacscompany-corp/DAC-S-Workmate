import '../../attendance/ui/attendance_copy.dart' show Bilingual;
import '../../requests/domain/quantity.dart';
import '../domain/stock_models.dart';

// Q22: English, with the Tagalog line underneath, on the key labels and every
// message. Screen titles and small field labels stay English.

const stockTitle = Bilingual('Stock', 'Stock sa bodega at site');
const issueMoveLabel = Bilingual('Issue / move', 'Ipadala / ilipat');
const issueFromStockLabel = Bilingual('Issue from stock', 'Kunin sa bodega');
const leftoversLabel = Bilingual('Record leftovers', 'Itala ang natira');
const receivedLabel = Bilingual('Received…', 'Natanggap…');
const returnLabel = Bilingual('Return…', 'Ibalik…');
const sendLabel = Bilingual('Send', 'Ipadala');
const fromStockLabel = Bilingual('From stock', 'Galing sa stock');
const stockNeedsSignal =
    Bilingual('Stock needs signal. Pull down to try again.', 'Kailangan ng signal ang stock. Hilahin pababa para subukan ulit.');
const stockOffNow = Bilingual('Stock is not switched on.', 'Hindi naka-on ang stock.');
const notMatchedYet = Bilingual('Not matched yet — the office matches it on Dacs Web; it becomes stock then.',
    'Hindi pa naitutugma — itutugma ng opisina sa Dacs Web; magiging stock ito pagkatapos.');
// R101–R103: a Send whose answer was lost.
const notSureLabel = Bilingual('Not sure this was recorded — the answer was lost. Send it again unchanged, check, or cancel it.',
    'Hindi sigurado kung naitala — nawala ang sagot. Ipadala ulit nang walang binago, i-check, o kanselahin.');
const sendAgainLabel = Bilingual('Send again', 'Ipadala ulit');
const checkLabel = Bilingual('Check', 'I-check');
const cancelLabel = Bilingual('Cancel it', 'Kanselahin');
const cancelChangeLabel = Bilingual('Cancel it and change', 'Kanselahin at baguhin');
const wasRecorded = Bilingual('It was recorded.', 'Naitala na ito.');
const notYetCopy = Bilingual('Not recorded yet — it may still arrive. Send it again, or cancel it.',
    'Hindi pa naitatala — baka dumating pa. Ipadala ulit, o kanselahin.');
const finishFirst = Bilingual('First finish the stock record that is not sure (top of the Stock tab).',
    'Tapusin muna ang stock record na hindi sigurado (sa itaas ng Stock tab).');

// R104: saved stock data the phone can no longer read.
const unreadableLabel = Bilingual(
    "A saved stock record on this phone is damaged — its details can't be read. Check whether it was recorded, or cancel it so it never records.",
    'May sirang stock record na naka-save sa phone na ito — hindi mabasa ang detalye. I-check kung naitala, o kanselahin para hindi na maitala.');
const unreadablePendingCopy = Bilingual('Not recorded yet — it may still arrive. Cancel it to settle it.',
    'Hindi pa naitatala — baka dumating pa. Kanselahin para matapos ito.');
const recoveryLabel = Bilingual(
    "Saved stock records on this phone can't be read. New stock records are paused on this phone — nothing was deleted. Ask the office for help before recording stock here.",
    'Hindi mabasa ang mga stock record na naka-save sa phone na ito. Nakahinto ang bagong stock record sa phone na ito — walang binura. Humingi ng tulong sa opisina bago magtala ng stock dito.');

/// A Send again refused while the first Send might still arrive.
Bilingual retryRefusedCopy(Bilingual refusal) => Bilingual('${refusal.english} The first Send may still arrive — check, or cancel it.',
    '${refusal.tagalog} Baka dumating pa ang unang pinadala — i-check, o kanselahin.');

const undoOnWeb = Bilingual('A mistake? The office reverses it on Dacs Web (Requests → Stock → History).',
    'May mali? Ang opisina ang magbabaliktad nito sa Dacs Web (Requests → Stock → History).');

/// "6 bag".
String stockQty(num v, String unit) => unit.trim().isEmpty ? formatQuantity(v) : '${formatQuantity(v)} ${unit.trim()}';

const _kind = {
  'receive': 'Received',
  'not_delivered': 'Not delivered',
  'leftover': 'Leftovers',
  'issue': 'Issued',
  'return': 'Returned',
  'move': 'Moved',
  'count': 'Count',
  'opening': 'Opening stock',
};

String recordKind(StockRecord r) => _kind[r.kind] ?? r.kind;

/// One line about a record: what moved, how much, from where to where.
String recordLine(StockRecord r) {
  final q = stockQty(r.quantity, r.unit);
  return switch (r.kind) {
    'receive' => '$q ${r.what} at the warehouse',
    'not_delivered' => '$q ${r.what} will not be delivered',
    'leftover' => '$q ${r.what} left over — ${r.toName}',
    'count' => '${r.what} at ${r.toName}: counted $q, books ${stockQty(r.bookQuantity ?? 0, r.unit)}',
    'opening' => '$q ${r.what} already at ${r.toName}',
    _ => '$q ${r.what} — ${r.fromName} → ${r.toName}',
  };
}

/// A record's state, or null when it simply happened.
String? recordState(StockRecord r) {
  if (r.reversed) return 'Reversed';
  return switch (r.status) {
    'pending' => 'Waiting for the owner',
    'rejected' => 'Rejected',
    'withdrawn' => 'Withdrawn',
    _ => null,
  };
}

/// A cost move's state, as the web words it — never its value (Q28).
String costState(StockCostState c) {
  if (c.status == 'pending') {
    return switch (c.kind) {
      'assign' => 'Cost assignment pending',
      'transfer' => 'Cost transfer pending',
      _ => 'Back to company stock — pending',
    };
  }
  if (c.status == 'rejected') return 'Cost move rejected — kept with source';
  if (c.status == 'withdrawn') return 'Cost request withdrawn';
  if (c.reversed) return 'Cost move reversed';
  return switch (c.kind) {
    'assign' => 'Cost assigned',
    'transfer' => 'Cost transferred',
    'back' => 'Cost back in company stock',
    _ => 'Company stock loss',
  };
}
