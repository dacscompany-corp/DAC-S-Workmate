import 'package:flutter_test/flutter_test.dart';
import 'package:workmate/attendance/domain/attendance_failure.dart';
import 'package:workmate/attendance/domain/location_verification.dart';

void main() {
  const fence = Geofence(latitude: 14.5995, longitude: 120.9842, radiusMetres: 150);
  DeviceFix fixAt(double lat, double lng, {double accuracy = 12}) =>
      DeviceFix(latitude: lat, longitude: lng, accuracyMetres: accuracy);

  test('one degree of latitude is about 111 kilometres', () {
    final m = distanceMetres(14.0, 121.0, 15.0, 121.0);
    expect(m, inInclusiveRange(110000, 112000));
  });

  test('location switched off is refused, not merely treated as no fix', () {
    final check = checkLocation(const DeviceFix(locationDisabled: true), fence, minAccuracyMetres: 50);
    expect(check.status, LocationStatus.locationDisabled);
    expect(locationRefuses(check.status, requireGeofence: false), isTrue);
    expect(check.status.wire, 'location_disabled');
  });

  test('a phone that is ON but cannot get a fix is still recorded', () {
    final check = checkLocation(const DeviceFix(), fence, minAccuracyMetres: 50);
    expect(check.status, LocationStatus.locationUnavailable);
    expect(check.distanceMetres, isNull);
    expect(locationRefuses(check.status, requireGeofence: true), isFalse);
  });

  test('a denied permission and a switched-off phone stay separate', () {
    expect(checkLocation(const DeviceFix(permissionDenied: true), fence, minAccuracyMetres: 50).status,
        LocationStatus.permissionDenied);
    expect(checkLocation(const DeviceFix(locationDisabled: true), fence, minAccuracyMetres: 50).status,
        LocationStatus.locationDisabled);
  });

  test('standing on the site verifies', () {
    final check = checkLocation(fixAt(14.5995, 120.9842), fence, minAccuracyMetres: 50);
    expect(check.status, LocationStatus.verified);
    expect(check.distanceMetres!, lessThan(1));
    expect(locationRefuses(check.status, requireGeofence: true), isFalse);
  });

  test('just inside the fence still verifies', () {
    final check = checkLocation(fixAt(14.6004, 120.9842), fence, minAccuracyMetres: 50);
    expect(check.status, LocationStatus.verified);
    expect(check.distanceMetres!, inInclusiveRange(90, 110));
  });

  test('a worker somewhere else is refused', () {
    final check = checkLocation(fixAt(14.6095, 120.9842), fence, minAccuracyMetres: 50);
    expect(check.status, LocationStatus.outsideRadius);
    expect(check.distanceMetres!, greaterThan(1000));
    expect(locationRefuses(check.status, requireGeofence: false), isTrue);
  });

  test('a vague fix is recorded, never refused', () {
    final check = checkLocation(fixAt(14.5995, 120.9842, accuracy: 300), fence, minAccuracyMetres: 50);
    expect(check.status, LocationStatus.lowAccuracy);
    expect(locationRefuses(check.status, requireGeofence: true), isFalse);
  });

  test('a mock location is refused however good it looks', () {
    const fix = DeviceFix(latitude: 14.5995, longitude: 120.9842, accuracyMetres: 12, isMock: true);
    final check = checkLocation(fix, fence, minAccuracyMetres: 50);
    expect(check.status, LocationStatus.mockLocation);
    expect(locationRefuses(check.status, requireGeofence: false), isTrue);
  });

  test('an unconfigured project is refused only once geofences are required', () {
    final check = checkLocation(fixAt(14.5995, 120.9842), null, minAccuracyMetres: 50);
    expect(check.status, LocationStatus.projectGeofenceUnavailable);
    expect(check.distanceMetres, isNull);
    expect(locationRefuses(check.status, requireGeofence: false), isFalse);
    expect(locationRefuses(check.status, requireGeofence: true), isTrue);
  });

  test('a disabled fence behaves as no fence', () {
    const off = Geofence(latitude: 14.5995, longitude: 120.9842, radiusMetres: 150, enabled: false);
    expect(checkLocation(fixAt(14.5995, 120.9842), off, minAccuracyMetres: 50).status,
        LocationStatus.projectGeofenceUnavailable);
  });

  test("permission and mock beat everything, in the server's order", () {
    const fix = DeviceFix(
        latitude: 14.7, longitude: 120.9842, accuracyMetres: 5, isMock: true, permissionDenied: true);
    expect(checkLocation(fix, fence, minAccuracyMetres: 50).status, LocationStatus.permissionDenied);
  });

  test('distance is kept even when the status was settled by something else', () {
    final check = checkLocation(fixAt(14.6095, 120.9842, accuracy: 400), fence, minAccuracyMetres: 50);
    expect(check.status, LocationStatus.lowAccuracy);
    expect(check.distanceMetres!, greaterThan(1000));
  });

  test("the fence used is carried back for the record's snapshot", () {
    expect(checkLocation(fixAt(14.5995, 120.9842), fence, minAccuracyMetres: 50).geofence, same(fence));
  });

  test('wire values match the codes the server stores', () {
    expect(LocationStatus.values.map((s) => s.wire), [
      'verified', 'outside_radius', 'low_accuracy', 'location_unavailable',
      'mock_location', 'permission_denied', 'location_disabled', 'project_geofence_unavailable',
    ]);
  });

  test('each refusal the device makes has a failure the screen can render', () {
    expect(failureForRefusal(LocationStatus.mockLocation), AttendanceFailure.mockLocation);
    expect(failureForRefusal(LocationStatus.permissionDenied), AttendanceFailure.locationPermissionDenied);
    expect(failureForRefusal(LocationStatus.locationDisabled), AttendanceFailure.locationDisabled);
    expect(failureForRefusal(LocationStatus.outsideRadius), AttendanceFailure.outsideRadius);
    expect(failureForRefusal(LocationStatus.verified), isNull);
  });
}
