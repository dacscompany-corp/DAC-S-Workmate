import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:workmate/attendance/domain/attendance_record.dart';
import 'package:workmate/attendance/domain/work_date.dart';
import 'package:workmate/attendance/home/home_controller.dart';
import 'package:workmate/attendance/home/home_screen.dart';
import 'package:workmate/attendance/ui/attendance_copy.dart';
import 'package:workmate/auth/worker_profile.dart';
import 'package:workmate/ui/theme.dart';

import '../fakes.dart';

void main() {
  late FakeAttendance attendance;
  late FakeScheduler scheduler;
  late List<TimeDirection> started;
  late int seeAll;
  late int exitDismissed;
  final now = DateTime.parse('2026-08-19T02:00:00Z'); // 10:00 AM, Wednesday 19 Aug, Manila
  const worker = WorkerProfile(id: 'u1', displayName: 'Juan dela Cruz', position: 'Mason', workerNo: 42);

  Future<void> show(WidgetTester tester, {Bilingual? exit}) async {
    useTallPhone(tester);
    final c = HomeController(attendance: attendance, scheduler: scheduler, now: () => now);
    await tester.pumpWidget(MaterialApp(
      theme: workMateTheme(),
      home: Scaffold(
        body: HomeScreen(
          worker: worker,
          controller: c,
          onStartFlow: started.add,
          onSeeHistory: () => seeAll++,
          openSettings: (_) {},
          exitNotice: exit,
          onDismissExit: () => exitDismissed++,
        ),
      ),
    ));
    await c.refresh();
    await tester.pumpAndSettle();
  }

  setUp(() {
    attendance = FakeAttendance();
    scheduler = FakeScheduler();
    started = [];
    seeAll = 0;
    exitDismissed = 0;
  });

  testWidgets('a fresh day offers Time In and says nothing is recorded yet', (tester) async {
    await show(tester);
    expect(find.text('Juan dela Cruz'), findsOneWidget);
    expect(find.text('WEDNESDAY'), findsOneWidget);
    expect(find.text('19 August 2026'), findsOneWidget);
    expect(find.text('STEP 1 OF 4'), findsOneWidget);
    expect(find.text('Tap to start your day'), findsOneWidget);
    expect(find.text('project · photo · check · submit'), findsOneWidget);
    expect(find.text('You have not timed in yet'), findsOneWidget);
    await tester.tap(find.byKey(const Key('hero-time-in')));
    expect(started, [TimeDirection.timeIn]);
  });

  testWidgets('while working: Time Out, the hours so far, and an honest "not sent yet"', (tester) async {
    attendance.todayRecord = AttendanceRecord(
      id: 'r',
      workDate: '2026-08-19',
      status: AttendanceStatus.working,
      timeInAt: DateTime.parse('2026-08-18T23:45:00Z'),
      timeInProjectName: abc.name,
      pending: true,
    );
    await show(tester);
    expect(find.text('Timed in at 7:45 AM'), findsOneWidget);
    expect(find.text('Not sent yet'), findsOneWidget);
    expect(find.text('Saved on this phone. It will send when there is signal.'), findsOneWidget);
    expect(find.text('Hours so far'), findsOneWidget);
    expect(find.text('2h 15m'), findsOneWidget);
    expect(find.text('Since 7:45 AM'), findsOneWidget);
    expect(find.text('You have not timed in yet'), findsNothing);
    await tester.tap(find.byKey(const Key('hero-time-out')));
    expect(started, [TimeDirection.timeOut]);
  });

  testWidgets("a closed day shows the server's total and no button", (tester) async {
    attendance.todayRecord = AttendanceRecord(
      id: 'r',
      workDate: '2026-08-19',
      status: AttendanceStatus.complete,
      timeInAt: DateTime.parse('2026-08-18T23:45:00Z'),
      timeOutAt: DateTime.parse('2026-08-19T09:30:00Z'),
      totalMinutes: 585,
    );
    await show(tester);
    expect(find.text('Saved'), findsOneWidget);
    expect(find.text('Total hours'), findsOneWidget);
    expect(find.text('9h 45m'), findsOneWidget);
    expect(find.text('Day complete'), findsOneWidget);
    expect(find.byKey(const Key('hero-time-in')), findsNothing);
    expect(find.byKey(const Key('hero-time-out')), findsNothing);
  });

  testWidgets('no signal and nothing on the phone: Time In is still offered', (tester) async {
    attendance.todayError = const SocketException('down');
    await show(tester);
    expect(find.text('No signal right now. Try again in a moment.'), findsOneWidget);
    expect(find.text('Walang signal ngayon. Subukan ulit mamaya.'), findsOneWidget);
    expect(find.byKey(const Key('hero-time-in')), findsOneWidget);
    expect(find.text('You have not timed in yet'), findsNothing);
  });

  testWidgets('a server refusal hides the button', (tester) async {
    attendance.todayError = const PostgrestException(message: 'ACCOUNT_INACTIVE', code: 'P0001');
    await show(tester);
    expect(find.text('This account is turned off. Call the office.'), findsOneWidget);
    expect(find.byKey(const Key('hero-time-in')), findsNothing);
  });

  testWidgets('a refused submission is explained until dismissed', (tester) async {
    attendance.refused = [refusedRow()];
    await show(tester);
    expect(find.text('Your Time In on 19 Aug was not accepted.'), findsOneWidget);
    expect(find.text('You are too far from the project to record attendance. Move closer to the site and try again.'),
        findsOneWidget);
    await tester.tap(find.text(dismissLabel));
    await tester.pumpAndSettle();
    expect(attendance.dismissed, ['e9']);
    expect(find.text('Your Time In on 19 Aug was not accepted.'), findsNothing);
  });

  testWidgets('the exit notice explains a cancelled flow', (tester) async {
    await show(tester, exit: flowCancelledByCamera(TimeDirection.timeIn));
    expect(find.text('Time In was not recorded. The camera permission is off, and the photo is the proof of attendance.'),
        findsOneWidget);
    await tester.tap(find.text(dismissLabel));
    expect(exitDismissed, 1);
  });

  testWidgets('pulling down re-reads today', (tester) async {
    await show(tester);
    await tester.pumpAndSettle();
    expect(scheduler.sendNows, 1);
    await tester.fling(find.byType(ListView), const Offset(0, 400), 1000);
    await tester.pumpAndSettle();
    expect(scheduler.sendNows, 2);
  });

  testWidgets('See all opens History', (tester) async {
    await show(tester);
    await tester.tap(find.text('See all'));
    expect(seeAll, 1);
  });

  testWidgets('today is marked worked on the strip as soon as the phone has a record', (tester) async {
    attendance.todayRecord = AttendanceRecord(
      id: 'r',
      workDate: '2026-08-19',
      status: AttendanceStatus.working,
      timeInAt: DateTime.parse('2026-08-18T23:45:00Z'),
      pending: true,
    );
    await show(tester);
    expect(find.byKey(const Key('week-dot-2026-08-19-worked')), findsOneWidget);
  });
}
