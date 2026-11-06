import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:supabase_flutter/supabase_flutter.dart' show AuthException;
import 'package:workmate/profile/password_change.dart';
import 'package:workmate/profile/password_prompt.dart';

import 'password_prompt_fakes.dart';

const a = 'u7';
const b = 'u5';

void main() {
  late FakePasswordServer server;
  late SharedPreferences prefs;
  late DateTime clock;

  setUp(() async {
    // ignore: invalid_use_of_visible_for_testing_member
    SharedPreferences.resetStatic();
    SharedPreferences.setMockInitialValues({});
    prefs = await SharedPreferences.getInstance();
    server = FakePasswordServer(session: a);
    clock = DateTime.utc(2026, 11, 6, 1);
  });

  PasswordPrompt prompt({String user = a}) => PasswordPrompt(
        services: server.services(prefs),
        userId: user,
        now: () => clock,
      );

  List<int> notesOf(String user) => PasswordNotes(prefs).pending(user);

  test('owed, with signal: wanted for its reset; a good save is confirmed for that reset once — never asked again', () async {
    final r1 = server.reset(a);
    final p = prompt();
    await p.check();
    expect([p.state, p.wanted, p.resetId], [PasswordPromptState.owed, true, r1]);
    await p.save('new-secret-1');
    expect([p.state, p.wanted, server.changedTo[a], server.confirmations], [PasswordPromptState.done, false, ['new-secret-1'], [(a, r1)]]);
    expect([server.changes(a), notesOf(a)], [1, isEmpty]);
    await p.check();
    expect([server.owedCalls, p.wanted], [2, false], reason: 'settled: not asked again');
    p.dispose();
  });

  test('not owed: nothing is asked', () async {
    final p = prompt();
    await p.check();
    expect([p.state, p.wanted], [PasswordPromptState.notOwed, false]);
    p.dispose();
  });

  test('no signal when asking: nothing is asked (Home stays); when signal comes back, the prompt is wanted', () async {
    server.reset(a);
    server.offline = true;
    final p = prompt();
    await p.check();
    expect([p.state, p.wanted], [PasswordPromptState.unknown, false], reason: 'never in the way while the server cannot answer');
    server.offline = false;
    await p.check();
    expect([p.state, p.wanted], [PasswordPromptState.owed, true], reason: 'the prompt returns with signal');
    p.dispose();
  });

  test('a save with no signal: Continue for now — the prompt waits for signal, then comes back', () async {
    server.reset(a);
    final p = prompt();
    await p.check();
    server.offline = true;
    await expectLater(p.save('new-secret-1'), throwsA(anything));
    expect(p.wanted, isTrue, reason: 'a failed save changes nothing by itself');
    p.continueForNow(PasswordChangeFailure.noConnection);
    expect([p.paused, p.wanted], [true, false], reason: 'Home and Time In again');
    clock = clock.add(const Duration(minutes: 30));
    await p.check();
    expect(p.wanted, isFalse, reason: 'still no signal: still paused');
    server.offline = false;
    await p.check();
    expect([p.paused, p.wanted], [false, true], reason: 'signal is back: the prompt returns');
    expect(server.changedTo[a], isNull);
    p.dispose();
  });

  test('a save refused by the server\'s fault: Continue for now pauses it 15 minutes, even with signal', () async {
    server.reset(a);
    final p = prompt();
    await p.check();
    server.failNextChange = const AuthException('Internal error', statusCode: '500');
    await expectLater(p.save('new-secret-1'), throwsA(isA<AuthException>()));
    p.continueForNow(PasswordChangeFailure.of(const AuthException('Internal error', statusCode: '500')));
    clock = clock.add(const Duration(minutes: 2));
    await p.check();
    expect(p.wanted, isFalse, reason: 'a broken server never nags every two minutes');
    clock = clock.add(const Duration(minutes: 14));
    await p.check();
    expect(p.wanted, isTrue);
    p.dispose();
  });

  test('the confirmation never arrived: never asked again; confirmed for its own reset at the next chance, once', () async {
    final r1 = server.reset(a);
    final p = prompt();
    await p.check();
    server.failNextConfirm = lostAnswer();
    await p.save('new-secret-1');
    expect([p.state, p.wanted, notesOf(a)], [PasswordPromptState.changedNotRecorded, false, [r1]]);
    await p.check();
    expect([server.changes(a), notesOf(a), p.wanted], [1, isEmpty, false]);
    expect(server.changedTo[a], ['new-secret-1'], reason: 'the worker was not asked for another password');
    p.dispose();
  });

  test('the confirmation arrived but its answer was lost: sent again it records nothing more; not asked again', () async {
    final r1 = server.reset(a);
    final p = prompt();
    await p.check();
    server.loseNextConfirmAnswer = lostAnswer();
    await p.save('new-secret-1');
    expect([server.changes(a), notesOf(a)], [1, [r1]], reason: 'recorded, but the phone could not know');
    await p.check();
    expect([server.changes(a), server.confirmations, notesOf(a), p.wanted], [1, [(a, r1), (a, r1)], isEmpty, false]);
    p.dispose();
  });

  group('the confirmation lost, then a second reset (the owner reset again before it arrived)', () {
    test('the late confirmation records nothing, and the second reset\'s prompt is kept', () async {
      final r1 = server.reset(a);
      final first = prompt();
      await first.check();
      server.failNextConfirm = lostAnswer();
      await first.save('new-secret-1');
      first.dispose();
      final r2 = server.reset(a); // a reset ends every sign-in: the worker signs in again
      final again = prompt();
      await again.check();
      expect(server.confirmations, [(a, r1)], reason: 'the late confirmation went, for its own reset');
      expect([server.changes(a), server.openReset(a)], [0, r2], reason: 'it closed nothing: r2 stays owed');
      expect([again.state, again.wanted, again.resetId, notesOf(a)], [PasswordPromptState.owed, true, r2, isEmpty]);
      await again.save('new-secret-2');
      expect([server.changes(a), server.openReset(a), again.state], [1, null, PasswordPromptState.done]);
      again.dispose();
    });

    test('with no signal after the second reset: nothing is asked (Home stays); with signal, the second reset\'s prompt', () async {
      server.reset(a);
      final first = prompt();
      await first.check();
      server.failNextConfirm = lostAnswer();
      await first.save('new-secret-1');
      first.dispose();
      final r2 = server.reset(a);
      server.offline = true;
      final again = prompt();
      await again.check();
      expect([again.state, again.wanted], [PasswordPromptState.changedNotRecorded, false], reason: 'attendance stays reachable');
      server.offline = false;
      await again.check();
      expect([again.wanted, again.resetId], [true, r2]);
      again.dispose();
    });
  });

  group('an account switch while a confirmation is pending', () {
    test('the other account is asked its own; the note is never sent with their sign-in; back on the first, it confirms its own reset', () async {
      final rA = server.reset(a);
      final rB = server.reset(b);
      final pa = prompt(user: a);
      await pa.check();
      server.failNextConfirm = lostAnswer();
      await pa.save('a-secret-1');
      pa.dispose();
      expect(notesOf(a), [rA]);

      server.session = b; // another account signs in on this phone
      final pb = prompt(user: b);
      await pb.check();
      expect([pb.wanted, pb.resetId], [true, rB], reason: 'their own prompt, untouched by the other\'s note');
      expect([server.confirmations, notesOf(a), server.changes(a), server.changes(b)], [isEmpty, [rA], 0, 0]);
      pb.dispose();

      server.session = a; // the first account signs back in
      final pa2 = prompt(user: a);
      await pa2.check();
      expect([server.confirmations, server.changes(a), server.changes(b), notesOf(a)], [[(a, rA)], 1, 0, isEmpty]);
      expect(pa2.wanted, isFalse, reason: 'confirmed, not asked again');
      pa2.dispose();
    });

    test('a prompt left from the other account never confirms with this sign-in: refused, and its note stays', () async {
      final rA = server.reset(a);
      final pa = prompt(user: a);
      await pa.check();
      server.failNextConfirm = lostAnswer();
      await pa.save('a-secret-1');
      server.session = b;
      await pa.check();
      expect([server.confirmations, notesOf(a), pa.wanted], [isEmpty, [rA], false]);
      pa.dispose();
    });

    test('the first account was reset again while away: its old confirmation closes nothing, and its new prompt is kept', () async {
      server.reset(a);
      final pa = prompt(user: a);
      await pa.check();
      server.failNextConfirm = lostAnswer();
      await pa.save('a-secret-1');
      pa.dispose();
      server.session = b;
      final rA2 = server.reset(a);
      server.session = a;
      final pa2 = prompt(user: a);
      await pa2.check();
      expect([server.changes(a), pa2.wanted, pa2.resetId], [0, true, rA2]);
      pa2.dispose();
    });
  });

  group('the password change is bound to the account the prompt was opened for', () {
    test('A\'s prompt, then B signs in, then Save: refused before anything is sent — B\'s password and reset state stay intact',
        () async {
      final rA = server.reset(a);
      final rB = server.reset(b);
      final pa = prompt(user: a);
      await pa.check();
      expect([pa.wanted, pa.resetId], [true, rA]);
      server.session = b; // B signs in while A's prompt is still open
      Object? why;
      try {
        await pa.save('typed-for-a-1');
      } catch (e) {
        why = e;
      }
      expect(PasswordChangeFailure.of(why!), PasswordChangeFailure.sessionExpired, reason: 'read as "Please log in again", never a password problem');
      expect([server.changedTo[b], server.openReset(b), server.changes(b)], [isNull, rB, 0], reason: 'B: password and reset state intact');
      expect([server.changedTo[a], server.openReset(a), server.changes(a)], [isNull, rA, 0], reason: 'A: nothing changed either');
      expect([server.confirmations, notesOf(a), notesOf(b)], [isEmpty, isEmpty, isEmpty]);
      expect([pa.state, pa.resetId], [PasswordPromptState.owed, rA], reason: 'still owed, for A\'s own reset');
      pa.dispose();
    });

    test('the account check and the request are one step: another account\'s sign-in never reaches the change', () async {
      var changes = 0;
      var signedIn = b;
      final change = PasswordPromptServices.boundChange(signedIn: () => signedIn, change: (_) async {
        changes++;
        return signedIn;
      });
      await expectLater(change(a, 'typed-for-a-1'), throwsStateError);
      expect(changes, 0, reason: 'nothing was sent');
      signedIn = a;
      await change(a, 'typed-for-a-1');
      expect(changes, 1);
    });

    test('an answer naming another account is refused too', () async {
      final change = PasswordPromptServices.boundChange(signedIn: () => a, change: (_) async => b);
      await expectLater(change(a, 'typed-for-a-1'), throwsStateError);
    });
  });

  test('a server without 0112 (no reset named): nothing is asked, and nothing confirmed', () async {
    var confirms = 0;
    final services = PasswordPromptServices(
      owed: (_) async => const PasswordOwed(mustChange: true),
      confirm: (_, _) async => ++confirms > 0,
      changePassword: (_, _) async {},
      notes: PasswordNotes(prefs),
    );
    final p = PasswordPrompt(services: services, userId: a);
    await p.check();
    expect([p.state, p.wanted, confirms], [PasswordPromptState.notOwed, false, 0]);
    p.dispose();
  });

  testWidgets('while unanswered, it asks again on its own every two minutes — and stops once settled', (tester) async {
    server.reset(a);
    server.offline = true;
    final p = PasswordPrompt(services: server.services(prefs), userId: a);
    await p.check();
    final asked = server.owedCalls;
    await tester.pump(const Duration(minutes: 2));
    expect(server.owedCalls, asked + 1);
    server.offline = false;
    await tester.pump(const Duration(minutes: 2));
    expect(p.wanted, isTrue);
    final settled = server.owedCalls;
    await tester.pump(const Duration(minutes: 10));
    expect(server.owedCalls, settled, reason: 'owed and shown: no timer');
    p.dispose();
  });
}
