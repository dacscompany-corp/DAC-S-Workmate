import 'dart:async';

import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:workmate/attendance/data/attendance_api.dart';
import 'package:workmate/attendance/data/reward_remote.dart';
import 'package:workmate/attendance/data/submission_request.dart';
import 'package:workmate/attendance/device/device_bridge.dart';
import 'package:workmate/attendance/domain/attendance_record.dart';
import 'package:workmate/attendance/domain/location_verification.dart';
import 'package:workmate/attendance/domain/weekly_reward.dart';
import 'package:workmate/attendance/domain/work_date.dart';
import 'package:workmate/attendance/sync/upload_scheduler.dart';

const abc = AttendanceProject(system: ProjectSystem.pc, id: 'p1', name: 'ABC Building Project');

/// An AttendanceApi whose every answer the test sets.
class FakeAttendance implements AttendanceApi {
  List<AttendanceProject> projects = [abc];
  Object? projectsError;
  int projectLoads = 0;

  final submitted = <SubmissionRequest>[];
  final mirrored = <bool>[];
  Object? submitError;
  Completer<void>? submitGate;
  int? savedMinutes;

  AttendanceRecord? todayRecord;
  Object? todayError;

  List<AttendanceRecord> historyRecords = [];
  Object? historyError;
  Completer<void>? historyGate;
  final historyCalls = <(String, String)>[];

  List<PendingSubmission> refused = [];
  final dismissed = <String>[];

  @override
  Future<List<AttendanceProject>> activeProjects() async {
    projectLoads++;
    if (projectsError != null) throw projectsError!;
    return projects;
  }

  @override
  Future<AttendanceRecord> submit(SubmissionRequest r, {bool mirrorPhoto = false}) async {
    submitted.add(r);
    mirrored.add(mirrorPhoto);
    final gate = submitGate;
    if (gate != null) await gate.future;
    if (submitError != null) throw submitError!;
    final workDate = WorkDate.of(r.capturedAt).iso;
    return r.direction == TimeDirection.timeIn
        ? AttendanceRecord(
            id: workDate,
            workDate: workDate,
            status: AttendanceStatus.working,
            timeInAt: r.capturedAt.toUtc(),
            timeInProjectName: abc.name,
            pending: true,
          )
        : AttendanceRecord(
            id: workDate,
            workDate: workDate,
            status: AttendanceStatus.complete,
            timeOutAt: r.capturedAt.toUtc(),
            timeOutProjectName: abc.name,
            totalMinutes: savedMinutes,
            pending: true,
          );
  }

  @override
  Future<AttendanceRecord?> today() async {
    if (todayError != null) throw todayError!;
    return todayRecord;
  }

  @override
  Future<List<AttendanceRecord>> history(String from, String to) async {
    historyCalls.add((from, to));
    final gate = historyGate;
    if (gate != null) await gate.future;
    if (historyError != null) throw historyError!;
    return historyRecords;
  }

  @override
  Future<List<PendingSubmission>> refusedSubmissions() async => refused;

  @override
  Future<void> dismissRefused(String eventId) async {
    dismissed.add(eventId);
    refused = refused.where((p) => p.eventId != eventId).toList();
  }
}

class FakeDevice implements DeviceBridge {
  DeviceFix fix = const DeviceFix(latitude: 14.5995, longitude: 120.9842, accuracyMetres: 8);
  int fixes = 0;
  int locationSettingsOpened = 0;

  @override
  Future<DeviceClockReading> clock() async => const DeviceClockReading(uptimeMillis: 0, bootCount: null);
  @override
  Future<bool> isOnline() async => true;
  @override
  Future<DeviceFix> currentFix() async {
    fixes++;
    return fix;
  }

  @override
  Future<String> preparePhoto({required String source, required String target, required String caption, bool mirror = false}) async =>
      target;

  @override
  Future<void> openLocationSettings() async {
    locationSettingsOpened++;
  }
}

class FakeScheduler implements UploadScheduler {
  int sendNows = 0;
  @override
  Future<void> enqueue(String eventId) async {}
  @override
  Future<void> sendNow() async {
    sendNows++;
  }

  @override
  Future<void> ensureSweeper() async {}
}

/// A row the server refused for good, as the queue stores it.
PendingSubmission refusedRow({
  String eventId = 'e9',
  TimeDirection direction = TimeDirection.timeIn,
  String capturedAt = '2026-08-18T23:45:00Z',
  String lastError = 'outsideRadius',
}) {
  final ms = DateTime.parse(capturedAt).millisecondsSinceEpoch;
  return PendingSubmission.fromMap({
    'event_id': eventId,
    'worker_id': 'u1',
    'direction': direction.wire,
    'project_system': 'pc',
    'project_id': 'p1',
    'project_name': abc.name,
    'captured_at': ms,
    'trusted_at': null,
    'photo_local_path': '/nope/$eventId.jpg',
    'description': null,
    'latitude': null,
    'longitude': null,
    'accuracy_metres': null,
    'was_offline': 0,
    'is_mock': 0,
    'permission_denied': 0,
    'location_status': null,
    'attempts': 1,
    'last_error': lastError,
    'failed_permanently': 1,
    'created_at': ms,
  });
}

/// A tall phone (400 x 1000 logical), so whole screens build in widget tests.
void useTallPhone(WidgetTester tester) {
  tester.view.physicalSize = const Size(1200, 3000);
  tester.view.devicePixelRatio = 3.0;
  addTearDown(tester.view.reset);
}

/// A RewardApi whose answers the test sets.
class FakeRewards implements RewardApi {
  List<RewardDay> days = [];
  Object? error;
  double? amount;
  Object? amountError;
  final weekStarts = <DateTime>[];

  @override
  Future<List<RewardDay>> weekProgress(DateTime weekStart) async {
    weekStarts.add(weekStart);
    if (error != null) throw error!;
    return days;
  }

  @override
  Future<double?> rewardAmount() async {
    if (amountError != null) throw amountError!;
    return amount;
  }
}
