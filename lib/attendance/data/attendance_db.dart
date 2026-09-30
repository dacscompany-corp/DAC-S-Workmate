import 'package:sqflite/sqflite.dart';

import '../domain/attendance_record.dart';
import '../domain/location_verification.dart';
import 'submission_request.dart';

/// The queue, the worker's record mirror and the project cache — all scoped by
/// worker, because site phones are shared. Same tables as DACS Attendance's
/// Room database (pending_submission, cached_record, cached_project).
class AttendanceDb {
  AttendanceDb._(this._db);

  final Database _db;

  static Future<AttendanceDb> open(DatabaseFactory factory, String path, {bool singleInstance = true}) async {
    final db = await factory.openDatabase(
      path,
      options: OpenDatabaseOptions(version: 1, onCreate: _create, singleInstance: singleInstance),
    );
    return AttendanceDb._(db);
  }

  static Future<void> _create(Database db, int version) async {
    await db.execute('''
      create table pending_submission (
        event_id text primary key,
        worker_id text not null,
        direction text not null,
        project_system text not null,
        project_id text not null,
        project_name text not null,
        captured_at integer not null,
        trusted_at integer,
        photo_local_path text not null,
        description text,
        latitude real,
        longitude real,
        accuracy_metres real,
        was_offline integer not null,
        is_mock integer not null default 0,
        permission_denied integer not null default 0,
        location_status text,
        attempts integer not null default 0,
        last_error text,
        failed_permanently integer not null default 0,
        created_at integer not null
      )''');
    await db.execute('''
      create table cached_record (
        worker_id text not null,
        work_date text not null,
        id text,
        status text not null,
        time_in_at integer,
        time_out_at integer,
        time_in_project_name text,
        time_out_project_name text,
        total_minutes integer,
        pending integer not null default 0,
        primary key (worker_id, work_date)
      )''');
    await db.execute('''
      create table cached_project (
        worker_id text not null,
        system text not null,
        id text not null,
        name text not null,
        geofence_lat real,
        geofence_lng real,
        geofence_radius_m real,
        geofence_enabled integer not null default 1,
        primary key (worker_id, system, id)
      )''');
  }

  Future<void> close() => _db.close();

  // ── queue ──────────────────────────────────────────────────────────────

  Future<void> insertPending(PendingSubmission p) =>
      _db.insert('pending_submission', p.toMap(), conflictAlgorithm: ConflictAlgorithm.replace);

  /// Scoped to ONE worker: an unscoped read is how another worker's queued day
  /// would be uploaded under this session.
  Future<List<PendingSubmission>> sendable(String workerId) async => (await _db.query('pending_submission',
          where: 'failed_permanently = 0 and worker_id = ?', whereArgs: [workerId], orderBy: 'created_at asc'))
      .map(PendingSubmission.fromMap)
      .toList();

  /// Any worker: the app-closed sweeper asks this before it touches auth.
  Future<bool> hasAnySendable() async =>
      (await _db.query('pending_submission', where: 'failed_permanently = 0', limit: 1)).isNotEmpty;

  Future<List<PendingSubmission>> failed(String workerId) async => (await _db.query('pending_submission',
          where: 'failed_permanently = 1 and worker_id = ?', whereArgs: [workerId], orderBy: 'created_at asc'))
      .map(PendingSubmission.fromMap)
      .toList();

  Future<PendingSubmission?> pendingById(String eventId) async {
    final rows = await _db.query('pending_submission', where: 'event_id = ?', whereArgs: [eventId], limit: 1);
    return rows.isEmpty ? null : PendingSubmission.fromMap(rows.first);
  }

  /// Failed rows are left out: "not sent YET" would promise they will be.
  Future<bool> hasPendingFor(String workerId) async =>
      (await _db.query('pending_submission',
              columns: ['event_id'], where: 'worker_id = ? and failed_permanently = 0', whereArgs: [workerId], limit: 1))
          .isNotEmpty;

  Future<void> recordAttempt(String eventId, String error) => _db.rawUpdate(
      'update pending_submission set attempts = attempts + 1, last_error = ? where event_id = ?', [error, eventId]);

  Future<void> markFailed(String eventId, String error) => _db.rawUpdate(
      'update pending_submission set failed_permanently = 1, last_error = ? where event_id = ?', [error, eventId]);

  Future<void> deletePending(String eventId) =>
      _db.delete('pending_submission', where: 'event_id = ?', whereArgs: [eventId]);

  // ── record mirror ───────────────────────────────────────────────────────

