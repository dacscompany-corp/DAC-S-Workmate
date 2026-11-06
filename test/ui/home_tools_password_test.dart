import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:supabase_flutter/supabase_flutter.dart' show AuthException;
import 'package:workmate/attendance/attendance_services.dart';
import 'package:workmate/attendance/sync/queue_settled.dart';
import 'package:workmate/auth/worker_profile.dart';
import 'package:workmate/profile/account_services.dart';
import 'package:workmate/profile/password_prompt.dart';
import 'package:workmate/tools/data/tools_saved_copy.dart';
import 'package:workmate/tools/tools_services.dart';
import 'package:workmate/ui/home_shell.dart';
import 'package:workmate/ui/theme.dart';

import '../attendance/fakes.dart';
import '../profile/password_prompt_fakes.dart';
import '../tools/tool_fakes.dart';

Widget wrap(Widget w) => MaterialApp(theme: workMateTheme(), home: w);

const worker = WorkerProfile(id: 'u7', displayName: 'Test Seven', position: 'Helper', workerNo: 7, role: 'worker');
const leader = WorkerProfile(id: 'u5', displayName: 'Test Five', position: 'Mason', workerNo: 5, role: 'teamLeader');

const prompt = 'Set your own password';
const flowTitle = 'Which project today?';

void main() {
  late SharedPreferences prefs;
  late FakePasswordServer server;
  late QueueSettled settled;
  late int signOuts;
  var signIns = 0;

  setUp(() async {
    // ignore: invalid_use_of_visible_for_testing_member
    SharedPreferences.resetStatic();
    SharedPreferences.setMockInitialValues({});
    prefs = await SharedPreferences.getInstance();
    server = FakePasswordServer(session: worker.id);
    settled = QueueSettled();
    signOuts = 0;
  });

  /// Home for [who], as after a sign-in: a new Home each time (a reset ends
  /// every sign-in, and another account gets its own Home).
  Future<void> showShell(WidgetTester tester, {WorkerProfile who = worker, ToolsServices? tools, bool password = true}) async {
    useTallPhone(tester);
    await tester.pumpWidget(wrap(HomeShell(
      key: ValueKey('${who.id}#${signIns++}'),
      worker: who,
      versionName: '0.10.0',
      onSignOut: () async => signOuts++,
      services: AttendanceServices(
        attendance: FakeAttendance(),
        device: FakeDevice(),
        scheduler: FakeScheduler(),
        trustedNow: () async => null,
        photoUrl: (_) async => null,
        openSettings: (_) async {},
        cameraStep: (context, args) => const Text('camera'),
        queueSettled: settled,
      ),
      account: AccountServices(
        changePassword: server.changePassword,
        termsAcceptedAt: () async => null,
        passwordPrompt: password ? server.services(prefs) : null,
      ),
      tools: tools,
    )));
    await tester.pumpAndSettle();
  }

  Future<void> typePassword(WidgetTester tester, String a, [String? b]) async {
    await tester.enterText(find.byKey(const Key('own-password')), a);
    await tester.enterText(find.byKey(const Key('own-password-again')), b ?? a);
    await tester.tap(find.byKey(const Key('own-password-save')));
    await tester.pumpAndSettle();
  }

  /// Time In opens and goes back: attendance is reachable.
  Future<void> timeInWorks(WidgetTester tester) async {
    await tester.tap(find.byKey(const Key('hero-time-in')));
    await tester.pumpAndSettle();
    expect(find.text(flowTitle), findsOneWidget, reason: 'Time In opens');
    await tester.tap(find.byKey(const Key('flow-back')));
    await tester.pumpAndSettle();
  }

  /// Signal is back: a background send just reached the server.
  Future<void> signalBack(WidgetTester tester) async {
    server.offline = false;
    settled.fire();
    await tester.pumpAndSettle();
  }

  List<int> notesOf(String user) => PasswordNotes(prefs).pending(user);

  group('the password prompt (P1 = A)', () {
    testWidgets('owed: it opens over Home after sign-in, and Back does not close it', (tester) async {
      server.reset(worker.id);
      await showShell(tester);
      expect(find.text(prompt), findsOneWidget);
      await tester.binding.handlePopRoute();
      await tester.pumpAndSettle();
      expect(find.text(prompt), findsOneWidget, reason: 'forced while the server can be reached');
      expect(find.byKey(const Key('own-password-continue')), findsNothing, reason: 'nothing failed: no way past it');
    });

    testWidgets('not owed: nothing opens', (tester) async {
      await showShell(tester);
      expect(find.text(prompt), findsNothing);
      expect(find.byKey(const Key('hero-time-in')), findsOneWidget);
    });

    testWidgets('no signal at sign-in: Home and Time In work; the prompt opens when signal comes back', (tester) async {
      server.reset(worker.id);
      server.offline = true;
      await showShell(tester);
      expect(find.text(prompt), findsNothing);
      await timeInWorks(tester);
      expect(find.text(prompt), findsNothing, reason: 'still no signal');
      await signalBack(tester);
      expect(find.text(prompt), findsOneWidget, reason: 'signal is back: the prompt returns');
    });

    testWidgets('no signal at sign-in: coming back to the app with signal opens it too', (tester) async {
      server.reset(worker.id);
      server.offline = true;
      await showShell(tester);
      server.offline = false;
      tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.paused);
      tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
      await tester.pumpAndSettle();
      expect(find.text(prompt), findsOneWidget);
    });

    testWidgets('the change fails for no signal: Continue for now — Home and Time In work; with signal it returns', (tester) async {
      server.reset(worker.id);
      await showShell(tester);
      server.offline = true;
      await typePassword(tester, 'new-secret-1');
      expect(find.text('No signal right now. Try again in a moment.'), findsOneWidget);
      await tester.tap(find.byKey(const Key('own-password-continue')));
      await tester.pumpAndSettle();
      expect(find.text(prompt), findsNothing);
      await timeInWorks(tester);
      await signalBack(tester);
      expect(find.text(prompt), findsOneWidget, reason: 'signal is back: asked again');
      expect(server.changedTo[worker.id], isNull, reason: 'the password never changed');
    });

    testWidgets('the change fails by the server\'s fault: Continue for now — Time In still works', (tester) async {
      server.reset(worker.id);
      await showShell(tester);
      server.failNextChange = const AuthException('Internal error', statusCode: '500');
      await typePassword(tester, 'new-secret-1');
      expect(find.text('Something went wrong. Try again.'), findsOneWidget);
      await tester.tap(find.byKey(const Key('own-password-continue')));
      await tester.pumpAndSettle();
      expect(find.text(prompt), findsNothing);
      await timeInWorks(tester);
      settled.fire();
      await tester.pumpAndSettle();
      expect(find.text(prompt), findsNothing, reason: 'paused 15 minutes after a server fault: no nagging');
    });

    testWidgets('a typing mistake is fixed, never continued past', (tester) async {
      server.reset(worker.id);
      await showShell(tester);
      await typePassword(tester, 'short');
      expect(find.text('Use at least 8 characters.'), findsOneWidget);
      await typePassword(tester, 'new-secret-1', 'new-secret-2');
      expect(find.text('The two passwords do not match.'), findsOneWidget);
      expect(find.byKey(const Key('own-password-continue')), findsNothing);
      expect(server.changedTo[worker.id], isNull);
    });

    testWidgets('a good change: saved, confirmed once for its reset, and the prompt closes for good', (tester) async {
      final r1 = server.reset(worker.id);
      await showShell(tester);
      await typePassword(tester, 'new-secret-1');
      expect(find.text(prompt), findsNothing);
      expect([server.changedTo[worker.id], server.confirmations, server.changes(worker.id)], [['new-secret-1'], [(worker.id, r1)], 1]);
      settled.fire();
      await tester.pumpAndSettle();
      expect(find.text(prompt), findsNothing);
      await timeInWorks(tester);
    });

    testWidgets('saved but the confirmation lost: the prompt closes and is not asked again; it is confirmed later', (tester) async {
      final r1 = server.reset(worker.id);
      await showShell(tester);
      server.failNextConfirm = lostAnswer();
      await typePassword(tester, 'new-secret-1');
      expect([find.text(prompt), server.changes(worker.id), notesOf(worker.id)], [findsNothing, 0, [r1]]);
      settled.fire();
      await tester.pumpAndSettle();
      expect([find.text(prompt), server.changes(worker.id), notesOf(worker.id), server.changedTo[worker.id]!.length],
          [findsNothing, 1, isEmpty, 1]);
    });

    testWidgets('a Time In in progress is never interrupted: the prompt waits for it to end', (tester) async {
      server.reset(worker.id);
      server.offline = true;
      await showShell(tester);
      await tester.tap(find.byKey(const Key('hero-time-in')));
      await tester.pumpAndSettle();
      await signalBack(tester);
      expect(find.text(flowTitle), findsOneWidget, reason: 'still recording');
      expect(find.text(prompt), findsNothing);
      await tester.tap(find.byKey(const Key('flow-back')));
      await tester.pumpAndSettle();
      expect(find.text(prompt), findsOneWidget, reason: 'asked once the flow ended');
    });

    testWidgets('"Not you? Log out" signs out; the change stays owed', (tester) async {
      server.reset(worker.id);
      await showShell(tester);
      await tester.tap(find.byKey(const Key('own-password-sign-out')));
      await tester.pumpAndSettle();
      expect([signOuts, server.changedTo[worker.id], server.changes(worker.id)], [1, isNull, 0]);
    });

    testWidgets('without the prompt\'s services nothing is asked (older wiring, tests)', (tester) async {
      server.reset(worker.id);
      await showShell(tester, password: false);
      expect(find.text(prompt), findsNothing);
      expect(server.owedCalls, 0);
    });
  });

  group('the confirmation lost, then a second reset', () {
    testWidgets('the late confirmation closes nothing; the second reset\'s prompt is kept, and Time In stays reachable throughout',
        (tester) async {
      final r1 = server.reset(worker.id);
      await showShell(tester);
      server.failNextConfirm = lostAnswer();
      await typePassword(tester, 'new-secret-1');
      expect(find.text(prompt), findsNothing);
      expect(notesOf(worker.id), [r1], reason: 'changed here; its confirmation waits');
      await timeInWorks(tester);

      // The owner resets the password again. That ends every sign-in: the
      // worker signs in again with the new temporary password — with no signal yet.
      final r2 = server.reset(worker.id);
      server.offline = true;
      await showShell(tester);
      expect(find.text(prompt), findsNothing, reason: 'nothing is known yet');
      await timeInWorks(tester);

      await signalBack(tester);
      expect(server.confirmations, [(worker.id, r1)], reason: 'the late confirmation went, for its own reset');
      expect([server.changes(worker.id), server.openReset(worker.id), notesOf(worker.id)], [0, r2, isEmpty],
          reason: 'it closed nothing: the second reset stays owed');
      expect(find.text(prompt), findsOneWidget, reason: 'the second reset\'s prompt is kept');

      // Attendance stays reachable even here: a failed change can be continued past.
      server.offline = true;
      await typePassword(tester, 'new-secret-2');
      await tester.tap(find.byKey(const Key('own-password-continue')));
      await tester.pumpAndSettle();
      await timeInWorks(tester);
      await signalBack(tester);
      expect(find.text(prompt), findsOneWidget, reason: 'still owed, asked again with signal');
      await typePassword(tester, 'new-secret-2');
      expect([find.text(prompt), server.changes(worker.id), server.openReset(worker.id)], [findsNothing, 1, null]);
    });
  });

  group('the password change is bound to the account that opened the prompt', () {
    testWidgets('A\'s prompt is open, B signs in, then Save: B\'s password and reset state stay intact', (tester) async {
      final rA = server.reset(worker.id);
      final rB = server.reset(leader.id);
      await showShell(tester);
      expect(find.text(prompt), findsOneWidget, reason: 'A\'s prompt is open');
      server.session = leader.id; // B signs in on this phone while A's prompt is still on screen
      await typePassword(tester, 'typed-for-a-1');
      expect(find.text('Please log in again.'), findsOneWidget, reason: 'refused as a sign-in problem, never as a password problem');
      expect([server.changedTo[leader.id], server.openReset(leader.id), server.changes(leader.id)], [isNull, rB, 0],
          reason: 'B: password and reset state intact');
      expect([server.changedTo[worker.id], server.openReset(worker.id), server.changes(worker.id)], [isNull, rA, 0],
          reason: 'A: nothing changed either');
      expect([server.confirmations, notesOf(worker.id), notesOf(leader.id)], [isEmpty, isEmpty, isEmpty]);
    });
  });

  group('an account switch while a confirmation is pending', () {
    testWidgets('each account keeps its own prompt; the pending confirmation stays with its account; Time In stays reachable',
        (tester) async {
      final rA = server.reset(worker.id);
      final rB = server.reset(leader.id);
      await showShell(tester);
      server.failNextConfirm = lostAnswer();
      await typePassword(tester, 'a-secret-1');
      expect([find.text(prompt), notesOf(worker.id)], [findsNothing, [rA]]);

      // Another account signs in on this phone, with no signal.
      server.session = leader.id;
      server.offline = true;
      await showShell(tester, who: leader);
      expect(find.text(prompt), findsNothing);
      await timeInWorks(tester);

      await signalBack(tester);
      expect(find.text(prompt), findsOneWidget, reason: 'their own outstanding prompt is kept');
      expect([server.confirmations, notesOf(worker.id), server.changes(worker.id), server.openReset(leader.id)], [isEmpty, [rA], 0, rB],
          reason: 'the first account\'s note was never sent with this sign-in');

      // Their change fails for no signal: they continue, and Time In works.
      server.offline = true;
      await typePassword(tester, 'b-secret-1');
      await tester.tap(find.byKey(const Key('own-password-continue')));
      await tester.pumpAndSettle();
      await timeInWorks(tester);

      // The first account signs back in, with signal: its own reset is confirmed, nothing asked.
      server.session = worker.id;
      server.offline = false;
      await showShell(tester);
      expect(find.text(prompt), findsNothing);
      expect([server.confirmations, server.changes(worker.id), notesOf(worker.id), server.openReset(leader.id)],
          [[(worker.id, rA)], 1, isEmpty, rB], reason: 'confirmed for its own account and reset; the other\'s stays owed');
      await timeInWorks(tester);
    });
  });

  group('the My tools card', () {
    ToolsServices tools(FakeToolsRemote remote) =>
        ToolsServices(remote: remote, store: MemoryToolPendingStore(), saved: ToolsSavedCopy(prefs));

    testWidgets('a worker: the card counts their tools and reported problems, and opens Tools', (tester) async {
      final remote = FakeToolsRemote();
      await showShell(tester, tools: tools(remote));
      expect(find.byKey(const Key('tools-card')), findsOneWidget);
      expect(find.text('2 tools with you'), findsOneWidget);
      expect(find.text('1 problem reported'), findsOneWidget);
      expect(remote.teamCalls, 0, reason: 'a worker is never asked for a team');
      await tester.tap(find.byKey(const Key('tools-card')));
      await tester.pumpAndSettle();
      expect(find.text('Tools'), findsOneWidget);
      expect(find.text('TOOL-0001 · Grinder'), findsOneWidget);
      expect(find.byKey(const Key('tools-parts')), findsNothing, reason: 'no Team for a worker');
    });

    testWidgets('a team leader: the card shows the team, and Tools has Mine, Team and My records', (tester) async {
      server.session = leader.id;
      await showShell(tester, who: leader, tools: tools(FakeToolsRemote()));
      expect(find.text('Team: 4 tools'), findsOneWidget);
      await tester.tap(find.byKey(const Key('tools-card')));
      await tester.pumpAndSettle();
      expect(find.byKey(const Key('tools-parts')), findsOneWidget);
    });

    testWidgets('tools switched off: no card, and Home is as before', (tester) async {
      final remote = FakeToolsRemote()..failMine = refusal('TOOLS_OFF');
      await showShell(tester, tools: tools(remote));
      expect(find.byKey(const Key('tools-card')), findsNothing);
      await timeInWorks(tester);
    });

    testWidgets('no signal on the first open, nothing saved: no card, attendance as always', (tester) async {
      final remote = FakeToolsRemote()..failReads = refusal('no signal');
      await showShell(tester, tools: tools(remote));
      expect(find.byKey(const Key('tools-card')), findsNothing);
      await timeInWorks(tester);
    });
  });
}
