import '../attendance/data/attendance_api.dart';
import '../attendance/data/submission_request.dart';
import '../attendance/domain/attendance_record.dart';

/// The attendance engine, telling the widget whenever today may have changed.
/// A decorator rather than calls sprinkled through the repository (ported from
/// DACS Attendance's WidgetAwareAttendanceRepository): submit is the optimistic
/// write, so the widget flips the moment the worker submits, signal or not;
/// today() is where Home reconciles with the server, so an admin correction
/// reaches the widget too.
class WidgetAwareAttendance implements AttendanceApi {
  WidgetAwareAttendance(this._inner, {required Future<void> Function() onTodayChanged}) : _onTodayChanged = onTodayChanged;

  final AttendanceApi _inner;
  final Future<void> Function() _onTodayChanged;

  @override
  Future<AttendanceRecord> submit(SubmissionRequest r, {bool mirrorPhoto = false}) async {
    try {
      return await _inner.submit(r, mirrorPhoto: mirrorPhoto);
    } finally {
      await _tell();
    }
  }

  @override
  Future<AttendanceRecord?> today() async {
    try {
      return await _inner.today();
    } finally {
      await _tell();
    }
  }

  @override
  Future<List<AttendanceRecord>> history(String from, String to) => _inner.history(from, to);

  @override
  Future<List<AttendanceProject>> activeProjects() => _inner.activeProjects();

  @override
  Future<List<PendingSubmission>> refusedSubmissions() => _inner.refusedSubmissions();

  @override
  Future<void> dismissRefused(String eventId) => _inner.dismissRefused(eventId);

  Future<void> _tell() async {
    try {
      await _onTodayChanged();
    } catch (_) {
      // Never let the widget break attendance.
    }
  }
}
