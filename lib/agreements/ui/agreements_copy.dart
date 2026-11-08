import '../../attendance/ui/attendance_copy.dart' show Bilingual;
import '../domain/my_agreement.dart';

/// English, then Tagalog — the crew's own words for their agreements.
const myAgreementsTitle = Bilingual('My agreements', 'Mga kasunduan ko');
const agreementsNone = Bilingual('No agreements are linked to your account yet.', 'Wala pang kasunduang naka-link sa account mo.');
const agreementsFootnote = Bilingual(
  'Payments are the company’s records. Progress is the whole project’s, not your own work.',
  'Ang mga bayad ay talaan ng kumpanya. Ang progreso ay sa buong proyekto, hindi sa sarili mong trabaho.',
);
const progressLabel = Bilingual('Overall project progress', 'Progreso ng buong proyekto');
const progressNone = Bilingual('Progress not recorded yet', 'Wala pang naitalang progreso');
const agreementGone = Bilingual('This agreement isn’t shown to you any more.', 'Hindi na ipinapakita sa iyo ang kasunduang ito.');
const agreementsRetry = Bilingual('Try again', 'Subukan ulit');
const agreementsChecking = Bilingual('Checking your agreements…', 'Sinusuri ang mga kasunduan mo…');

Bilingual agreementsFailureCopy(AgreementsFailure f) => switch (f) {
      AgreementsFailure.noConnection => const Bilingual(
          'Needs signal to show your agreements. Nothing is saved on this phone.',
          'Kailangan ng signal para makita ang mga kasunduan mo. Walang naka-save sa phone na ito.'),
      AgreementsFailure.notAllowed => const Bilingual(
          'Agreements here are for workers and team leaders. Ask the office.',
          'Para sa mga worker at team leader ang mga kasunduan dito. Itanong sa opisina.'),
      AgreementsFailure.sessionExpired => const Bilingual(
          'Please sign in again to see your agreements.', 'Mag-sign in ulit para makita ang mga kasunduan mo.'),
      AgreementsFailure.appUpdateRequired => const Bilingual(
          'Update WorkMate to see your agreements.', 'I-update ang WorkMate para makita ang mga kasunduan mo.'),
      AgreementsFailure.unexpected => const Bilingual(
          'Your agreements could not be shown. Try again later.', 'Hindi maipakita ang mga kasunduan mo. Subukan ulit mamaya.'),
    };

String paymentMethodLabel(String? m) => switch (m) {
      'cash' => 'Cash',
      'gcash' => 'GCash',
      'bank_transfer' => 'Bank transfer',
      'cheque' => 'Cheque',
      _ => '',
    };

/// "₱1,250.50" (never a minus sign: an overpayment reads "Over by").
String agreementPeso(num v) {
  final fixed = v.abs().toStringAsFixed(2);
  final parts = fixed.split('.');
  final whole = parts[0].replaceAllMapped(RegExp(r'\B(?=(\d{3})+(?!\d))'), (_) => ',');
  return '₱$whole.${parts[1]}';
}

/// "42.5%" — one decimal, as the office shows it.
String progressText(double pct) => '${pct.toStringAsFixed(1)}%';
