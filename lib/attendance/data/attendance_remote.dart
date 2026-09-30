import 'dart:io';

import 'package:supabase_flutter/supabase_flutter.dart';

import '../domain/attendance_record.dart';
import '../domain/location_verification.dart';
import '../domain/work_date.dart';
import 'submission_request.dart';

/// The private bucket every attendance photo lives in (0050).
const photoBucket = 'attendance';

const _readTimeout = Duration(seconds: 15);
const _rpcTimeout = Duration(seconds: 20);
const _uploadTimeout = Duration(seconds: 60);

/// The RPC arguments — exactly the live signature (verified 2026-09-30).
/// p_trusted_at is OMITTED when unknown (the server default says the same).
/// The device's location verdict is never sent: the server computes its own.
Map<String, dynamic> rpcParams(SubmissionRequest r, String photoPath) => {
      'p_project_system': r.projectSystem.wire,
      'p_project_id': r.projectId,
      'p_captured_at': r.capturedAt.toUtc().toIso8601String(),
      'p_photo_path': photoPath,
      'p_event_id': r.eventId,
      'p_description': r.description,
      'p_lat': r.latitude,
      'p_lng': r.longitude,
      'p_accuracy_m': r.accuracyMetres,
      'p_was_offline': r.wasOffline,
      'p_is_mock': r.isMock,
      'p_permission_denied': r.permissionDenied,
      if (r.trustedAt != null) 'p_trusted_at': r.trustedAt!.toUtc().toIso8601String(),
    };

/// One row of attendance_projects_for_worker(); null for a system this build
/// does not know (offering it would fail four screens later).
AttendanceProject? projectFromRow(Map<String, dynamic> row) {
  final system = ProjectSystem.of(row['project_system'] as String?);
  if (system == null) return null;
  return AttendanceProject(system: system, id: row['project_id'].toString(), name: row['project_name'] as String);
}

/// The newest fence per "system:id" from the append-only fence table.
Map<String, Geofence> newestFences(List<Map<String, dynamic>> rows) {
  final keyed = rows.where((r) => (r['folder_id'] ?? r['pm_project_id']) != null).toList()
    ..sort((a, b) => ((a['effective_from'] as String?) ?? '').compareTo((b['effective_from'] as String?) ?? ''));
  return {
    for (final r in keyed)
      '${r['project_system']}:${r['folder_id'] ?? r['pm_project_id']}': Geofence(
        latitude: (r['latitude'] as num).toDouble(),
        longitude: (r['longitude'] as num).toDouble(),
        radiusMetres: (r['radius_m'] as num).toDouble(),
        enabled: r['enabled'] != false,
      ),
  };
}

abstract class AttendanceRemote {
  /// Uploads the photo, THEN calls the matching RPC (a record must never point
  /// at a photo that never uploaded).
  Future<AttendanceRecord> submit(SubmissionRequest r, {required String workerId});

  /// Today's record for the Manila [workDate], or null.
  Future<AttendanceRecord?> today(String workDate);

  Future<List<AttendanceRecord>> history(String from, String to);

  Future<List<AttendanceProject>> activeProjects();
}

class SupabaseAttendanceRemote implements AttendanceRemote {
  SupabaseAttendanceRemote(this._client);

  final SupabaseClient _client;

  @override
  Future<AttendanceRecord> submit(SubmissionRequest r, {required String workerId}) async {
    // The RPC files under the CURRENT session: a different signed-in worker must never receive this row.
    final sessionId = _client.auth.currentUser?.id;
    if (sessionId == null || sessionId != workerId) throw StateError('AUTH_REQUIRED');
    final path = photoPath(workerId: sessionId, workDate: WorkDate.of(r.capturedAt), direction: r.direction, eventId: r.eventId);

    // upsert: a retry re-uploads over the same path instead of failing on "already exists".
    await _client.storage
        .from(photoBucket)
        .upload(path, File(r.photoPath), fileOptions: const FileOptions(upsert: true, contentType: 'image/jpeg'))
        .timeout(_uploadTimeout);

    final fn = r.direction == TimeDirection.timeIn ? 'attendance_time_in' : 'attendance_time_out';
    final result = await _client.rpc(fn, params: rpcParams(r, path)).timeout(_rpcTimeout);
    final row = result is List ? result.first : result;
    return AttendanceRecord.fromRow(Map<String, dynamic>.from(row as Map));
  }

  @override
  Future<AttendanceRecord?> today(String workDate) async {
    final row = await _client
        .from('attendance_records')
        .select(AttendanceRecord.columns)
        .eq('work_date', workDate)
        .limit(1)
        .maybeSingle()
        .timeout(_readTimeout);
    return row == null ? null : AttendanceRecord.fromRow(row);
  }

  @override
  Future<List<AttendanceRecord>> history(String from, String to) async {
    final rows = await _client
        .from('attendance_records')
        .select(AttendanceRecord.columns)
        .gte('work_date', from)
        .lte('work_date', to)
        .order('work_date', ascending: false)
        .timeout(_readTimeout);
    return rows.map(AttendanceRecord.fromRow).toList();
  }

  /// An RPC, not a table read: workers have no select on folders (contract
  /// values are owner-confidential); the function exposes exactly 3 columns.
  @override
  Future<List<AttendanceProject>> activeProjects() async {
    final rows = await _client.rpc('attendance_projects_for_worker').timeout(_readTimeout) as List<dynamic>;
    final projects = rows
        .map((r) => projectFromRow(Map<String, dynamic>.from(r as Map)))
        .whereType<AttendanceProject>()
        .toList();
    return _attachGeofences(projects);
  }

  /// Fences fetched separately and merged; a failure here costs a pre-check,
  /// not the flow (the server still verifies).
  Future<List<AttendanceProject>> _attachGeofences(List<AttendanceProject> projects) async {
    try {
      final rows = await _client
          .from('attendance_project_geofence')
          .select('project_system,folder_id,pm_project_id,effective_from,latitude,longitude,radius_m,enabled')
          .timeout(_readTimeout);
      final fences = newestFences(rows);
      return [for (final p in projects) fences.containsKey(p.key) ? p.withGeofence(fences[p.key]) : p];
    } catch (_) {
      return projects;
    }
  }
}
