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
const agreementsChecking = Bilingual('Checking your agreements…', 'Tinitingnan ang mga kasunduan mo…');
const agreementOverPaid = Bilingual(
  'Paid more than the agreed amount. Ask the office if you have questions.',
  'Nabayaran nang higit sa kasunduan. Itanong sa opisina kung may tanong ka.',
);
const agreementDailyNote = 'No agreed total — paid by the day.';
const agreementWorksLabel = 'Works covered';

/// The headline of a failure (English) and the whole message in Tagalog.
Bilingual agreementsFailureCopy(AgreementsFailure f) => switch (f) {
      AgreementsFailure.noConnection => const Bilingual(
          'Needs signal to show your agreements.',
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

/// The English second line under a failure's headline, when it has one.
String? agreementsFailureDetail(AgreementsFailure f) =>
    f == AgreementsFailure.noConnection ? 'Nothing is saved on this phone.' : null;

/// Whether "Try again" can help: an app too old to be answered needs an update first.
bool agreementsFailureRetries(AgreementsFailure f) => f != AgreementsFailure.appUpdateRequired;

/// One tab per agreement, by id. A project with one agreement is named alone;
/// two or more on the same project add the trade (or, without one, the job):
/// "De Leon Residence · Tiling". Labels still alike then try the job, and any
/// left alike are numbered, so no two tabs ever read the same.
Map<String, String> agreementTabLabels(List<MyAgreement> list) {
  String name(MyAgreement a) => a.project.trim().isEmpty ? 'Agreement' : a.project.trim();
  String job(MyAgreement a) => a.scope.trim().isEmpty ? 'Untitled job' : a.scope.trim();
  String tag(MyAgreement a) => a.trade.trim().isNotEmpty ? a.trade.trim() : job(a);

  final perProject = <String, int>{};
  for (final a in list) {
    perProject[name(a)] = (perProject[name(a)] ?? 0) + 1;
  }
  final labels = {for (final a in list) a.id: perProject[name(a)]! > 1 ? '${name(a)} · ${tag(a)}' : name(a)};

  Map<String, List<MyAgreement>> alike() {
    final groups = <String, List<MyAgreement>>{};
    for (final a in list) {
      groups.putIfAbsent(labels[a.id]!, () => []).add(a);
    }
    return {for (final e in groups.entries) if (e.value.length > 1) e.key: e.value};
  }

  for (final group in alike().values) {
    for (final a in group) {
      labels[a.id] = '${name(a)} · ${job(a)}';
    }
  }
  for (final e in alike().entries) {
    for (final (i, a) in e.value.indexed) {
      labels[a.id] = '${e.key} (${i + 1})';
    }
  }
  return labels;
}

/// The share of the agreed amount paid, as the ring prints it, or null with no
/// agreed amount to measure against. Under the agreed amount it rounds DOWN and
/// over it rounds UP, so the ring reads exactly 100% only when paid equals agreed.
int? agreementPaidPercent(MyAgreement a) {
  final agreed = a.agreed;
  if (a.daily || agreed == null || agreed <= 0) return null;
  final pct = a.paid * 100 / agreed;
  if (a.paid < agreed) {
    final down = pct.floor();
    return down < 0 ? 0 : (down > 99 ? 99 : down);
  }
  if (a.paid == agreed) return 100;
  final up = pct.ceil();
  return up < 101 ? 101 : up;
}

/// "₱1,250.50" (never a minus sign: an overpayment reads "Over by").
String agreementPeso(num v) {
  final fixed = v.abs().toStringAsFixed(2);
  final parts = fixed.split('.');
  final whole = parts[0].replaceAllMapped(RegExp(r'\B(?=(\d{3})+(?!\d))'), (_) => ',');
  return '₱$whole.${parts[1]}';
}

/// "42.5%" — one decimal, as the office shows it.
String progressText(double pct) => '${pct.toStringAsFixed(1)}%';
