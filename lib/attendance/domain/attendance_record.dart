import 'location_verification.dart';
import 'work_date.dart';

/// WHICH project list a project came from (0059): PC -> folders,
/// PM -> construction_projects. Ids are only unique within a system.
enum ProjectSystem {
  pc('pc'),
  pm('pm');

  const ProjectSystem(this.wire);
  final String wire;

  /// Null for anything the server has not taught us about yet.
  static ProjectSystem? of(String? wire) {
    final w = wire?.toLowerCase();
    for (final s in values) {
      if (s.wire == w) return s;
    }
    return null;
  }
}

class AttendanceProject {
  const AttendanceProject({required this.system, required this.id, required this.name, this.geofence});
  final ProjectSystem system;
  final String id;
  final String name;

  /// Null = the phone has never seen a fence; the server still checks.
  final Geofence? geofence;

  /// "pc:`<uuid>`" for list keys. Never sent to the server.
  String get key => '${system.wire}:$id';

  AttendanceProject withGeofence(Geofence? g) => AttendanceProject(system: system, id: id, name: name, geofence: g);
}

/// The §14 status machine. `abandoned` is set by an admin sweep; the app must
/// render it rather than crash on an unknown value.
enum AttendanceStatus {
  working,
  complete,
  abandoned,
  unknown;

  static AttendanceStatus parse(String? raw) => switch (raw?.toLowerCase()) {
        'working' => working,
        'complete' => complete,
        'abandoned' => abandoned,
        _ => unknown,
      };
}

DateTime? _instant(Object? raw) => raw == null ? null : DateTime.tryParse(raw.toString())?.toUtc();

class AttendanceRecord {
  const AttendanceRecord({
    required this.id,
    required this.workDate,
    required this.status,
    this.timeInAt,
    this.timeOutAt,
    this.timeInProjectName,
    this.timeOutProjectName,
    this.totalMinutes,
    this.timeInPhotoPath,
    this.timeOutPhotoPath,
    this.pending = false,
  });

  /// Only the columns the app renders; location columns are admin-only.
  static const columns = 'id,work_date,status,timein_at,timeout_at,'
      'timein_project_name,timeout_project_name,total_minutes,'
      'timein_photo_path,timeout_photo_path';

  factory AttendanceRecord.fromRow(Map<String, dynamic> row) => AttendanceRecord(
        id: row['id'] as String,
        workDate: row['work_date'] as String,
        status: AttendanceStatus.parse(row['status'] as String?),
        timeInAt: _instant(row['timein_at']),
        timeOutAt: _instant(row['timeout_at']),
        timeInProjectName: row['timein_project_name'] as String?,
        timeOutProjectName: row['timeout_project_name'] as String?,
        totalMinutes: (row['total_minutes'] as num?)?.toInt(),
        timeInPhotoPath: row['timein_photo_path'] as String?,
        timeOutPhotoPath: row['timeout_photo_path'] as String?,
      );

  final String id;
  final String workDate;
  final AttendanceStatus status;
  final DateTime? timeInAt;
  final DateTime? timeOutAt;
  final String? timeInProjectName;
  final String? timeOutProjectName;
  final int? totalMinutes;
  final String? timeInPhotoPath;
  final String? timeOutPhotoPath;

  /// True while this day is still only on the phone ("will sync").
  final bool pending;

  /// What the worker may do next. Complete or abandoned: the day is closed
  /// (one record per worker per day), so Time In is never offered again.
  TimeDirection? get nextAction => status == AttendanceStatus.working ? TimeDirection.timeOut : null;

  AttendanceRecord copyWith({bool? pending}) => AttendanceRecord(
        id: id,
        workDate: workDate,
        status: status,
        timeInAt: timeInAt,
        timeOutAt: timeOutAt,
        timeInProjectName: timeInProjectName,
        timeOutProjectName: timeOutProjectName,
        totalMinutes: totalMinutes,
        timeInPhotoPath: timeInPhotoPath,
        timeOutPhotoPath: timeOutPhotoPath,
        pending: pending ?? this.pending,
      );
}
