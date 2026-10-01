import 'package:flutter_test/flutter_test.dart';
import 'package:workmate/attendance/domain/attendance_failure.dart';
import 'package:workmate/attendance/domain/work_date.dart';
import 'package:workmate/attendance/ui/attendance_copy.dart';

void main() {
  test('every failure has words in both languages', () {
    for (final f in AttendanceFailure.values) {
      final c = failureCopy(f);
      expect(c.english, isNotEmpty, reason: f.name);
      expect(c.tagalog, isNotEmpty, reason: f.name);
      expect(c.english, isNot(c.tagalog), reason: f.name);
    }
  });

  test("the location refusals carry DACS Attendance's exact words", () {
    expect(failureCopy(AttendanceFailure.outsideRadius).english,
        'You are too far from the project to record attendance. Move closer to the site and try again.');
    expect(failureCopy(AttendanceFailure.locationDisabled).tagalog,
        'I-on ang Location sa telepono mo para makapagtala. Mag-swipe pababa, i-tap ang Location, tapos subukan ulit.');
    expect(failureCopy(AttendanceFailure.noConnection).english, 'No signal right now. Try again in a moment.');
  });

  test('TRY AGAIN is offered only where retrying can help', () {
    for (final f in [
      AttendanceFailure.noConnection,
      AttendanceFailure.unexpected,
      AttendanceFailure.deviceClockWrong,
      AttendanceFailure.outsideRadius,
      AttendanceFailure.projectGeofenceUnavailable,
      AttendanceFailure.locationDisabled,
    ]) {
      expect(worthRetrying(f), isTrue, reason: f.name);
    }
    for (final f in [
      AttendanceFailure.alreadyTimedIn,
      AttendanceFailure.mockLocation,
      AttendanceFailure.locationPermissionDenied,
      AttendanceFailure.accountInactive,
    ]) {
      expect(worthRetrying(f), isFalse, reason: f.name);
    }
  });

  test('the permission and the phone switch send the worker to different screens', () {
    expect(settingsRouteFor(AttendanceFailure.locationPermissionDenied), SettingsRoute.appPermissions);
    expect(settingsRouteFor(AttendanceFailure.locationDisabled), SettingsRoute.locationSwitch);
    expect(settingsRouteFor(AttendanceFailure.outsideRadius), isNull);
  });

  test('a stored refusal reads back; anything else is "something went wrong"', () {
    expect(failureFromStored('outsideRadius'), AttendanceFailure.outsideRadius);
    expect(failureFromStored('PHOTO_MISSING'), AttendanceFailure.unexpected);
    expect(failureFromStored(null), AttendanceFailure.unexpected);
  });

  test('the refused-day line names the half and the day', () {
    final lead = refusedLead(TimeDirection.timeOut, '19 Aug');
    expect(lead.english, 'Your Time Out on 19 Aug was not accepted.');
    expect(lead.tagalog, 'Hindi tinanggap ang Time Out mo noong 19 Aug.');
  });

  test('a camera give-up names the half of the day it cost', () {
    expect(flowCancelledByCamera(TimeDirection.timeIn).english,
        'Time In was not recorded. The camera permission is off, and the photo is the proof of attendance.');
    expect(flowCancelledByCamera(TimeDirection.timeOut).tagalog,
        'Hindi naitala ang Time Out. Naka-off ang camera permission, at ang litrato ang patunay ng pasok.');
  });
}
