import 'package:flutter_test/flutter_test.dart';
import 'package:workmate/terms/terms_gates.dart';

void main() {
  test('terms gate: current version accepted or not', () {
    expect(decideTerms({'2026-09-v3'}, '2026-09-v3'), TermsDecision.alreadyAccepted);
    expect(decideTerms({'2026-08-v2'}, '2026-09-v3'), TermsDecision.mustAccept);
  });

  group('startup gate', () {
    test('the server answer wins', () {
      expect(decideStartup(acceptedVersions: {'2026-09-v3'}, cachedVersion: null, currentVersion: '2026-09-v3'),
          StartupDecision.ready);
      // A cached acceptance the server does not have does not count.
      expect(decideStartup(acceptedVersions: <String>{}, cachedVersion: '2026-09-v3', currentVersion: '2026-09-v3'),
          StartupDecision.mustAccept);
    });

    test('offline falls back to what this device recorded', () {
      expect(decideStartup(acceptedVersions: null, cachedVersion: '2026-09-v3', currentVersion: '2026-09-v3'),
          StartupDecision.ready);
    });

    test('offline with nothing recorded never guesses "not accepted"', () {
      expect(decideStartup(acceptedVersions: null, cachedVersion: null, currentVersion: '2026-09-v3'),
          StartupDecision.unavailable);
      expect(decideStartup(acceptedVersions: null, cachedVersion: '2026-08-v2', currentVersion: '2026-09-v3'),
          StartupDecision.unavailable);
    });
  });
}