  Future<void> upsertRecord(String workerId, AttendanceRecord r, {required bool pending}) => _db.insert(
        'cached_record',
        {
          'worker_id': workerId,
          'work_date': r.workDate,
          'id': r.id,
          'status': r.status.name,
          'time_in_at': r.timeInAt?.millisecondsSinceEpoch,
          'time_out_at': r.timeOutAt?.millisecondsSinceEpoch,
          'time_in_project_name': r.timeInProjectName,
          'time_out_project_name': r.timeOutProjectName,
          'total_minutes': r.totalMinutes,
          'pending': pending ? 1 : 0,
        },
        conflictAlgorithm: ConflictAlgorithm.replace,
      );

  static DateTime? _ms(Object? v) => v == null ? null : DateTime.fromMillisecondsSinceEpoch(v as int, isUtc: true);

  static AttendanceRecord _record(Map<String, Object?> m) => AttendanceRecord(
        id: (m['id'] as String?) ?? (m['work_date']! as String),
        workDate: m['work_date']! as String,
        status: AttendanceStatus.parse(m['status'] as String?),
        timeInAt: _ms(m['time_in_at']),
        timeOutAt: _ms(m['time_out_at']),
        timeInProjectName: m['time_in_project_name'] as String?,
        timeOutProjectName: m['time_out_project_name'] as String?,
        totalMinutes: m['total_minutes'] as int?,
        pending: m['pending'] == 1,
      );

  Future<AttendanceRecord?> recordFor(String workerId, String workDate) async {
    final rows = await _db.query('cached_record',
        where: 'worker_id = ? and work_date = ?', whereArgs: [workerId, workDate], limit: 1);
    return rows.isEmpty ? null : _record(rows.first);
  }

  Future<void> clearRecord(String workerId, String workDate) =>
      _db.delete('cached_record', where: 'worker_id = ? and work_date = ?', whereArgs: [workerId, workDate]);

  /// work_date is ISO yyyy-MM-dd text, so lexical BETWEEN is chronological.
  Future<List<AttendanceRecord>> recordsBetween(String workerId, String from, String to) async =>
      (await _db.query('cached_record',
              where: 'worker_id = ? and work_date between ? and ?',
              whereArgs: [workerId, from, to],
              orderBy: 'work_date desc'))
          .map(_record)
          .toList();

  // ── project cache ───────────────────────────────────────────────────────

  Future<List<AttendanceProject>> projects(String workerId) async {
    final rows = await _db.query('cached_project', where: 'worker_id = ?', whereArgs: [workerId], orderBy: 'name asc');
    final out = <AttendanceProject>[];
    for (final m in rows) {
      final system = ProjectSystem.of(m['system'] as String?);
      if (system == null) continue; // a system this build does not know is dropped, not guessed
      final lat = (m['geofence_lat'] as num?)?.toDouble();
      final lng = (m['geofence_lng'] as num?)?.toDouble();
      final radius = (m['geofence_radius_m'] as num?)?.toDouble();
      out.add(AttendanceProject(
        system: system,
        id: m['id']! as String,
        name: m['name']! as String,
        // Rebuilt only when all three parts are present: a half fence is a circle nobody drew.
        geofence: (lat != null && lng != null && radius != null)
            ? Geofence(latitude: lat, longitude: lng, radiusMetres: radius, enabled: m['geofence_enabled'] == 1)
            : null,
      ));
    }
    return out;
  }

  /// Clear + insert in one transaction, so a project deactivated on the server
  /// disappears from the picker instead of lingering.
  Future<void> replaceProjects(String workerId, List<AttendanceProject> projects) => _db.transaction((txn) async {
        await txn.delete('cached_project', where: 'worker_id = ?', whereArgs: [workerId]);
        for (final p in projects) {
          await txn.insert(
            'cached_project',
            {
              'worker_id': workerId,
              'system': p.system.wire,
              'id': p.id,
              'name': p.name,
              'geofence_lat': p.geofence?.latitude,
              'geofence_lng': p.geofence?.longitude,
              'geofence_radius_m': p.geofence?.radiusMetres,
              'geofence_enabled': (p.geofence?.enabled ?? true) ? 1 : 0,
            },
            conflictAlgorithm: ConflictAlgorithm.replace,
          );
        }
      });
}

/// The database file on the phone, shared by the app and the background sync.
Future<AttendanceDb> openDeviceAttendanceDb({bool singleInstance = true}) async => AttendanceDb.open(
    databaseFactory, '${await getDatabasesPath()}/workmate_attendance.db',
    singleInstance: singleInstance);
