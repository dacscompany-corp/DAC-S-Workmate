import 'dart:math';

import 'attendance_failure.dart';

/// Where the worker is, judged against where the project is. A PRE-CHECK: the
/// server verifies again (0069) and its answer is the one stored. Every rule
/// here matches 0069's attendance_check_location exactly. Refusals are only for
/// what is known bad; uncertainty is recorded and flagged, never refused.
enum LocationStatus {
  verified('verified'),
  outsideRadius('outside_radius'),
  lowAccuracy('low_accuracy'),
  locationUnavailable('location_unavailable'),
  mockLocation('mock_location'),
  permissionDenied('permission_denied'),

  /// Location switched OFF on the phone — a switch somebody flipped, not
  /// weather. Refused at the shutter, so never sent to the server.
  locationDisabled('location_disabled'),
  projectGeofenceUnavailable('project_geofence_unavailable');

  const LocationStatus(this.wire);
  final String wire;
}

/// A project's CURRENT fence as the device last cached it (the server keeps
/// them effective-dated and re-checks against the one in force at capture).
class Geofence {
  const Geofence({required this.latitude, required this.longitude, required this.radiusMetres, this.enabled = true});
  final double latitude;
  final double longitude;
  final double radiusMetres;
  final bool enabled;
}

/// What the device managed to observe at the shutter.
class DeviceFix {
  const DeviceFix({
    this.latitude,
    this.longitude,
    this.accuracyMetres,
    this.isMock = false,
    this.permissionDenied = false,
    this.locationDisabled = false,
  });
  final double? latitude;
  final double? longitude;
  final double? accuracyMetres;
  final bool isMock;
  final bool permissionDenied;
  final bool locationDisabled;
}

class LocationCheck {
  const LocationCheck({required this.status, this.distanceMetres, this.geofence});
  final LocationStatus status;
  final double? distanceMetres;
  final Geofence? geofence;
}

/// Mean earth radius, matching attendance_distance_m (0068).
const _earthRadiusM = 6371000.0;

double _rad(double degrees) => degrees * pi / 180;

/// Haversine in metres — the same formula and radius as the SQL, on purpose.
double distanceMetres(double lat1, double lng1, double lat2, double lng2) {
  final dLat = _rad(lat2 - lat1);
  final dLng = _rad(lng2 - lng1);
  final a = pow(sin(dLat / 2), 2) + cos(_rad(lat1)) * cos(_rad(lat2)) * pow(sin(dLng / 2), 2);
  return 2 * _earthRadiusM * asin(sqrt(a));
}

/// The check, in the same order the server applies it. Distance is computed
/// whenever there is a fix and a fence, even when the status is settled
/// otherwise — it is evidence for the admin.
LocationCheck checkLocation(DeviceFix fix, Geofence? fence, {required double minAccuracyMetres}) {
  final lat = fix.latitude;
  final lng = fix.longitude;
  final distance = (fence != null && lat != null && lng != null)
      ? distanceMetres(fence.latitude, fence.longitude, lat, lng)
      : null;

  final LocationStatus status;
  if (fix.permissionDenied) {
    status = LocationStatus.permissionDenied;
  } else if (fix.locationDisabled) {
    // BEFORE the null-coordinate branch: a phone with location off also has
    // no coordinates, and must not read as locationUnavailable.
    status = LocationStatus.locationDisabled;
  } else if (fix.isMock) {
    status = LocationStatus.mockLocation;
  } else if (lat == null || lng == null) {
    status = LocationStatus.locationUnavailable;
  } else if (fix.accuracyMetres == null || fix.accuracyMetres! > minAccuracyMetres) {
    status = LocationStatus.lowAccuracy;
  } else if (fence == null || !fence.enabled) {
    status = LocationStatus.projectGeofenceUnavailable;
  } else if (distance != null && distance > fence.radiusMetres) {
    status = LocationStatus.outsideRadius;
  } else {
    status = LocationStatus.verified;
  }
  return LocationCheck(status: status, distanceMetres: distance, geofence: fence);
}

/// Whether the app refuses to record this at all — the STRICT rule, with no
/// offline softening (the server softens outside_radius only for rows the
/// device already accepted). The device always passes requireGeofence: false.
bool locationRefuses(LocationStatus status, {required bool requireGeofence}) => switch (status) {
      LocationStatus.mockLocation ||
      LocationStatus.permissionDenied ||
      LocationStatus.locationDisabled ||
      LocationStatus.outsideRadius =>
        true,
      LocationStatus.projectGeofenceUnavailable => requireGeofence,
      LocationStatus.verified || LocationStatus.lowAccuracy || LocationStatus.locationUnavailable => false,
    };

/// The device's refusal as something the screen can render; null for statuses
/// that are recorded rather than refused.
AttendanceFailure? failureForRefusal(LocationStatus status) => switch (status) {
      LocationStatus.mockLocation => AttendanceFailure.mockLocation,
      LocationStatus.permissionDenied => AttendanceFailure.locationPermissionDenied,
      LocationStatus.locationDisabled => AttendanceFailure.locationDisabled,
      LocationStatus.outsideRadius => AttendanceFailure.outsideRadius,
      LocationStatus.projectGeofenceUnavailable => AttendanceFailure.projectGeofenceUnavailable,
      LocationStatus.verified || LocationStatus.lowAccuracy || LocationStatus.locationUnavailable => null,
    };
