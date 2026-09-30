import 'dart:io';

import 'package:flutter/services.dart';

/// Hands a verified APK to Android. An interface so the update flow tests
/// without a device.
abstract class InstallGateway {
  /// Whether Android lets WorkMate open the installer ("Install unknown apps"
  /// is per-app from Android 8; below that the system installer asks).
  Future<bool> canInstall();

  /// Opens the "Install unknown apps" switch for WorkMate.
  Future<void> openInstallPermission();

  Future<void> install(File apk);
}

class ApkInstaller implements InstallGateway {
  static const _channel = MethodChannel('com.dacs.workmate/installer');

  @override
  Future<bool> canInstall() async => await _channel.invokeMethod<bool>('canInstall') ?? false;

  @override
  Future<void> openInstallPermission() => _channel.invokeMethod<void>('openInstallPermission');

  @override
  Future<void> install(File apk) => _channel.invokeMethod<void>('install', {'path': apk.path});
}
