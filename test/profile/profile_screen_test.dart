import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:supabase_flutter/supabase_flutter.dart' show AuthException;
import 'package:workmate/agreements/domain/my_agreement.dart';
import 'package:workmate/agreements/ui/agreements_controller.dart';
import 'package:workmate/auth/worker_profile.dart';
import 'package:workmate/profile/account_services.dart';
import 'package:workmate/profile/profile_screen.dart';
import 'package:workmate/terms/attendance_terms.dart';
import 'package:workmate/tools/ui/tools_controller.dart';
import 'package:workmate/ui/theme.dart';

import '../agreements/agreement_fakes.dart';
import '../attendance/fakes.dart';
import '../tools/tool_fakes.dart';

void main() {
  const juan = WorkerProfile(
      id: 'u1', email: 'juan@x.com', displayName: 'Juan dela Cruz', position: 'Mason', workerNo: 42, role: 'worker', status: 'active');
  late List<String> saved;
  Object? saveError;
  DateTime? acceptedAt;

  Future<void> show(WidgetTester tester,
      {ToolsController? tools, VoidCallback? onTools, AgreementsController? agreements, VoidCallback? onAgreements, bool buyer = false}) async {
    useTallPhone(tester);
    await tester.pumpWidget(MaterialApp(
      theme: workMateTheme(),
      home: Scaffold(
        body: ProfileScreen(
          worker: juan,
          versionName: '0.3.0',
          onSignOut: () async {},
          buyer: buyer,
          tools: tools,
          onOpenTools: onTools,
          agreements: agreements,
          onOpenAgreements: onAgreements,
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

  testWidgets('the profile card, the ACCOUNT section and a full-width Log out', (tester) async {
    await show(tester);
    expect(find.text('Profile'), findsOneWidget);
    expect(find.text('Mason · W-0042'), findsOneWidget);
    expect(find.text('ACCOUNT'), findsOneWidget);
    expect(find.text('MINE'), findsNothing, reason: 'nothing of theirs is on');
    final logout = tester.getSize(find.widgetWithText(OutlinedButton, 'Log out'));
    expect([logout.width, logout.height], [360.0, 52.0], reason: '400 wide phone, 20 each side');
  });

  test('the tools line', () {
    expect(toolsLine(0, 0), 'No tools with you');
    expect(toolsLine(1, 0), '1 tool with you');
    expect(toolsLine(2, 1), '2 tools with you · 1 problem reported');
    expect(toolsLine(3, 2), '3 tools with you · 2 problems reported');
  });

  testWidgets('MINE: My tools counts tools and problems, and opens Tools', (tester) async {
    final tools = ToolsController(remote: FakeToolsRemote(), userId: 'u7', isLeader: false);
    await tools.refresh();
    var opened = 0;
    await show(tester, tools: tools, onTools: () => opened++);
    expect(find.text('MINE'), findsOneWidget);
    expect(find.text('2 tools with you · 1 problem reported'), findsOneWidget);
    await tester.tap(find.byKey(const Key('profile-tools')));
    expect(opened, 1);
  });

  testWidgets('MINE: tools switched off — no row, and no MINE at all', (tester) async {
    final tools = ToolsController(remote: FakeToolsRemote()..failMine = refusal('TOOLS_OFF'), userId: 'u7', isLeader: false);
    await tools.refresh();
    await show(tester, tools: tools);
    expect(find.byKey(const Key('profile-tools')), findsNothing);
    expect(find.text('MINE'), findsNothing);
  });

  // Moved here from agreements_screens_test ("the Home card shows only after a read found agreements").
  testWidgets('MINE: My agreements shows only after a read found agreements — and never an amount', (tester) async {
    final remote = FakeAgreementsRemote();
    final a = AgreementsController(remote: remote, userId: 'w13', now: () => DateTime.utc(2026, 11, 8, 2, 30));
    await show(tester, agreements: a);
    expect(find.byKey(const Key('profile-agreements')), findsNothing);
    remote.answers.add([
      for (final x in (jsonDecode(myAgreementsJson)['agreements'] as List)) MyAgreement.fromJson(Map<String, dynamic>.from(x as Map)),
    ]);
    await a.refresh();
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('profile-agreements')), findsOneWidget);
    expect(find.text('4 agreements'), findsOneWidget);
    expect(find.textContaining('₱'), findsNothing);
    remote.answers.add(noSignal);
    await a.refresh();
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('profile-agreements')), findsNothing);
  });

  testWidgets('a buyer: no MINE and no Terms, even with tools wired in', (tester) async {
    final tools = ToolsController(remote: FakeToolsRemote(), userId: 'u7', isLeader: false);
    await tools.refresh();
    await show(tester, tools: tools, buyer: true);
    expect(find.text('MINE'), findsNothing);
    expect(find.byKey(const Key('profile-terms')), findsNothing);
  });
}
