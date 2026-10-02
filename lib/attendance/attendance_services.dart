import 'package:flutter/widgets.dart';

import 'data/attendance_api.dart';
import 'data/reward_remote.dart';
import 'device/device_bridge.dart';
import 'flow/camera_step.dart';
import 'flow/time_flow_screen.dart';
import 'sync/upload_scheduler.dart';
import 'ui/attendance_copy.dart';

/// The real camera step (tests pass a fake builder instead).
Widget realCameraStep(BuildContext context, CameraStepArgs args) => CameraStep(args: args);

/// Everything the attendance screens need, built once in main.dart.
class AttendanceServices {
  const AttendanceServices({
    required this.attendance,
    required this.device,
    required this.scheduler,
    required this.trustedNow,
    required this.photoUrl,
    required this.openSettings,
    this.rewards,
    this.queueSettled,
    this.cameraStep = realCameraStep,
  });

  final AttendanceApi attendance;
  final DeviceBridge device;
  final UploadScheduler scheduler;

  /// The time the worker cannot change (0078), or null when it cannot vouch.
  final Future<DateTime?> Function() trustedNow;

  /// A link for one stored photo, or null.
  final Future<String?> Function(String? path) photoUrl;

  /// The app's permission page, or the phone's Location switch.
  final Future<void> Function(SettingsRoute route) openSettings;

  /// The weekly reward reads; null in tests that do not need them.
  final RewardApi? rewards;

  /// Fires when the live app's background drain settled rows (main.dart).
  final Listenable? queueSettled;

  final CameraStepBuilder cameraStep;
}
