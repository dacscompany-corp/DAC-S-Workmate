import 'dart:io';

import 'package:flutter/foundation.dart';

import '../data/attendance_api.dart';
import '../data/submission_request.dart';
import '../device/device_bridge.dart';
import '../domain/attendance_failure.dart';
import '../domain/attendance_record.dart';
import '../domain/description_chips.dart';
import '../domain/event_id.dart';
import '../domain/location_verification.dart';
import '../domain/work_date.dart';

/// The four steps of the design, plus the confirmation that ends them.
enum FlowStep { pickProject, takePhoto, checkPhoto, describe, confirmed }

/// The documented default (§36 / migration 0068). It only changes which label
/// a flagged record carries: low accuracy is recorded, never refused.
const minAccuracyMetres = 50.0;

/// A photo on disk and its shutter moment — by the phone's clock and by the
/// clock the worker cannot change (0078; null when it cannot vouch).
class CapturedPhoto {
  const CapturedPhoto({required this.path, required this.capturedAt, required this.trustedAt, required this.mirrored});
  final String path;
  final DateTime capturedAt;
  final DateTime? trustedAt;

  /// Front camera: shown and filed mirrored, as previewed.
  final bool mirrored;
}

/// ONE flow for both directions (Time Out is "the same five, in brown").
/// Ported from DACS Attendance's TimeFlowViewModel.
class TimeFlowController extends ChangeNotifier {
  TimeFlowController({
    required this.direction,
    required AttendanceApi attendance,
    required DeviceBridge device,
    required Future<DateTime?> Function() trustedNow,
    String Function()? newId,
  })  : _attendance = attendance,
        _device = device,
        _trustedNow = trustedNow,
        eventId = (newId ?? newEventId)();

  final TimeDirection direction;

  /// The idempotency key for THIS submission, minted once and reused for
  /// every retry: a fresh id per attempt would turn one retried Time In into two.
  final String eventId;

  final AttendanceApi _attendance;
  final DeviceBridge _device;
  final Future<DateTime?> Function() _trustedNow;

  FlowStep _step = FlowStep.pickProject;
  List<AttendanceProject> _projects = const [];
  bool _loadingProjects = true;
  String? _selectedKey;
  CapturedPhoto? _photo;
  String _description = '';
  bool _submitting = false;
  AttendanceFailure? _failure;
  AttendanceRecord? _saved;
  bool _disposed = false;

  FlowStep get step => _step;
  List<AttendanceProject> get projects => _projects;
  bool get loadingProjects => _loadingProjects;
  String? get selectedKey => _selectedKey;
  CapturedPhoto? get photo => _photo;
  String get description => _description;
  bool get submitting => _submitting;
  AttendanceFailure? get failure => _failure;
  AttendanceRecord? get saved => _saved;

  /// Matched on "system:id": since 0059 an id alone is ambiguous.
  AttendanceProject? get selectedProject => _projects.where((p) => p.key == _selectedKey).firstOrNull;

  /// "Step N of 4". Confirmation is not a step.
  int get stepNumber => switch (_step) {
        FlowStep.pickProject => 1,
        FlowStep.takePhoto => 2,
        FlowStep.checkPhoto => 3,
        FlowStep.describe || FlowStep.confirmed => 4,
      };

  Future<void> loadProjects() async {
    _loadingProjects = true;
    _failure = null;
    _notify();
    try {
      _projects = await _attendance.activeProjects();
    } catch (e) {
      // An empty picker and a failed fetch look identical, and only one is fixed by waiting.
      _failure = AttendanceFailure.of(e);
    }
    _loadingProjects = false;
    _notify();
  }

  void selectProject(String key) {
    _selectedKey = key;
    _failure = null;
    _notify();
  }

  void confirmProject() {
    if (selectedProject == null) return;
    _step = FlowStep.takePhoto;
    _notify();
  }

