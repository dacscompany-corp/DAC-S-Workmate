import 'dart:async';
import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:workmate/agreements/agreements_services.dart';
import 'package:workmate/agreements/data/agreements_remote.dart';
import 'package:workmate/agreements/domain/my_agreement.dart';
import 'package:workmate/attendance/attendance_services.dart';
import 'package:workmate/attendance/sync/queue_settled.dart';
import 'package:workmate/auth/worker_profile.dart';
import 'package:workmate/profile/account_services.dart';
import 'package:workmate/ui/home_shell.dart';
import 'package:workmate/ui/theme.dart';

import '../agreements/agreement_fakes.dart';
import '../attendance/fakes.dart';

Widget wrap(Widget w) => MaterialApp(theme: workMateTheme(), home: w);

const juan = WorkerProfile(id: 'w13', displayName: 'Juan Cruz', position: 'Mason', workerNo: 13, role: 'worker');
const other = WorkerProfile(id: 'w15', displayName: 'Juan Cruz', position: 'Tiler', workerNo: 15, role: 'worker');

/// Answers ll_my_agreements per signed-in account, as the server does. A
/// [gate] holds the answer back (the phone is still checking); [fail] makes it
/// fail the way no signal does.
class PerAccountRemote implements AgreementsRemote {
  PerAccountRemote(this.byUser);
  final Map<String, List<MyAgreement>> byUser;
  final asked = <String>[];
  Completer<void>? gate;
  Object? fail;

  @override
  Future<List<MyAgreement>> mine({required String userId}) async {
    asked.add(userId);
    final g = gate;
    if (g != null) await g.future;
    final f = fail;
    if (f != null) throw f;
    return byUser[userId] ?? const [];
  }
}

List<MyAgreement> juansAgreements() => [
      for (final a in (jsonDecode(myAgreementsJson)['agreements'] as List)) MyAgreement.fromJson(Map<String, dynamic>.from(a as Map)),
    ];

void main() {
  late QueueSettled settled;

  setUp(() async {
    // ignore: invalid_use_of_visible_for_testing_member
    SharedPreferences.resetStatic();
    SharedPreferences.setMockInitialValues({});
    settled = QueueSettled();
  });

  Widget shell(WorkerProfile who, AgreementsServices? agreements) => HomeShell(
        key: const ValueKey('one-home'),
        worker: who,
        versionName: '0.11.0',
        onSignOut: () async {},
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
        account: AccountServices(changePassword: (_) async {}, termsAcceptedAt: () async => null),
        agreements: agreements,
      );

  testWidgets('a linked worker gets the My agreements shortcut and a Profile row, and it opens their agreements', (tester) async {
    useTallPhone(tester);
    final remote = PerAccountRemote({'w13': juansAgreements()});
    await tester.pumpWidget(wrap(shell(juan, AgreementsServices(remote: remote))));
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('shortcut-agreements')), findsOneWidget);
    expect(find.textContaining('₱'), findsNothing, reason: 'no amount on Home');
    await tester.tap(find.text('Profile'));
    await tester.pumpAndSettle();
    expect(find.text('4 agreements'), findsOneWidget);
    expect(find.textContaining('₱'), findsNothing, reason: 'no amount on Profile');
    await tester.tap(find.text('Home'));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('shortcut-agreements')));
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('agreement-a-main')), findsOneWidget);
    expect(remote.asked.toSet(), {'w13'});
  });

  testWidgets('no linked agreement, or no signal: no shortcut, and nothing else on Home changes', (tester) async {
    useTallPhone(tester);
    final remote = FakeAgreementsRemote()..answers.add(noSignal);
    await tester.pumpWidget(wrap(shell(juan, AgreementsServices(remote: remote))));
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('shortcut-agreements')), findsNothing);
    expect(find.text('Time In'), findsWidgets);
  });

  testWidgets('another account on the same Home never sees the last account’s agreements', (tester) async {
    useTallPhone(tester);
    final remote = PerAccountRemote({'w13': juansAgreements()});
    final services = AgreementsServices(remote: remote);
    await tester.pumpWidget(wrap(shell(juan, services)));
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('shortcut-agreements')), findsOneWidget);
    // Same Home widget, another worker (same name, other account): a fresh read for that account.
    await tester.pumpWidget(wrap(shell(other, services)));
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('shortcut-agreements')), findsNothing);
    expect(remote.asked.last, 'w15');
  });

  testWidgets('reopening My agreements with no signal: no old figure while checking, and none after', (tester) async {
    useTallPhone(tester);
    final remote = PerAccountRemote({'w13': juansAgreements()});
    await tester.pumpWidget(wrap(shell(juan, AgreementsServices(remote: remote))));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('shortcut-agreements')));
    await tester.pumpAndSettle();
    expect(find.textContaining('₱'), findsWidgets);
    await tester.pageBack();
    await tester.pumpAndSettle();
    // The signal goes; the worker opens My agreements again.
    remote
      ..gate = Completer<void>()
      ..fail = noSignal;
    await tester.tap(find.byKey(const Key('shortcut-agreements')));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 400));
    expect(find.textContaining('₱'), findsNothing, reason: 'an old figure while checking');
    expect(find.textContaining('Checking your agreements'), findsOneWidget);
    remote.gate!.complete();
    await tester.pumpAndSettle();
    expect(find.textContaining('₱'), findsNothing, reason: 'an old figure after the failure');
    expect(find.textContaining('Needs signal to show your agreements'), findsOneWidget);
  });

  testWidgets('back in the app with a detail open, after an unlink: no old figure while checking, and none after', (tester) async {
    useTallPhone(tester);
    final remote = PerAccountRemote({'w13': juansAgreements()});
    await tester.pumpWidget(wrap(shell(juan, AgreementsServices(remote: remote))));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('shortcut-agreements')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('agreement-a-main')));
    await tester.pumpAndSettle();
    expect(find.text('₱50,000.00'), findsOneWidget);
    // While the app was away, the office unlinked that agreement.
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.paused);
    remote
      ..byUser['w13'] = juansAgreements().where((a) => a.id != 'a-main').toList()
      ..gate = Completer<void>();
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
    await tester.pump();
    expect(find.textContaining('₱'), findsNothing, reason: 'an old figure while checking');
    expect(find.textContaining('Checking your agreements'), findsOneWidget);
    remote.gate!.complete();
    await tester.pumpAndSettle();
    expect(find.textContaining('₱'), findsNothing, reason: 'an unlinked agreement’s figures after the answer');
    expect(find.textContaining('isn’t shown to you any more'), findsOneWidget);
  });

  testWidgets('without the service (an older setup), Home shows no shortcut at all', (tester) async {
    useTallPhone(tester);
    await tester.pumpWidget(wrap(shell(juan, null)));
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('shortcut-agreements')), findsNothing);
  });
}
