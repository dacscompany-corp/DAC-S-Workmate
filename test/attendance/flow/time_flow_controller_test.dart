import 'dart:async';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:workmate/attendance/domain/attendance_failure.dart';
import 'package:workmate/attendance/domain/attendance_record.dart';
import 'package:workmate/attendance/domain/location_verification.dart';
import 'package:workmate/attendance/domain/work_date.dart';
import 'package:workmate/attendance/flow/time_flow_controller.dart';

import '../fakes.dart';

void main() {
  late FakeAttendance attendance;
  late FakeDevice device;
  late DateTime? trusted;
  late int ids;
  final shutter = DateTime.parse('2026-08-18T23:45:00Z');

  TimeFlowController flow({TimeDirection d = TimeDirection.timeIn}) => TimeFlowController(
        direction: d,
        attendance: attendance,
        device: device,
        trustedNow: () async => trusted,
        newId: () => 'event-${++ids}',
      );

  Future<TimeFlowController> atDescribe({TimeDirection d = TimeDirection.timeIn, bool mirrored = false, String path = '/nope/raw.jpg'}) async {
    final c = flow(d: d);
    await c.loadProjects();
    c.selectProject(abc.key);
    c.confirmProject();
    await c.photoTaken(path, shutter, mirrored: mirrored);
    c.acceptPhoto();
    return c;
  }

  setUp(() {
    attendance = FakeAttendance();
    device = FakeDevice();
    trusted = DateTime.parse('2026-08-18T23:45:02Z');
    ids = 0;
  });

  test('the projects load, and a failed load says why instead of looking empty', () async {
    final c = flow();
    expect(c.loadingProjects, isTrue);
    await c.loadProjects();
    expect(c.projects, [abc]);
    expect(c.loadingProjects, isFalse);
    expect(c.failure, isNull);
    attendance.projectsError = const SocketException('down');
    await c.loadProjects();
    expect(c.failure, AttendanceFailure.noConnection);
    expect(c.loadingProjects, isFalse);
  });

  test('the camera opens only once a project is picked', () async {
    final c = flow();
    await c.loadProjects();
    c.confirmProject();
    expect(c.step, FlowStep.pickProject);
    c.selectProject(abc.key);
    c.confirmProject();
    expect(c.step, FlowStep.takePhoto);
    expect(c.stepNumber, 2);
  });

  test('the shutter time and the trusted time are frozen at the shutter', () async {
    final c = await atDescribe();
    expect(c.photo!.capturedAt, shutter);
    expect(c.photo!.trustedAt, DateTime.parse('2026-08-18T23:45:02Z'));
    expect(c.step, FlowStep.describe);
    expect(c.stepNumber, 4);
  });

  test('retake throws the rejected photo away', () async {
    final tmp = await Directory.systemTemp.createTemp('wmflow');
    addTearDown(() => tmp.delete(recursive: true));
    final raw = File('${tmp.path}/raw.jpg')..writeAsBytesSync([1]);
    final c = flow();
    await c.loadProjects();
    c.selectProject(abc.key);
    c.confirmProject();
    await c.photoTaken(raw.path, shutter, mirrored: false);
    c.retake();
    expect(c.step, FlowStep.takePhoto);
    expect(c.photo, isNull);
    expect(raw.existsSync(), isFalse);
  });

  test('back walks one step at a time and says so on the first step', () async {
    final c = await atDescribe();
    expect(c.back(), isTrue);
    expect(c.step, FlowStep.checkPhoto);
    expect(c.back(), isTrue);
    expect(c.step, FlowStep.takePhoto);
    expect(c.photo, isNull);
    expect(c.back(), isTrue);
    expect(c.step, FlowStep.pickProject);
    expect(c.back(), isFalse);
  });

  test('SUBMIT sends the frozen shutter, the fix, the note and the mirror flag', () async {
    final c = await atDescribe(mirrored: true);
    c.setDescription('  Block A  ');
    await c.submit();
    expect(c.step, FlowStep.confirmed);
    expect(c.saved!.status, AttendanceStatus.working);
    final r = attendance.submitted.single;
    expect(r.capturedAt, shutter);
    expect(r.trustedAt, DateTime.parse('2026-08-18T23:45:02Z'));
    expect(r.photoPath, '/nope/raw.jpg');
    expect(r.description, 'Block A');
    expect(r.projectSystem, ProjectSystem.pc);
    expect(r.projectId, 'p1');
    expect(r.latitude, 14.5995);
    expect(r.accuracyMetres, 8);
    expect(r.eventId, 'event-1');
    expect(r.locationStatus, 'project_geofence_unavailable');
    expect(attendance.mirrored.single, isTrue);
  });

  test('an empty note is sent as no note', () async {
    final c = await atDescribe();
    c.setDescription('   ');
    await c.submit();
    expect(attendance.submitted.single.description, isNull);
  });

  test('a retry reuses the same event id and keeps the photo', () async {
    final c = await atDescribe();
    attendance.submitError = const SocketException('down');
    await c.submit();
    expect(c.failure, AttendanceFailure.noConnection);
    expect(c.step, FlowStep.describe);
    expect(c.photo, isNotNull);
    attendance.submitError = null;
    await c.submit();
    expect(attendance.submitted.map((r) => r.eventId).toSet(), {'event-1'});
    expect(c.step, FlowStep.confirmed);
  });

  test('a fake location is refused on the phone and never sent', () async {
    device.fix = const DeviceFix(latitude: 14.5995, longitude: 120.9842, accuracyMetres: 8, isMock: true);
    final c = await atDescribe();
    await c.submit();
    expect(c.failure, AttendanceFailure.mockLocation);
    expect(attendance.submitted, isEmpty);
    expect(c.submitting, isFalse);
  });

  test('outside the cached fence is refused on the phone', () async {
    attendance.projects = [abc.withGeofence(const Geofence(latitude: 14.5995, longitude: 120.9842, radiusMetres: 150))];
    device.fix = const DeviceFix(latitude: 14.6095, longitude: 120.9842, accuracyMetres: 8);
    final c = await atDescribe();
    await c.submit();
    expect(c.failure, AttendanceFailure.outsideRadius);
    expect(attendance.submitted, isEmpty);
  });

  test('Location switched off is refused with its own reason', () async {
    device.fix = const DeviceFix(locationDisabled: true);
    final c = await atDescribe();
    await c.submit();
    expect(c.failure, AttendanceFailure.locationDisabled);
  });

  test('a vague fix is recorded and flagged, not refused', () async {
    device.fix = const DeviceFix(latitude: 14.5995, longitude: 120.9842, accuracyMetres: 300);
    final c = await atDescribe();
    await c.submit();
    expect(attendance.submitted.single.locationStatus, 'low_accuracy');
    expect(c.step, FlowStep.confirmed);
  });

  test('a second tap while sending does nothing', () async {
    final c = await atDescribe();
    attendance.submitGate = Completer();
    final first = c.submit();
    final second = c.submit();
    expect(c.submitting, isTrue);
    attendance.submitGate!.complete();
    await Future.wait([first, second]);
    expect(attendance.submitted.length, 1);
  });

  test('chips add to the note without losing typing', () async {
    final c = await atDescribe();
    c.setDescription('Gate 2');
    c.toggleChip('Masonry');
    expect(c.description, 'Gate 2, Masonry');
    c.toggleChip('Masonry');
    expect(c.description, 'Gate 2');
  });

  test('leaving the flow deletes a photo that was never submitted', () async {
    final tmp = await Directory.systemTemp.createTemp('wmflow');
    addTearDown(() => tmp.delete(recursive: true));
    final raw = File('${tmp.path}/raw.jpg')..writeAsBytesSync([1]);
    final c = await atDescribe(path: raw.path);
    c.abandon();
    expect(raw.existsSync(), isFalse);
  });

  test('leaving after a submit never deletes the filed photo', () async {
    final tmp = await Directory.systemTemp.createTemp('wmflow');
    addTearDown(() => tmp.delete(recursive: true));
    final raw = File('${tmp.path}/raw.jpg')..writeAsBytesSync([1]);
    final c = await atDescribe(path: raw.path);
    await c.submit();
    c.abandon();
    expect(raw.existsSync(), isTrue);
  });

  test('back while sending changes nothing and keeps the photo', () async {
    final tmp = await Directory.systemTemp.createTemp('wmflow');
    addTearDown(() => tmp.delete(recursive: true));
    final raw = File('${tmp.path}/raw.jpg')..writeAsBytesSync([1]);
    final c = await atDescribe(path: raw.path);
    attendance.submitGate = Completer();
    final submitFuture = c.submit();
    // In-flight: location fix is being read, or submit is waiting on the gate.
    expect(c.step, FlowStep.describe);
    expect(c.back(), isTrue);
    expect(c.step, FlowStep.describe);
    expect(c.photo, isNotNull);
    expect(raw.existsSync(), isTrue);
    expect(c.back(), isTrue);
    expect(c.step, FlowStep.describe);
    expect(c.photo, isNotNull);
    expect(raw.existsSync(), isTrue);
    // Complete the submit and verify it succeeds.
    attendance.submitGate!.complete();
    await submitFuture;
    expect(c.step, FlowStep.confirmed);
  });

  test('leaving while sending never deletes the photo', () async {
    final tmp = await Directory.systemTemp.createTemp('wmflow');
    addTearDown(() => tmp.delete(recursive: true));
    final raw = File('${tmp.path}/raw.jpg')..writeAsBytesSync([1]);
    final c = await atDescribe(path: raw.path);
    attendance.submitGate = Completer();
    final submitFuture = c.submit();
    // In-flight: location fix is being read, or submit is waiting on the gate.
    expect(c.photo, isNotNull);
    c.abandon();
    expect(raw.existsSync(), isTrue);
    // Complete the submit and verify it succeeds.
    attendance.submitGate!.complete();
    await submitFuture;
    expect(c.step, FlowStep.confirmed);
  });

  test('one event id per flow', () {
    final a = flow();
    final b = flow();
    expect(a.eventId, 'event-1');
    expect(b.eventId, 'event-2');
  });
}
