import 'dart:convert';

import 'package:crypto/crypto.dart';

class TermsClause {
  const TermsClause({required this.heading, required this.english, required this.tagalog});
  final String heading;
  final String english;
  final String tagalog;
}

/// The Terms a worker accepts on first sign-in. SHARED with the Attendance
/// app (domain/AttendanceTerms.kt): same wording, same version, so an
/// acceptance there counts here.
///
/// This text is EVIDENCE: accepting writes it, and its SHA-256, into the
/// append-only agreement_events table. CHANGING ANY CHARACTER REQUIRES A NEW
/// VERSION, agreed with the owner, and the same change in the Attendance app.
class AttendanceTerms {
  static const version = '2026-09-v3';

  static const title = "DAC's Attendance -- Terms & Conditions";

  static const clauses = <TermsClause>[
    TermsClause(
      heading: 'Recording attendance.',
      english: 'You record your own Time In and Time Out using this app. The date and time are set by the system, not typed by you.',
      tagalog: 'Ikaw mismo ang magta-Time In at Time Out. Ang petsa at oras ay galing sa sistema, hindi ito tina-type.',
    ),
    TermsClause(
      heading: 'Project selection.',
      english: 'You choose the project you are working on each time you time in and time out.',
      tagalog: 'Pipiliin mo ang project na pinagtatrabahuhan mo sa tuwing magta-Time In at Time Out ka.',
    ),
    TermsClause(
      heading: 'Photo documentation.',
      english: 'A photo is taken at Time In and at Time Out as proof of attendance and is stored with your record.',
      tagalog: 'May kukunang litrato tuwing Time In at Time Out bilang patunay ng pagpasok, at itatago ito kasama ng iyong record.',
    ),
    TermsClause(
      heading: 'Location check.',
      english: 'Your location is checked when you Time In and Time Out, to confirm you are at the project you selected. It is taken only at those two moments; the app does not follow you at any other time. If your phone cannot get a clear location, your attendance is still recorded and marked for the Admin to check. If it shows you are away from the site, or location is turned off, the attendance cannot be recorded.',
      tagalog: 'Titingnan ang lokasyon mo tuwing Time In at Time Out, para makumpirma na nasa project ka na iyong pinili. Sa dalawang sandaling iyon lang ito kinukuha; hindi ka sinusundan ng app sa ibang oras. Kung hindi makakuha ng malinaw na lokasyon ang telepono mo, maitatala pa rin ang pasok mo at mamarkahan para tingnan ng Admin. Kung malayo ka sa site ayon dito, o naka-off ang lokasyon, hindi maitatala ang pasok.',
    ),
    TermsClause(
      heading: 'Honest use.',
      english: 'Your account is yours alone. Do not let another person time in or out for you.',
      tagalog: 'Sa iyo lang ang account mo. Huwag hayaang may ibang tao ang mag-Time In o Time Out para sa iyo.',
    ),
    TermsClause(
      heading: 'Who can see your records.',
      english: 'Your attendance records, photos and location may be viewed by the Admin and the Owner to check attendance and site activity. These records are not used to compute your pay.',
      tagalog: 'Ang iyong mga record, litrato at lokasyon ay maaaring makita ng Admin at ng May-ari para tingnan ang pasok at ang trabaho sa site. Hindi ito ang batayan ng sahod mo.',
    ),
    TermsClause(
      heading: 'Weekly attendance reward.',
      english: 'The Owner may give a weekly attendance reward for a complete, on-time week. It is based on your Time In on each required day from Monday to Friday, compared against the start time set for your project: one late day, or one required day with no Time In, means no reward for that week, and there is no partial amount. Days the site is closed are not counted against you. This reward is separate from your pay and is not computed from your hours.',
      tagalog: 'Maaaring magbigay ang May-ari ng lingguhang reward para sa kumpleto at hindi nahuling pasok. Nakabatay ito sa Time In mo sa bawat araw na kailangan mula Lunes hanggang Biyernes, ayon sa oras ng simula na nakatakda para sa project mo: isang araw na late, o isang araw na walang Time In, ay walang reward para sa linggong iyon, at walang bahagyang halaga. Hindi bibilangin laban sa iyo ang mga araw na sarado ang site. Hiwalay ito sa sahod mo at hindi ito kinukuwenta mula sa oras mo.',
    ),
  ];

  /// The exact text hashed and stored. Built FROM [clauses], so the wording
  /// shown and the wording hashed cannot drift apart.
  static String canonicalText() {
    final b = StringBuffer()
      ..write(title)
      ..write('\n')
      ..write('Version: ')
      ..write(version)
      ..write('\n\n');
    for (var i = 0; i < clauses.length; i++) {
      final c = clauses[i];
      b
        ..write('${i + 1}. ${c.heading} ${c.english}\n')
        ..write('${c.tagalog}\n\n');
    }
    return b.toString().trimRight();
  }

  /// Lower-case hex, the format agreement_events.doc_sha256 holds.
  static String sha256Hex() => sha256.convert(utf8.encode(canonicalText())).toString();
}
