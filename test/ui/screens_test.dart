import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:workmate/attendance/attendance_services.dart';
import 'package:workmate/auth/login_failure.dart';
import 'package:workmate/auth/worker_profile.dart';
import 'package:workmate/terms/attendance_terms.dart';
import 'package:workmate/ui/home_shell.dart';
import 'package:workmate/ui/login_screen.dart';
import 'package:workmate/ui/terms_screen.dart';
import 'package:workmate/ui/theme.dart';

import '../attendance/fakes.dart';

Widget wrap(Widget w) => MaterialApp(theme: workMateTheme(), home: w);

void main() {
  testWidgets('login shows the failure in English and Tagalog', (tester) async {
    await tester.pumpWidget(wrap(LoginScreen(
      initialNotice: null,
      onSignIn: (_, _) async => LoginFailure.wrongCredentials,
    )));
    await tester.enterText(find.byKey(const Key('email')), 'a@b.c');
    await tester.enterText(find.byKey(const Key('password')), 'x');
    await tester.tap(find.text('SIGN IN'));
    await tester.pumpAndSettle();
    expect(find.text('That email and password do not match.'), findsOneWidget);
    expect(find.text('Hindi tugma ang email at password.'), findsOneWidget);
  });

  testWidgets('terms cannot be accepted until the box is ticked', (tester) async {
    var accepted = 0;
    await tester.pumpWidget(wrap(TermsScreen(onAccept: () async {
      accepted++;
      return null;
    })));
    expect(find.text(AttendanceTerms.clauses.first.english), findsOneWidget);
    await tester.tap(find.text('ACCEPT & CONTINUE'));
    await tester.pump();
    expect(accepted, 0);
    await tester.tap(find.text('I have read and I agree.'));
    await tester.pump();
    await tester.tap(find.text('ACCEPT & CONTINUE'));
    await tester.pump();
    expect(accepted, 1);
  });

  AttendanceServices fakeServices() => AttendanceServices(
        attendance: FakeAttendance(),
        device: FakeDevice(),
        scheduler: FakeScheduler(),
        trustedNow: () async => null,
        photoUrl: (_) async => null,
        openSettings: (_) async {},
        cameraStep: (context, args) => const Text('camera'),
      );

  Future<void> showShell(WidgetTester tester) async {
    useTallPhone(tester);
    await tester.pumpWidget(wrap(HomeShell(
      worker: const WorkerProfile(id: 'u1', displayName: 'Juan dela Cruz', position: 'Mason', workerNo: 42),
      versionName: '0.2.0',
      onSignOut: () async {},
      services: fakeServices(),
    )));
    await tester.pumpAndSettle();
  }

  testWidgets('home greets the worker and offers Time In, with History and Profile tabs', (tester) async {
    await showShell(tester);
    expect(find.text('Juan dela Cruz'), findsOneWidget);
    expect(find.text('Mason · W-0042'), findsOneWidget);
    expect(find.byKey(const Key('hero-time-in')), findsOneWidget);
    expect(find.text('History'), findsOneWidget);
    expect(find.text('Profile'), findsOneWidget);
    expect(find.textContaining('DACS Attendance'), findsNothing);
  });

  testWidgets('Time In opens the flow full screen, and Back returns home', (tester) async {
    await showShell(tester);
    await tester.tap(find.byKey(const Key('hero-time-in')));
    await tester.pumpAndSettle();
    expect(find.text('Which project today?'), findsOneWidget);
    expect(find.byType(NavigationBar), findsNothing);
    await tester.tap(find.byKey(const Key('flow-back')));
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('hero-time-in')), findsOneWidget);
    expect(find.byType(NavigationBar), findsOneWidget);
  });

  testWidgets('the History tab shows the worker\'s days', (tester) async {
    await showShell(tester);
    await tester.tap(find.text('History'));
    await tester.pumpAndSettle();
    expect(find.text('My attendance'), findsOneWidget);
  });

  testWidgets('Profile keeps Log out and the version', (tester) async {
    await showShell(tester);
    await tester.tap(find.text('Profile'));
    await tester.pumpAndSettle();
    expect(find.text('Log out'), findsOneWidget);
    expect(find.textContaining("DAC'S WorkMate 0.2.0"), findsOneWidget);
  });
}
