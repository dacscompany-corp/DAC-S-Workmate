import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:supabase_flutter/supabase_flutter.dart' show AuthException;
import 'package:workmate/auth/worker_profile.dart';
import 'package:workmate/profile/account_services.dart';
import 'package:workmate/profile/profile_screen.dart';
import 'package:workmate/terms/attendance_terms.dart';
import 'package:workmate/ui/theme.dart';

import '../attendance/fakes.dart';

void main() {
  const juan = WorkerProfile(
      id: 'u1', email: 'juan@x.com', displayName: 'Juan dela Cruz', position: 'Mason', workerNo: 42, role: 'worker', status: 'active');
  late List<String> saved;
  Object? saveError;
  DateTime? acceptedAt;

  Future<void> show(WidgetTester tester) async {
    useTallPhone(tester);
    await tester.pumpWidget(MaterialApp(
      theme: workMateTheme(),
      home: Scaffold(
        body: ProfileScreen(
          worker: juan,
          versionName: '0.3.0',
          onSignOut: () async {},
          account: AccountServices(
            changePassword: (p) async {
              if (saveError != null) throw saveError!;
              saved.add(p);
            },
            termsAcceptedAt: () async => acceptedAt,
          ),
        ),
      ),
    ));
    await tester.pumpAndSettle();
  }

  setUp(() {
    saved = [];
    saveError = null;
    acceptedAt = null;
  });

  testWidgets('shows the account: email, position, worker ID, active', (tester) async {
    await show(tester);
    expect(find.text('Active account'), findsOneWidget);
    expect(find.text('juan@x.com'), findsOneWidget);
    expect(find.text('Mason'), findsWidgets);
    expect(find.text('W-0042'), findsOneWidget);
    expect(find.text('Log out'), findsOneWidget);
    expect(find.textContaining("DAC'S WorkMate 0.3.0"), findsOneWidget);
  });

  testWidgets('the Terms row shows the Manila date they were accepted', (tester) async {
    acceptedAt = DateTime.utc(2026, 8, 2, 17); // 01:00 on 3 Aug in Manila
    await show(tester);
    expect(find.text('Accepted 3 Aug 2026'), findsOneWidget);
  });

  testWidgets('with no known date the Terms row still offers them', (tester) async {
    await show(tester);
    expect(find.text('Read the terms you accepted'), findsOneWidget);
    await tester.tap(find.byKey(const Key('profile-terms')));
    await tester.pumpAndSettle();
    expect(find.text(AttendanceTerms.clauses.first.english), findsOneWidget);
  });

  Future<void> openSheet(WidgetTester tester) async {
    await tester.tap(find.byKey(const Key('profile-change-password')));
    await tester.pumpAndSettle();
  }

  testWidgets('a short password is refused on the phone, in both languages', (tester) async {
    await show(tester);
    await openSheet(tester);
    await tester.enterText(find.byKey(const Key('new-password')), 'abc');
    await tester.enterText(find.byKey(const Key('confirm-password')), 'abc');
    await tester.tap(find.text('SAVE PASSWORD'));
    await tester.pumpAndSettle();
    expect(find.text('Use at least 8 characters.'), findsOneWidget);
    expect(find.text('Kailangan ng 8 letra o numero pataas.'), findsOneWidget);
    expect(saved, isEmpty);
  });

  testWidgets('a mismatch is refused on the phone', (tester) async {
    await show(tester);
    await openSheet(tester);
    await tester.enterText(find.byKey(const Key('new-password')), 'bagongpass1');
    await tester.enterText(find.byKey(const Key('confirm-password')), 'bagongpass2');
    await tester.tap(find.text('SAVE PASSWORD'));
    await tester.pumpAndSettle();
    expect(find.text('The two passwords do not match.'), findsOneWidget);
    expect(saved, isEmpty);
  });

  testWidgets('the server refusing a reused password is explained', (tester) async {
    saveError = const AuthException('New password should be different from the old password.', code: 'same_password');
    await show(tester);
    await openSheet(tester);
    await tester.enterText(find.byKey(const Key('new-password')), 'bagongpass1');
    await tester.enterText(find.byKey(const Key('confirm-password')), 'bagongpass1');
    await tester.tap(find.text('SAVE PASSWORD'));
    await tester.pumpAndSettle();
    expect(find.text('That is your current password. Pick a different one.'), findsOneWidget);
    expect(find.text('SAVE PASSWORD'), findsOneWidget); // still open
  });

  testWidgets('a saved password closes the sheet and says so', (tester) async {
    await show(tester);
    await openSheet(tester);
    await tester.enterText(find.byKey(const Key('new-password')), 'bagongpass1');
    await tester.enterText(find.byKey(const Key('confirm-password')), 'bagongpass1');
    await tester.tap(find.text('SAVE PASSWORD'));
    await tester.pumpAndSettle();
    expect(saved, ['bagongpass1']);
    expect(find.text('SAVE PASSWORD'), findsNothing);
    expect(find.text('Your password has been changed.'), findsOneWidget);
  });
}
