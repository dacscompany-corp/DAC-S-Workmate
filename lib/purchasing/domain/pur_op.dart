import 'dart:convert';

/// One receipt photo of a queued purchase: the file on the phone and, once
/// uploaded, where it went. [photoId] is minted once, at Send, so a retry
/// uploads to the same place.
class ReceiptUpload {
  const ReceiptUpload({required this.local, required this.photoId, this.path, this.url});

  factory ReceiptUpload.fromJson(Map<String, dynamic> j) => ReceiptUpload(
        local: j['local'] as String,
        photoId: j['photo_id'] as String,
        path: j['path'] as String?,
        url: j['url'] as String?,
      );

  final String local;
  final String photoId;

  /// `purchases/<company>/<yyyy-mm>/<photoId>.jpg`, fixed at the first attempt.
  final String? path;

  /// Set once the file is in storage.
  final String? url;

  ReceiptUpload withPath(String p) => ReceiptUpload(local: local, photoId: photoId, path: p, url: url);
  ReceiptUpload withUrl(String u) => ReceiptUpload(local: local, photoId: photoId, path: path, url: u);

  Map<String, dynamic> toJson() => {'local': local, 'photo_id': photoId, 'path': path, 'url': url};
}

/// One purchase waiting to be recorded (Q7: "Waiting to send"). [opId] is
/// minted once, at Send, and reused on every retry: pur_record answers a
/// repeated op id with its first answer, so it is recorded once.
class PurOp {
  const PurOp({
    required this.opId,
    required this.userId,
    required this.createdAt,
    required this.purchase,
    this.kind = 'record',
    this.draftId,
    this.companyId,
    this.receipts = const {},
    this.seq = 0,
    this.attempts = 0,
    this.lastError,
    this.failedPermanently = false,
    this.sent = false,
  });

  factory PurOp.fromMap(Map<String, Object?> m) {
    final body = Map<String, dynamic>.from(jsonDecode(m['body']! as String) as Map);
    return PurOp(
      opId: m['op_id']! as String,
      userId: m['user_id']! as String,
      kind: m['kind']! as String,
      createdAt: DateTime.fromMillisecondsSinceEpoch(m['created_at']! as int, isUtc: true),
      draftId: m['draft_id'] as String?,
      purchase: Map<String, dynamic>.from(body['purchase'] as Map),
      companyId: body['company_id'] as String?,
      receipts: {
        for (final e in Map<String, dynamic>.from((body['receipts'] as Map?) ?? const {}).entries)
          e.key: ReceiptUpload.fromJson(Map<String, dynamic>.from(e.value as Map)),
      },
      seq: (m['seq'] as int?) ?? 0,
      attempts: (m['attempts'] as int?) ?? 0,
      lastError: m['last_error'] as String?,
      failedPermanently: m['failed_permanently'] == 1,
      sent: m['done_at'] != null,
    );
  }

  final String opId;

  /// Who queued it. Every read and every send is scoped to ONE account.
  final String userId;
  final String kind;
  final DateTime createdAt;
  final String? draftId;

  /// The pur_record body, without its receipt links.
  final Map<String, dynamic> purchase;

  /// The company the receipts file under; resolved at the first attempt
  /// when this phone did not know it yet.
  final String? companyId;

  /// Receipt slot → its photo.
  final Map<String, ReceiptUpload> receipts;
  final int seq;
  final int attempts;
  final String? lastError;
  final bool failedPermanently;

  /// R38: the server has it. Kept on the phone (never sent again) until every
  /// saved copy that shows it counts it, so a copy read before it went still
  /// shows it and no balance is ever wrong because of it.
  final bool sent;

  Map<String, dynamic> get bodyJson => {
        'purchase': purchase,
        'company_id': companyId,
        'receipts': {for (final e in receipts.entries) e.key: e.value.toJson()},
      };

  PurOp copyWith({String? companyId, Map<String, ReceiptUpload>? receipts}) => PurOp(
        opId: opId,
        userId: userId,
        createdAt: createdAt,
        purchase: purchase,
        kind: kind,
        draftId: draftId,
        companyId: companyId ?? this.companyId,
        receipts: receipts ?? this.receipts,
        seq: seq,
        attempts: attempts,
        lastError: lastError,
        failedPermanently: failedPermanently,
        sent: sent,
      );

  Map<String, Object?> toMap() => {
        'op_id': opId,
        'user_id': userId,
        'kind': kind,
        'draft_id': draftId,
        'body': jsonEncode(bodyJson),
        'seq': seq,
        'attempts': attempts,
        'last_error': lastError,
        'failed_permanently': failedPermanently ? 1 : 0,
        'created_at': createdAt.millisecondsSinceEpoch,
      };
}

/// `<folder>/<company>/<yyyy-mm>/<photo>.jpg` — the only shape the
/// receipt_uploads check and the storage rules accept. [folder] is
/// `purchases` (receipts and payment proofs, buyers of the company: 0097) or
/// `pettyCash` (a return's photo: the main owner and its uploader only, 0102
/// R13). The month is Manila's ([manilaNow] already shifted), as the web's
/// local-parts month.
String receiptPath({required String companyId, required DateTime manilaNow, required String photoId, String folder = 'purchases'}) {
  final ym = '${manilaNow.year.toString().padLeft(4, '0')}-${manilaNow.month.toString().padLeft(2, '0')}';
  return '$folder/${companyId.toLowerCase()}/$ym/${photoId.toLowerCase()}.jpg';
}

/// What a queued op sends (0102). 'record' is a purchase (with any "paid
/// now" payment inside it, one transaction); 'pay' a later payment on a
/// recorded purchase (its proof photo under purchases/); 'cash_return' a
/// return of petty cash (its photo under pettyCash/).
const opRecord = 'record';
const opPay = 'pay';
const opCashReturn = 'cash_return';

/// The upload kind and folder each op's photos go to.
({String kind, String folder}) photoTarget(String opKind) =>
    opKind == opCashReturn ? (kind: 'petty_cash', folder: 'pettyCash') : (kind: 'purchase', folder: 'purchases');
