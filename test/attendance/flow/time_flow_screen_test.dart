import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:workmate/attendance/domain/location_verification.dart';
import 'package:workmate/attendance/domain/work_date.dart';
import 'package:workmate/attendance/flow/time_flow_controller.dart';
import 'package:workmate/attendance/flow/time_flow_screen.dart';
import 'package:workmate/attendance/ui/attendance_copy.dart';
import 'package:workmate/ui/theme.dart';

import '../fakes.dart';

void main() {
  late FakeAttendance attendance;
  late FakeDevice device;
  late int finished;
  late int cancelled;
  late FlowExit? cancelledWith;
  late List<SettingsRoute> routes;

  Widget fakeCamera(BuildContext context, CameraStepArgs a) => Column(children: [
        Text('camera for ${a.projectName}', style: const TextStyle(color: Colors.white)),
        ElevatedButton(
          onPressed: () => a.onTaken('/nope/raw.jpg', DateTime.parse('2026-08-18T23:45:00Z'), false),
          child: const Text('FAKE SHUTTER'),
        ),
        TextButton(onPressed: a.onGiveUp, child: const Text('GIVE UP')),
      ]);

  Future<TimeFlowController> open(WidgetTester tester, {TimeDirection d = TimeDirection.timeIn}) async {
    useTallPhone(tester);
    final c = TimeFlowController(direction: d, attendance: attendance, device: device, trustedNow: () async => null, newId: () => 'e1');
    await tester.pumpWidget(MaterialApp(
      theme: workMateTheme(),
      home: TimeFlowScreen(
        controller: c,
        cameraStep: fakeCamera,
        onFinished: () => finished++,
        onCancelled: (r) {
          cancelled++;
          cancelledWith = r;
        },
        openSettings: routes.add,
      ),
    ));
    await c.loadProjects();
    await tester.pumpAndSettle();
    return c;
  }

  Future<void> toDescribe(WidgetTester tester) async {
    await tester.tap(find.text(abc.name));
    await tester.pump();
    await tester.tap(find.text('NEXT · TAKE PHOTO'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('FAKE SHUTTER'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('YES, USE THIS PHOTO'));
    await tester.pumpAndSettle();
  }

  Future<void> submit(WidgetTester tester) async {
    await tester.tap(find.byKey(const Key('submit')));
    await tester.pumpAndSettle();
  }

  setUp(() {
    attendance = FakeAttendance();
    device = FakeDevice();
    finished = 0;
    cancelled = 0;
    cancelledWith = null;
    routes = [];
  });

  testWidgets('a whole Time In, tap by tap', (tester) async {
    await open(tester);
    expect(find.text('Which project today?'), findsOneWidget);
    expect(find.text('TIME IN'), findsOneWidget);
    expect(find.text('Step 1 of 4'), findsOneWidget);

    await tester.tap(find.text('NEXT · TAKE PHOTO'));
    await tester.pump();
    expect(find.text('Which project today?'), findsOneWidget, reason: 'no project picked yet');

    await tester.tap(find.text(abc.name));
    await tester.pump();
    await tester.tap(find.text('NEXT · TAKE PHOTO'));
    await tester.pumpAndSettle();
    expect(find.text('Take your photo'), findsOneWidget);
    expect(find.text('camera for ${abc.name}'), findsOneWidget);

    await tester.tap(find.text('FAKE SHUTTER'));
    await tester.pumpAndSettle();
    expect(find.text('Is this photo clear?'), findsOneWidget);

    await tester.tap(find.text('YES, USE THIS PHOTO'));
    await tester.pumpAndSettle();
    expect(find.text('What are you working on?'), findsOneWidget);

    await tester.tap(find.text('Masonry'));
    await tester.pump();
    expect(find.widgetWithText(TextField, 'Masonry'), findsOneWidget);

    await submit(tester);
    expect(find.text('All done!'), findsOneWidget);
    expect(find.text('Your Time In has been recorded'), findsOneWidget);
    expect(find.text('7:45 AM'), findsOneWidget);
    expect(find.text('19 Aug 2026'), findsOneWidget);
    expect(find.text('Saved on your phone'), findsOneWidget);
    expect(find.text('When you head home, time out and pick your project again.'), findsOneWidget);
    expect(attendance.submitted.single.description, 'Masonry');

    await tester.tap(find.text('BACK TO HOME'));
    await tester.pump();
    expect(finished, 1);
  });

  testWidgets('Time Out says so on every screen', (tester) async {
    attendance.savedMinutes = 585;
    await open(tester, d: TimeDirection.timeOut);
    expect(find.text('TIME OUT'), findsOneWidget);
    await toDescribe(tester);
    expect(find.text('SUBMIT TIME OUT'), findsOneWidget);
    await submit(tester);
    expect(find.text('Day complete!'), findsOneWidget);
    expect(find.text('Your Time Out has been recorded'), findsOneWidget);
    expect(find.text('Total hours'), findsOneWidget);
    expect(find.text('9h 45m'), findsOneWidget);
    expect(find.text('Thank you. See you tomorrow.'), findsOneWidget);
  });

  testWidgets('a refusal is shown in both languages and the photo is kept', (tester) async {
    device.fix = const DeviceFix(latitude: 14.5995, longitude: 120.9842, accuracyMetres: 8, isMock: true);
    await open(tester);
    await toDescribe(tester);
    await submit(tester);
    expect(find.text('This phone is reporting a fake location. Turn off any mock location app, then try again.'), findsOneWidget);
    expect(find.text('Nagre-report ang telepono na ito ng pekeng lokasyon. I-off ang anumang mock location app, tapos subukan ulit.'),
        findsOneWidget);
    expect(find.text(retryLabel), findsNothing);
    expect(find.text('What are you working on?'), findsOneWidget);
    expect(attendance.submitted, isEmpty);
  });

  testWidgets('Location switched off sends the worker to the Location switch, then TRY AGAIN works', (tester) async {
    device.fix = const DeviceFix(locationDisabled: true);
    await open(tester);
    await toDescribe(tester);
    await submit(tester);
    await tester.ensureVisible(find.text(openSettingsLabel));
    await tester.tap(find.text(openSettingsLabel));
    await tester.pump();
    expect(routes, [SettingsRoute.locationSwitch]);

    device.fix = const DeviceFix(latitude: 14.5995, longitude: 120.9842, accuracyMetres: 8);
    await tester.ensureVisible(find.text(retryLabel));
    await tester.tap(find.text(retryLabel));
    await tester.pumpAndSettle();
    expect(find.text('All done!'), findsOneWidget);
  });

  testWidgets('back from the first step leaves the flow with nothing to explain', (tester) async {
    await open(tester);
    await tester.tap(find.byKey(const Key('flow-back')));
    await tester.pump();
    expect(cancelled, 1);
    expect(cancelledWith, isNull);
  });

  testWidgets('back from a later step goes one step back', (tester) async {
    await open(tester);
    await toDescribe(tester);
    await tester.tap(find.byKey(const Key('flow-back')));
    await tester.pumpAndSettle();
    expect(find.text('Is this photo clear?'), findsOneWidget);
    expect(cancelled, 0);
  });

  testWidgets('giving up on the camera leaves with the reason', (tester) async {
    await open(tester);
    await tester.tap(find.text(abc.name));
    await tester.pump();
    await tester.tap(find.text('NEXT · TAKE PHOTO'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('GIVE UP'));
    await tester.pump();
    expect(cancelledWith, FlowExit.cameraPermission);
  });

  testWidgets('a failed project list says why and can be retried', (tester) async {
    attendance.projectsError = const SocketException('down');
    await open(tester);
    expect(find.text('No signal right now. Try again in a moment.'), findsOneWidget);
    attendance.projectsError = null;
    await tester.tap(find.text(retryLabel));
    await tester.pumpAndSettle();
    expect(find.text(abc.name), findsOneWidget);
  });

  testWidgets('no projects at all tells the worker who to call', (tester) async {
    attendance.projects = [];
    await open(tester);
    expect(find.text('No projects are listed. Call the office.'), findsOneWidget);
  });
}
