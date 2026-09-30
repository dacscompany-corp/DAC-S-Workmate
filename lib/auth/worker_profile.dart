/// Who may use WorkMate. The same rule `attendance-signin` and the
/// attendance RPCs enforce; applied here so a deactivated worker is told at
/// the door. The database stays the authority.
enum Eligibility { allowed, accountInactive, notAWorker }

const _workerRoles = {'worker', 'teamLeader'};

Eligibility eligibilityOf(String? role, String? status) {
  if (!_workerRoles.contains(role)) return Eligibility.notAWorker;
  // SQL says coalesce(status, 'active'): older rows carry no status.
  if ((status ?? 'active') != 'active') return Eligibility.accountInactive;
  return Eligibility.allowed;
}

/// The worker's `profiles` row, as the app needs it.
class WorkerProfile {
  const WorkerProfile({
    required this.id,
    this.email,
    this.displayName,
    this.position,
    this.workerNo,
    this.role,
    this.status,
  });

  static const columns = 'id,email,display_name,position,worker_no,role,status';

  factory WorkerProfile.fromRow(Map<String, dynamic> row) => WorkerProfile(
        id: row['id'] as String,
        email: row['email'] as String?,
        displayName: row['display_name'] as String?,
        position: row['position'] as String?,
        workerNo: (row['worker_no'] as num?)?.toInt(),
        role: row['role'] as String?,
        status: row['status'] as String?,
      );

  final String id;
  final String? email;
  final String? displayName;
  final String? position;
  final int? workerNo;
  final String? role;
  final String? status;

  Map<String, dynamic> toRow() => {
        'id': id,
        'email': email,
        'display_name': displayName,
        'position': position,
        'worker_no': workerNo,
        'role': role,
        'status': status,
      };

  /// "W-0042", the format the Profile screen shows.
  String get workerIdLabel => workerNo == null ? '--' : 'W-${workerNo.toString().padLeft(4, '0')}';

  /// First name only; falls back to the email's local part, then "Worker".
  String get firstName {
    final d = displayName?.trim();
    if (d != null && d.isNotEmpty) return d.split(' ').first;
    final e = email;
    if (e != null) return e.split('@').first;
    return 'Worker';
  }

  /// "JD" for Juan dela Cruz: first letters of the first two words.
  String get initials {
    final parts = (displayName ?? firstName).trim().split(' ').where((p) => p.isNotEmpty).toList();
    if (parts.isEmpty) return '?';
    if (parts.length == 1) return parts[0].substring(0, 1).toUpperCase();
    return (parts[0].substring(0, 1) + parts[1].substring(0, 1)).toUpperCase();
  }

  /// "Mason · W-0042".
  String get positionAndId => [
        if (position != null && position!.trim().isNotEmpty) position!,
        workerIdLabel,
      ].join(' · ');

  Eligibility eligibility() => eligibilityOf(role, status);
}
