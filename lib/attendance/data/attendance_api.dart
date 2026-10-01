import '../domain/attendance_record.dart';
import 'submission_request.dart';

/// What the attendance screens need from the engine. An interface so every
/// controller and screen tests with a fake instead of a database and a server.
abstract interface class AttendanceApi {
  /// The worker's projects: fresh when online, the cached list offline.
  Future<List<AttendanceProject>> activeProjects();

  /// Saves a Time In / Time Out on the phone and queues its upload.
  /// [mirrorPhoto] files a front-camera capture as previewed (mirrored).
  Future<AttendanceRecord> submit(SubmissionRequest r, {bool mirrorPhoto = false});

  /// Today's record, null when there is none; throws when it cannot be known.
  Future<AttendanceRecord?> today();

  /// Records between two ISO dates, newest first.
  Future<List<AttendanceRecord>> history(String from, String to);

  /// This worker's submissions the server refused for good, oldest first.
  Future<List<PendingSubmission>> refusedSubmissions();

  /// Forgets one refused submission (the worker has read why) and deletes its photo.
  Future<void> dismissRefused(String eventId);
}
