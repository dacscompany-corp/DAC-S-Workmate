import 'package:flutter_test/flutter_test.dart';
import 'package:workmate/attendance/data/attendance_remote.dart';
import 'package:workmate/attendance/data/submission_request.dart';
import 'package:workmate/attendance/domain/attendance_record.dart';
import 'package:workmate/attendance/domain/work_date.dart';

SubmissionRequest req({DateTime? trusted, String? description = 'Block A'}) => SubmissionRequest(
      direction: TimeDirection.timeIn,
      projectSystem: ProjectSystem.pc,
      projectId: 'a1b2c3d4-0000-4000-8000-000000000001',
      capturedAt: DateTime.parse('2026-08-19T07:45:00+08:00'),
      trustedAt: trusted,
      photoPath: '/files/e.jpg',
      description: description,
      eventId: 'e0000000-0000-4000-8000-000000000001',
      latitude: 14.5,
      longitude: 121.0,
      accuracyMetres: 9.5,
      wasOffline: true,
      isMock: false,
      permissionDenied: false,
      locationStatus: 'verified',
    );

void main() {
  test('the RPC gets exactly the live signature, the shutter time in UTC', () {
    final p = rpcParams(req(trusted: DateTime.parse('2026-08-18T23:45:02Z')), 'w/2026-08-19/in-e.jpg');
    expect(p.keys.toSet(), {
      'p_project_system', 'p_project_id', 'p_captured_at', 'p_photo_path', 'p_event_id', 'p_description',
      'p_lat', 'p_lng', 'p_accuracy_m', 'p_was_offline', 'p_is_mock', 'p_permission_denied', 'p_trusted_at',
    });
    expect(p['p_project_system'], 'pc');
    expect(p['p_captured_at'], '2026-08-18T23:45:00.000Z');
    expect(p['p_trusted_at'], '2026-08-18T23:45:02.000Z');
    expect(p['p_was_offline'], isTrue);
  });

  test('no trusted time is OMITTED, not sent as null; no description IS null', () {
    final p = rpcParams(req(description: null), 'x');
    expect(p.containsKey('p_trusted_at'), isFalse);
    expect(p.containsKey('p_description'), isTrue);
    expect(p['p_description'], isNull);
  });

  test('the location verdict is never uploaded (the server computes its own)', () {
    expect(rpcParams(req(), 'x').values, isNot(contains('verified')));
  });

  test('project rows: a system this build does not know is dropped', () {
    expect(projectFromRow({'project_system': 'pc', 'project_id': 'id1', 'project_name': 'Alpha'})!.key, 'pc:id1');
    expect(projectFromRow({'project_system': 'zz', 'project_id': 'id1', 'project_name': 'X'}), isNull);
  });

  test('only the newest fence per project is kept (append-only history)', () {
    final fences = newestFences([
      {'project_system': 'pc', 'folder_id': 'a', 'effective_from': '2026-08-01T00:00:00Z', 'latitude': 1, 'longitude': 1, 'radius_m': 100, 'enabled': true},
      {'project_system': 'pc', 'folder_id': 'a', 'effective_from': '2026-09-01T00:00:00Z', 'latitude': 2, 'longitude': 2, 'radius_m': 200, 'enabled': true},
      {'project_system': 'pm', 'pm_project_id': 'b', 'effective_from': null, 'latitude': 3, 'longitude': 3, 'radius_m': 300, 'enabled': false},
      {'project_system': 'pc', 'effective_from': '2026-09-01T00:00:00Z', 'latitude': 9, 'longitude': 9, 'radius_m': 9, 'enabled': true},
    ]);
    expect(fences.keys.toSet(), {'pc:a', 'pm:b'});
    expect(fences['pc:a']!.radiusMetres, 200);
    expect(fences['pm:b']!.enabled, isFalse);
  });
}