  /// The capture, frozen at the shutter: its time, and the trusted time now.
  Future<void> photoTaken(String path, DateTime capturedAt, {required bool mirrored}) async {
    DateTime? trusted;
    try {
      trusted = await _trustedNow();
    } catch (_) {
      // "Cannot vouch" is null, never a guess.
    }
    _photo = CapturedPhoto(path: path, capturedAt: capturedAt, trustedAt: trusted, mirrored: mirrored);
    _step = FlowStep.checkPhoto;
    _failure = null;
    _notify();
  }

  void retake() {
    _discardPhoto();
    _step = FlowStep.takePhoto;
    _notify();
  }

  void acceptPhoto() {
    if (_photo == null) return;
    _step = FlowStep.describe;
    _notify();
  }

  void setDescription(String value) {
    _description = value;
    _notify();
  }

  void toggleChip(String chip) {
    _description = toggleDescriptionChip(_description, chip);
    _notify();
  }

  /// One step back. False on the first step (and after confirming): the
  /// caller leaves the flow.
  bool back() {
    // Do not navigate while submit() is reading the photo from disk.
    if (_submitting) return true;
    switch (_step) {
      case FlowStep.pickProject:
      case FlowStep.confirmed:
        return false;
      case FlowStep.takePhoto:
        _step = FlowStep.pickProject;
      case FlowStep.checkPhoto:
        _discardPhoto();
        _step = FlowStep.takePhoto;
      case FlowStep.describe:
        _step = FlowStep.checkPhoto;
    }
    _failure = null;
    _notify();
    return true;
  }

  Future<void> submit() async {
    // Guards the commonest duplicate: a slow phone and a second tap.
    if (_submitting) return;
    final project = selectedProject;
    final photo = _photo;
    if (project == null || photo == null) return;
    _submitting = true;
    _failure = null;
    _notify();

    // The location is read NOW, a few seconds after the shutter, standing in
    // the same place — the shutter itself never waits on GPS.
    final fix = await _device.currentFix();
    // The same rule the server applies (0069), with the fence the phone cached,
    // so an OFFLINE worker is told at the gate instead of days later.
    final check = checkLocation(fix, project.geofence, minAccuracyMetres: minAccuracyMetres);
    // requireGeofence stays FALSE on the device: whether a fence is mandatory
    // is the server's ruling, against config the phone does not hold.
    if (locationRefuses(check.status, requireGeofence: false)) {
      _failure = failureForRefusal(check.status) ?? AttendanceFailure.unexpected;
      _submitting = false;
      _notify();
      return;
    }

    try {
      final note = _description.trim();
      _saved = await _attendance.submit(
        SubmissionRequest(
          direction: direction,
          projectSystem: project.system,
          projectId: project.id,
          capturedAt: photo.capturedAt,
          trustedAt: photo.trustedAt,
          photoPath: photo.path,
          description: note.isEmpty ? null : note,
          eventId: eventId,
          latitude: fix.latitude,
          longitude: fix.longitude,
          accuracyMetres: fix.accuracyMetres,
          isMock: fix.isMock,
          permissionDenied: fix.permissionDenied,
          locationStatus: check.status.wire,
        ),
        mirrorPhoto: photo.mirrored,
      );
      _step = FlowStep.confirmed;
    } catch (e) {
      // Stay on Describe with the photo intact: the photo is the evidence of when they arrived.
      _failure = AttendanceFailure.of(e);
    }
    _submitting = false;
    _notify();
  }

  /// The worker left the flow: a photo that was never submitted is deleted.
  void abandon() {
    if (_step != FlowStep.confirmed && !_submitting) _discardPhoto();
  }

  void _discardPhoto() {
    final p = _photo;
    _photo = null;
    if (p == null) return;
    try {
      File(p.path).deleteSync();
    } catch (_) {
      // Already gone.
    }
  }

  void _notify() {
    if (!_disposed) notifyListeners();
  }

  @override
  void dispose() {
    _disposed = true;
    super.dispose();
  }
}
