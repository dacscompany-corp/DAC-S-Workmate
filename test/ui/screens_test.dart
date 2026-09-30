import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:workmate/auth/login_failure.dart';
import 'package:workmate/auth/worker_profile.dart';
import 'package:workmate/terms/attendance_terms.dart';
import 'package:workmate/ui/home_shell.dart';
import 'package:workmate/ui/login_screen.dart';
import 'package:workmate/ui/terms_screen.dart';
import 'package:workmate/ui/theme.dart';

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

  testWidgets('home greets the worker and says Attendance is still in the old app', (tester) async {
    await tester.pumpWidget(wrap(HomeShell(
      worker: const WorkerProfile(id: 'u1', displayName: 'Juan dela Cruz', position: 'Mason', workerNo: 42),
      versionName: '0.1.0',
      onSignOut: () async {},
    )));
    expect(find.text('Juan dela Cruz'), findsOneWidget);
    expect(find.text('Mason · W-0042'), findsOneWidget);
    expect(find.textContaining('DACS Attendance'), findsWidgets);
  });
}
