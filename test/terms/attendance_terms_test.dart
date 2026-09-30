import 'package:flutter_test/flutter_test.dart';
import 'package:workmate/terms/attendance_terms.dart';

/// WorkMate shows the SAME Terms the Attendance app shows, so a worker who
/// accepted there is not asked again. The hash below is the live
/// agreement_events.doc_sha256 for version 2026-09-v3 (checked 2026-09-30).
/// If this fails, the wording drifted: do not "fix" the hash.
void main() {
  test('same version as the Attendance app', () {
    expect(AttendanceTerms.version, '2026-09-v3');
  });

  test('canonical text is byte-identical to what workers already accepted', () {
    expect(AttendanceTerms.canonicalText().length, 3079);
    expect(AttendanceTerms.sha256Hex(), '80bb9d44274b77de8a2d6e11609f1b07d6b73245a6366ed2807b9d981584fbd5');
  });

  test('seven numbered clauses, English then Tagalog', () {
    final text = AttendanceTerms.canonicalText();
    expect(AttendanceTerms.clauses.length, 7);
    expect(text, startsWith("DAC's Attendance -- Terms & Conditions\nVersion: 2026-09-v3\n\n1. Recording attendance. "));
    expect(text.endsWith('\n'), isFalse);
  });
}
