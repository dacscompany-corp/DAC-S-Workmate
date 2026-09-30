import 'dart:async';
import 'dart:io';

import 'package:http/http.dart' as http;
import 'package:supabase_flutter/supabase_flutter.dart' show AuthRetryableFetchException;

/// Every way a Time In or Time Out can be refused. The RPCs raise stable codes
/// (0050/0051/0069/0077) precisely so this mapping can exist; anything else is
/// [unexpected], never a guess.
enum AttendanceFailure {
  alreadyTimedIn,
  notTimedIn,
  alreadyComplete,
  timeOutBeforeTimeIn,
  deviceClockWrong,
  shiftTooLong,
  projectUnavailable,
  noOwnerAssigned,
  accountInactive,
  notAWorker,
  outsideRadius,
  mockLocation,
  locationPermissionDenied,
  locationDisabled,
  projectGeofenceUnavailable,
  appUpdateRequired,
  sessionExpired,
  noConnection,
  unexpected;

  // EVENT_ID_CONFLICT / EVENT_ID_REQUIRED are deliberately absent: both mean
  // the app generated a bad event id — our bug, not something to tell a worker.
  // PROJECT_GEOFENCE_UNAVAILABLE does not contain PROJECT_UNAVAILABLE, so the
  // two cannot shadow each other.
  static const _byCode = <String, AttendanceFailure>{
    'ALREADY_TIMED_IN': alreadyTimedIn,
    'NOT_TIMED_IN': notTimedIn,
    'ALREADY_COMPLETE': alreadyComplete,
    'TIMEOUT_BEFORE_TIMEIN': timeOutBeforeTimeIn,
    'CAPTURED_IN_FUTURE': deviceClockWrong,
    'SHIFT_TOO_LONG': shiftTooLong,
    'PROJECT_UNAVAILABLE': projectUnavailable,
    'NO_OWNER_ASSIGNED': noOwnerAssigned,
    'ACCOUNT_INACTIVE': accountInactive,
    'NOT_A_WORKER': notAWorker,
    'AUTH_REQUIRED': sessionExpired,
    'OUTSIDE_RADIUS': outsideRadius,
    'MOCK_LOCATION': mockLocation,
    'PERMISSION_DENIED': locationPermissionDenied,
    'LOCATION_DISABLED': locationDisabled,
    'PROJECT_GEOFENCE_UNAVAILABLE': projectGeofenceUnavailable,
    'APP_UPDATE_REQUIRED': appUpdateRequired,
  };

  static AttendanceFailure of(Object error) {
    if (error is IOException ||
        error is TimeoutException ||
        error is http.ClientException ||
        error is AuthRetryableFetchException) {
      return noConnection;
    }
    final text = error.toString();
    for (final entry in _byCode.entries) {
      if (text.contains(entry.key)) return entry.value;
    }
    return unexpected;
  }
}
