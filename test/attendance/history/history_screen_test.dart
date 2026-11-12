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

  Future<HistoryController> show(WidgetTester tester, {PhotoUrl? photoUrl}) async {
    useTallPhone(tester);
    final c = HistoryController(attendance: attendance, now: () => now);
    await tester.pumpWidget(MaterialApp(
      theme: workMateTheme(),
      home: Scaffold(body: HistoryScreen(controller: c, photoUrl: photoUrl ?? (_) async => null)),
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

  AttendanceRecord closedDay({String? outProject, String? inPhoto, String? outPhoto, bool pending = false}) => AttendanceRecord(
        id: 'a',
        workDate: '2026-08-24',
        status: AttendanceStatus.complete,
        timeInAt: DateTime.parse('2026-08-24T00:00:00Z'),
        timeOutAt: DateTime.parse('2026-08-24T09:45:00Z'),
        timeInProjectName: abc.name,
        timeOutProjectName: outProject ?? abc.name,
        totalMinutes: 585,
        timeInPhotoPath: inPhoto,
        timeOutPhotoPath: outPhoto,
        pending: pending,
      );

  final card = find.byKey(const Key('day-2026-08-24'));
  Finder inCard(Finder f) => find.descendant(of: card, matching: f);

  testWidgets('Week / Month is one switch that says which half is chosen', (tester) async {
    await show(tester);
    final handle = tester.ensureSemantics();
    expect(tester.getSemantics(find.byKey(const Key('span-week'))), containsSemantics(isSelected: true));
    expect(tester.getSemantics(find.byKey(const Key('span-month'))), containsSemantics(isSelected: false));
    expect(tester.getSize(find.byKey(const Key('span-week'))).width, tester.getSize(find.byKey(const Key('span-month'))).width);
    await tester.tap(find.byKey(const Key('span-month')));
    await tester.pumpAndSettle();
    expect(tester.getSemantics(find.byKey(const Key('span-month'))), containsSemantics(isSelected: true));
    expect(attendance.historyCalls.last, ('2026-08-01', '2026-08-26'));
    handle.dispose();
  });

  testWidgets('a day card: Time In and Time Out side by side, one place line, no photo asked for', (tester) async {
    final asked = <String?>[];
    attendance.historyRecords = [closedDay(inPhoto: 'in.jpg', outPhoto: 'out.jpg')];
    await show(tester, photoUrl: (p) async {
      asked.add(p);
      return null;
    });
    final timeIn = tester.getTopLeft(inCard(find.text('Time In')));
    final timeOut = tester.getTopLeft(inCard(find.text('Time Out')));
    expect(timeOut.dy, timeIn.dy, reason: 'side by side');
    expect(timeOut.dx, greaterThan(timeIn.dx));
    expect(inCard(find.text(abc.name)), findsOneWidget, reason: 'the same project is named once');
    expect(asked, isEmpty, reason: 'photos are fetched only when the day is opened');
  });

  testWidgets('a day that ended at another project names both', (tester) async {
    attendance.historyRecords = [closedDay(outProject: 'Villa Verde')];
    await show(tester);
    expect(inCard(find.text('In: ${abc.name} · Out: Villa Verde')), findsOneWidget);
  });

  testWidgets('tapping a day opens its sheet: pills, both legs, the places; then the photos are asked for', (tester) async {
    final asked = <String?>[];
    attendance.historyRecords = [closedDay(outProject: 'Villa Verde', inPhoto: 'in.jpg', outPhoto: 'out.jpg', pending: true)];
    await show(tester, photoUrl: (p) async {
      asked.add(p);
      return null;
    });
    await tester.tap(card);
    await tester.pumpAndSettle();
    final sheet = find.byKey(const Key('day-sheet'));
    Finder inSheet(Finder f) => find.descendant(of: sheet, matching: f);
    expect(sheet, findsOneWidget);
    expect(inSheet(find.text('Monday, 24 Aug')), findsOneWidget);
    expect(inSheet(find.text('Not sent yet')), findsOneWidget);
    expect(inSheet(find.text('9h 45m')), findsOneWidget);
    expect(inSheet(find.text('8:00 AM')), findsOneWidget);
    expect(inSheet(find.text('5:45 PM')), findsOneWidget);
    expect(inSheet(find.text(abc.name)), findsOneWidget);
    expect(inSheet(find.text('Villa Verde')), findsOneWidget);
    expect(asked.toSet(), {'in.jpg', 'out.jpg'});
    expect(find.byKey(const Key('day-photo-in')), findsNothing, reason: 'no link, nothing to open');
  });

  testWidgets('an open day in the sheet: Time Out is "not yet" and names no place', (tester) async {
    attendance.historyRecords = [
      AttendanceRecord(
        id: 'b',
        workDate: '2026-08-26',
        status: AttendanceStatus.working,
        timeInAt: DateTime.parse('2026-08-25T23:45:00Z'),
        timeInProjectName: abc.name,
        timeOutProjectName: 'Should not show',
      ),
    ];
    await show(tester);
    await tester.tap(find.byKey(const Key('day-2026-08-26')));
    await tester.pumpAndSettle();
    final sheet = find.byKey(const Key('day-sheet'));
    expect(find.descendant(of: sheet, matching: find.text('not yet')), findsOneWidget);
    expect(find.descendant(of: sheet, matching: find.text('Working')), findsOneWidget);
    expect(find.text('Should not show'), findsNothing);
  });

  testWidgets('a photo that has a link can be opened full screen', (tester) async {
    attendance.historyRecords = [closedDay(inPhoto: 'in.jpg')];
    await show(tester, photoUrl: (p) async => 'https://example.invalid/$p');
    await tester.tap(card);
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('day-photo-in')), findsOneWidget);
    expect(find.byKey(const Key('day-photo-out')), findsNothing, reason: 'no Time Out photo');
    expect(
      find.byWidgetPredicate((w) => w is Semantics && w.properties.label == 'Time In photo, open full screen' && w.properties.button == true),
      findsOneWidget,
      reason: 'TalkBack hears what the photo opens',
    );
    await tester.tap(find.byKey(const Key('day-photo-in')));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 400));
    expect(find.byType(PhotoViewer), findsOneWidget);
    expect(find.text('Time In · 8:00 AM'), findsOneWidget);
  });

  testWidgets('a day with no record opens nothing', (tester) async {
    await show(tester);
    await tester.tap(find.text('No record').first);
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('day-sheet')), findsNothing);
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
