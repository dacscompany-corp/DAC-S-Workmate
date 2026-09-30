import 'dart:async';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:workmate/attendance/domain/attendance_failure.dart';

PostgrestException rpcError(String code) => PostgrestException(message: code, code: 'P0001');

void main() {
  test('the whole documented error surface is mapped', () {
    const expected = {
      'ALREADY_TIMED_IN': AttendanceFailure.alreadyTimedIn,
      'NOT_TIMED_IN': AttendanceFailure.notTimedIn,
      'ALREADY_COMPLETE': AttendanceFailure.alreadyComplete,
      'TIMEOUT_BEFORE_TIMEIN': AttendanceFailure.timeOutBeforeTimeIn,
      'CAPTURED_IN_FUTURE': AttendanceFailure.deviceClockWrong,
      'SHIFT_TOO_LONG': AttendanceFailure.shiftTooLong,
      'PROJECT_UNAVAILABLE': AttendanceFailure.projectUnavailable,
      'NO_OWNER_ASSIGNED': AttendanceFailure.noOwnerAssigned,
      'ACCOUNT_INACTIVE': AttendanceFailure.accountInactive,
      'NOT_A_WORKER': AttendanceFailure.notAWorker,
      'AUTH_REQUIRED': AttendanceFailure.sessionExpired,
      'OUTSIDE_RADIUS': AttendanceFailure.outsideRadius,
      'MOCK_LOCATION': AttendanceFailure.mockLocation,
      'PERMISSION_DENIED': AttendanceFailure.locationPermissionDenied,
      'LOCATION_DISABLED': AttendanceFailure.locationDisabled,
      'PROJECT_GEOFENCE_UNAVAILABLE': AttendanceFailure.projectGeofenceUnavailable,
      'APP_UPDATE_REQUIRED': AttendanceFailure.appUpdateRequired,
      'EVENT_ID_CONFLICT': AttendanceFailure.unexpected,
      'EVENT_ID_REQUIRED': AttendanceFailure.unexpected,
    };
    expected.forEach((code, failure) => expect(AttendanceFailure.of(rpcError(code)), failure, reason: code));
  });

  test('PROJECT_GEOFENCE_UNAVAILABLE is not mistaken for PROJECT_UNAVAILABLE', () {
    expect(AttendanceFailure.of(rpcError('PROJECT_GEOFENCE_UNAVAILABLE')),
        AttendanceFailure.projectGeofenceUnavailable);
  });

  test('no signal is never reported as a rejected submission', () {
    expect(AttendanceFailure.of(const SocketException('dns')), AttendanceFailure.noConnection);
    expect(AttendanceFailure.of(TimeoutException('slow')), AttendanceFailure.noConnection);
    expect(AttendanceFailure.of(http.ClientException('closed')), AttendanceFailure.noConnection);
    expect(AttendanceFailure.of(AuthRetryableFetchException(message: 'offline')), AttendanceFailure.noConnection);
  });

  test('an unrecognised database error does not masquerade as a known one', () {
    expect(AttendanceFailure.of(rpcError('SOME_NEW_CODE_FROM_A_LATER_MIGRATION')), AttendanceFailure.unexpected);
  });
}
