import 'dart:io';
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:workmate/attendance/domain/attendance_record.dart';
import 'package:workmate/attendance/history/history_controller.dart';
import 'package:workmate/attendance/history/history_screen.dart';
import 'package:workmate/attendance/history/photo_viewer.dart';
import 'package:workmate/attendance/ui/attendance_copy.dart';
import 'package:workmate/ui/theme.dart';

import '../fakes.dart';

void main() {
  late FakeAttendance attendance;
  final now = DateTime.parse('2026-08-26T02:00:00Z'); // Wednesday 26 Aug, Manila

  Future<HistoryController> show(WidgetTester tester) async {
    useTallPhone(tester);
    final c = HistoryController(attendance: attendance, now: () => now);
    await tester.pumpWidget(MaterialApp(
      theme: workMateTheme(),
      home: Scaffold(body: HistoryScreen(controller: c, photoUrl: (_) async => null)),
    ));
    await c.refresh();
    await tester.pumpAndSettle();
    return c;
  }

  setUp(() => attendance = FakeAttendance());

  testWidgets('a week with a closed day, a gap and an open day', (tester) async {
    attendance.historyRecords = [
      AttendanceRecord(
        id: 'b',
        workDate: '2026-08-26',
        status: AttendanceStatus.working,
        timeInAt: DateTime.parse('2026-08-25T23:45:00Z'),
        timeInProjectName: abc.name,
      ),
      AttendanceRecord(
        id: 'a',
        workDate: '2026-08-24',
        status: AttendanceStatus.complete,
        timeInAt: DateTime.parse('2026-08-24T00:00:00Z'),
        timeOutAt: DateTime.parse('2026-08-24T09:45:00Z'),
        timeInProjectName: abc.name,
        timeOutProjectName: abc.name,
        totalMinutes: 585,
      ),
    ];
    await show(tester);
    expect(find.text('My attendance'), findsOneWidget);
    expect(find.text('2 days worked'), findsOneWidget);
    expect(find.text('this week'), findsOneWidget);
    expect(find.text('9h 45m'), findsNWidgets(2)); // the total, and the closed day's pill
    expect(find.text('Wednesday, 26 Aug'), findsOneWidget);
    expect(find.text('Working'), findsOneWidget);
    expect(find.text('7:45 AM'), findsOneWidget);
    expect(find.text('not yet'), findsOneWidget);
    expect(find.text('Tuesday, 25 Aug'), findsOneWidget);
    expect(find.text('No record'), findsOneWidget);
    expect(find.text('Monday, 24 Aug'), findsOneWidget);
    expect(find.text('8:00 AM'), findsOneWidget);
    expect(find.text('5:45 PM'), findsOneWidget);
  });

  testWidgets('a day still on the phone says so', (tester) async {
    attendance.historyRecords = [
      AttendanceRecord(
        id: 'b',
        workDate: '2026-08-26',
        status: AttendanceStatus.working,
        timeInAt: DateTime.parse('2026-08-25T23:45:00Z'),
        pending: true,
      ),
    ];
    await show(tester);
    expect(find.text('Not sent yet'), findsOneWidget);
  });

  testWidgets('Month asks for the whole month', (tester) async {
    await show(tester);
    await tester.tap(find.text('Month'));
    await tester.pumpAndSettle();
    expect(attendance.historyCalls.last, ('2026-08-01', '2026-08-26'));
    expect(find.text('this month'), findsOneWidget);
  });

  testWidgets('offline with nothing saved says so, and can be retried', (tester) async {
    attendance.historyError = const SocketException('down');
    await show(tester);
    expect(find.text('No signal right now. Try again in a moment.'), findsOneWidget);
    await tester.tap(find.text(retryLabel));
    await tester.pumpAndSettle();
    expect(attendance.historyCalls.length, 2);
  });

  testWidgets('pulling down reads the days again', (tester) async {
    await show(tester);
    expect(attendance.historyCalls.length, 1);
    await tester.fling(find.byType(ListView), const Offset(0, 400), 1000);
    await tester.pumpAndSettle();
    expect(attendance.historyCalls.length, 2);
  });

  testWidgets('the photo viewer says whose proof it is, and closes', (tester) async {
    await tester.pumpWidget(MaterialApp(
      theme: workMateTheme(),
      home: Builder(
        builder: (context) => TextButton(
          onPressed: () => Navigator.of(context).push(MaterialPageRoute<void>(
            builder: (_) => PhotoViewer(image: MemoryImage(Uint8List(0)), heading: 'Wednesday, 26 Aug', caption: 'Time In · 7:45 AM'),
          )),
          child: const Text('open'),
        ),
      ),
    ));
    await tester.tap(find.text('open'));
    await tester.pumpAndSettle();
    expect(find.text('PROOF'), findsOneWidget);
    expect(find.text('Wednesday, 26 Aug'), findsOneWidget);
    expect(find.text('Time In · 7:45 AM'), findsOneWidget);
    await tester.tap(find.byTooltip('Close'));
    await tester.pumpAndSettle();
    expect(find.text('PROOF'), findsNothing);
  });
}
