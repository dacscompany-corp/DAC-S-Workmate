import 'package:flutter_test/flutter_test.dart';
import 'package:workmate/auth/session_gate.dart';

void main() {
  test('a confirmed session asks the server', () {
    expect(decideSession(SessionPresence.confirmed, hasLastKnownWorker: false), SessionDecision.askTheServer);
  });

  test('a session that cannot be checked is still a session (offline morning)', () {
    expect(decideSession(SessionPresence.unverifiable, hasLastKnownWorker: true), SessionDecision.useLastKnown);
  });

  test('unverifiable with nobody remembered cannot show a worker', () {
    expect(decideSession(SessionPresence.unverifiable, hasLastKnownWorker: false), SessionDecision.signedOut);
  });

  test('no session means signed out, even with a cached profile', () {
    expect(decideSession(SessionPresence.absent, hasLastKnownWorker: true), SessionDecision.signedOut);
  });
}
