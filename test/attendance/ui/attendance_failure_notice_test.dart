import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:workmate/attendance/domain/attendance_failure.dart';
import 'package:workmate/attendance/domain/work_date.dart';
import 'package:workmate/attendance/ui/attendance_copy.dart';
import 'package:workmate/attendance/ui/attendance_failure_notice.dart';
import 'package:workmate/ui/theme.dart';

Widget wrap(Widget w) => MaterialApp(theme: workMateTheme(), home: Scaffold(body: w));

void main() {
  testWidgets('both languages, and TRY AGAIN where it can help', (tester) async {
    var retries = 0;
    await tester.pumpWidget(wrap(AttendanceFailureNotice(failure: AttendanceFailure.noConnection, onRetry: () => retries++)));
    expect(find.text('No signal right now. Try again in a moment.'), findsOneWidget);
    expect(find.text('Walang signal ngayon. Subukan ulit mamaya.'), findsOneWidget);
    await tester.tap(find.text(retryLabel));
    expect(retries, 1);
  });

  testWidgets('no TRY AGAIN where a second attempt cannot succeed', (tester) async {
    await tester.pumpWidget(wrap(AttendanceFailureNotice(failure: AttendanceFailure.alreadyTimedIn, onRetry: () {})));
    expect(find.text('You already timed in today.'), findsOneWidget);
    expect(find.text(retryLabel), findsNothing);
  });

  testWidgets('Location switched off offers the Location screen, not the app page', (tester) async {
    final routes = <SettingsRoute>[];
    await tester.pumpWidget(wrap(AttendanceFailureNotice(failure: AttendanceFailure.locationDisabled, onOpenSettings: routes.add)));
    await tester.tap(find.text(openSettingsLabel));
    expect(routes, [SettingsRoute.locationSwitch]);
  });

  testWidgets('a lead line and a Dismiss', (tester) async {
    var dismissed = 0;
    await tester.pumpWidget(wrap(AttendanceFailureNotice(
      failure: AttendanceFailure.outsideRadius,
      lead: refusedLead(TimeDirection.timeIn, '19 Aug'),
      onDismiss: () => dismissed++,
    )));
    expect(find.text('Your Time In on 19 Aug was not accepted.'), findsOneWidget);
    expect(find.text('Hindi tinanggap ang Time In mo noong 19 Aug.'), findsOneWidget);
    await tester.tap(find.text(dismissLabel));
    expect(dismissed, 1);
  });
}
