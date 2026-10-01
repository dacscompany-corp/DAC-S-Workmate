import 'package:flutter/services.dart';

import '../domain/location_verification.dart';

class DeviceClockReading {
  const DeviceClockReading({required this.uptimeMillis, required this.bootCount});

  /// SystemClock.elapsedRealtime(): counts forward from boot, untouchable from Settings.
  final int uptimeMillis;

  /// Settings.Global.BOOT_COUNT, or null when the phone does not say.
  final int? bootCount;
}

/// What only Android can do for attendance. An interface so the rules and
/// repositories test without a phone. Not available in the background sync
/// isolate (nothing there needs it).
abstract class DeviceBridge {
  Future<DeviceClockReading> clock();

  /// A VALIDATED internet connection right now (fills was_offline).
  Future<bool> isOnline();

  /// One fresh fix at the shutter. Never throws: every failure is a DeviceFix.
  Future<DeviceFix> currentFix();

  /// Upright, scaled to 1600 px, caption burned in, JPEG 80 at [target];
  /// deletes [source]. [mirror] flips a front-camera capture so the filed
  /// photo matches the mirrored preview the worker approved. Returns [target].
  Future<String> preparePhoto({required String source, required String target, required String caption, bool mirror = false});

  /// Opens the phone-wide Location switch screen — NOT the app's permission
  /// page: sending a worker to the wrong screen strands them.
  Future<void> openLocationSettings();
}

double? _double(Object? v) => (v as num?)?.toDouble();

DeviceFix deviceFixFromMap(Map<Object?, Object?> map) => DeviceFix(
      latitude: _double(map['latitude']),
      longitude: _double(map['longitude']),
      accuracyMetres: _double(map['accuracyMetres']),
      isMock: map['isMock'] == true,
      permissionDenied: map['permissionDenied'] == true,
      locationDisabled: map['locationDisabled'] == true,
    );

class MethodChannelDeviceBridge implements DeviceBridge {
  static const _channel = MethodChannel('com.dacs.workmate/attendance');

  @override
  Future<DeviceClockReading> clock() async {
    final m = await _channel.invokeMapMethod<Object?, Object?>('clock') ?? const {};
    return DeviceClockReading(
      uptimeMillis: (m['uptimeMillis'] as num).toInt(),
      bootCount: (m['bootCount'] as num?)?.toInt(),
    );
  }

  @override
  Future<bool> isOnline() async => await _channel.invokeMethod<bool>('isOnline') ?? false;

  @override
  Future<DeviceFix> currentFix() async {
    try {
      return deviceFixFromMap(await _channel.invokeMapMethod<Object?, Object?>('currentFix') ?? const {});
    } catch (_) {
      // "The phone could not tell" is flagged, never a lockout.
      return const DeviceFix();
    }
  }

  @override
  Future<String> preparePhoto({required String source, required String target, required String caption, bool mirror = false}) async =>
      await _channel.invokeMethod<String>(
        'preparePhoto',
        {'source': source, 'target': target, 'caption': caption, 'mirror': mirror},
      ) ??
      target;

  @override
  Future<void> openLocationSettings() async {
    await _channel.invokeMethod<void>('openLocationSettings');
  }
}
