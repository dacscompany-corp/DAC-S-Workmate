import '../domain/attendance_record.dart';
import '../domain/submission_queue.dart';
import '../domain/work_date.dart';

/// Everything needed to record one Time In or Time Out. [eventId] is minted
/// once when the worker first taps SUBMIT and reused for every retry (the RPCs
/// are idempotent on it). [capturedAt] is the SHUTTER, never the upload time.
class SubmissionRequest {
  const SubmissionRequest({
    required this.direction,
    required this.projectSystem,
    required this.projectId,
    required this.capturedAt,
    required this.trustedAt,
    required this.photoPath,
    required this.description,
    required this.eventId,
    this.latitude,
    this.longitude,
    this.accuracyMetres,
    this.wasOffline = false,
    this.isMock = false,
    this.permissionDenied = false,
    this.locationStatus,
  });

  final TimeDirection direction;
  final ProjectSystem projectSystem;
  final String projectId;
  final DateTime capturedAt;

  /// The shutter by the clock the worker cannot change (0078), or null.
  final DateTime? trustedAt;
  final String photoPath;
  final String? description;
  final String eventId;
  final double? latitude;
  final double? longitude;
  final double? accuracyMetres;
  final bool wasOffline;

  /// The two things only the device can observe (both arrive as null coordinates).
  final bool isMock;
  final bool permissionDenied;

  /// The device's own verdict, kept LOCAL so a queued row can explain itself.
  final String? locationStatus;

  SubmissionRequest withPhoto(String path, {required bool wasOffline}) => SubmissionRequest(
        direction: direction,
        projectSystem: projectSystem,
        projectId: projectId,
        capturedAt: capturedAt,
        trustedAt: trustedAt,
        photoPath: path,
        description: description,
        eventId: eventId,
        latitude: latitude,
        longitude: longitude,
        accuracyMetres: accuracyMetres,
        wasOffline: wasOffline,
        isMock: isMock,
        permissionDenied: permissionDenied,
        locationStatus: locationStatus,
      );
}

/// One row of pending_submission: the worker's day until the upload succeeds.
class PendingSubmission {
  const PendingSubmission({
    required this.eventId,
    required this.workerId,
    required this.direction,
    required this.projectSystem,
    required this.projectId,
    required this.projectName,
    required this.capturedAtMs,
    required this.trustedAtMs,
    required this.photoLocalPath,
    required this.description,
    required this.latitude,
    required this.longitude,
    required this.accuracyMetres,
    required this.wasOffline,
    required this.isMock,
    required this.permissionDenied,
    required this.locationStatus,
    required this.attempts,
    required this.lastError,
    required this.failedPermanently,
    required this.createdAtMs,
  });

  factory PendingSubmission.fromRequest(SubmissionRequest r,
          {required String workerId, required String projectName, required DateTime createdAt}) =>
      PendingSubmission(
        eventId: r.eventId,
        workerId: workerId,
        direction: r.direction.wire,
        projectSystem: r.projectSystem.wire,
        projectId: r.projectId,
        projectName: projectName,
        capturedAtMs: r.capturedAt.millisecondsSinceEpoch,
        trustedAtMs: r.trustedAt?.millisecondsSinceEpoch,
        photoLocalPath: r.photoPath,
        description: r.description,
        latitude: r.latitude,
        longitude: r.longitude,
        accuracyMetres: r.accuracyMetres,
        wasOffline: r.wasOffline,
        isMock: r.isMock,
        permissionDenied: r.permissionDenied,
        locationStatus: r.locationStatus,
        attempts: 0,
        lastError: null,
        failedPermanently: false,
        createdAtMs: createdAt.millisecondsSinceEpoch,
      );

  factory PendingSubmission.fromMap(Map<String, Object?> m) => PendingSubmission(
        eventId: m['event_id']! as String,
        workerId: m['worker_id']! as String,
        direction: m['direction']! as String,
        projectSystem: m['project_system']! as String,
        projectId: m['project_id']! as String,
        projectName: m['project_name']! as String,
        capturedAtMs: m['captured_at']! as int,
        trustedAtMs: m['trusted_at'] as int?,
        photoLocalPath: m['photo_local_path']! as String,
        description: m['description'] as String?,
        latitude: (m['latitude'] as num?)?.toDouble(),
        longitude: (m['longitude'] as num?)?.toDouble(),
        accuracyMetres: (m['accuracy_metres'] as num?)?.toDouble(),
        wasOffline: m['was_offline'] == 1,
        isMock: m['is_mock'] == 1,
        permissionDenied: m['permission_denied'] == 1,
        locationStatus: m['location_status'] as String?,
        attempts: m['attempts']! as int,
        lastError: m['last_error'] as String?,
        failedPermanently: m['failed_permanently'] == 1,
        createdAtMs: m['created_at']! as int,
      );

  final String eventId;
  final String workerId;
  final String direction;
  final String projectSystem;
  final String projectId;
  final String projectName;
  final int capturedAtMs;
  final int? trustedAtMs;
  final String photoLocalPath;
  final String? description;
  final double? latitude;
  final double? longitude;
  final double? accuracyMetres;
  final bool wasOffline;
  final bool isMock;
  final bool permissionDenied;
  final String? locationStatus;
  final int attempts;
  final String? lastError;
  final bool failedPermanently;
  final int createdAtMs;

  DateTime get capturedAt => DateTime.fromMillisecondsSinceEpoch(capturedAtMs, isUtc: true);

  Map<String, Object?> toMap() => {
        'event_id': eventId,
        'worker_id': workerId,
        'direction': direction,
        'project_system': projectSystem,
        'project_id': projectId,
        'project_name': projectName,
        'captured_at': capturedAtMs,
        'trusted_at': trustedAtMs,
        'photo_local_path': photoLocalPath,
        'description': description,
        'latitude': latitude,
        'longitude': longitude,
        'accuracy_metres': accuracyMetres,
        'was_offline': wasOffline ? 1 : 0,
        'is_mock': isMock ? 1 : 0,
        'permission_denied': permissionDenied ? 1 : 0,
        'location_status': locationStatus,
        'attempts': attempts,
        'last_error': lastError,
        'failed_permanently': failedPermanently ? 1 : 0,
        'created_at': createdAtMs,
      };

  /// Null when the row names a project system this build does not know: there
  /// is nothing to send it against.
  SubmissionRequest? toRequest() {
    final system = ProjectSystem.of(projectSystem);
    if (system == null) return null;
    return SubmissionRequest(
      direction: TimeDirection.parse(direction),
      projectSystem: system,
      projectId: projectId,
      capturedAt: capturedAt,
      trustedAt: trustedAtMs == null ? null : DateTime.fromMillisecondsSinceEpoch(trustedAtMs!, isUtc: true),
      photoPath: photoLocalPath,
      description: description,
      eventId: eventId,
      latitude: latitude,
      longitude: longitude,
      accuracyMetres: accuracyMetres,
      wasOffline: wasOffline,
      isMock: isMock,
      permissionDenied: permissionDenied,
      locationStatus: locationStatus,
    );
  }

  QueuedSubmission toQueued() => QueuedSubmission(
        eventId: eventId,
        direction: TimeDirection.parse(direction),
        createdAt: DateTime.fromMillisecondsSinceEpoch(createdAtMs, isUtc: true),
        workerId: workerId,
      );

  /// Test/support helper: the same row with another project system value.
  PendingSubmission copyWithSystem(String system) => PendingSubmission.fromMap({...toMap(), 'project_system': system});
}
