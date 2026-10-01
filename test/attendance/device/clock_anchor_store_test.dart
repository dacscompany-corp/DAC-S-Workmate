import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:workmate/attendance/device/clock_anchor_store.dart';
import 'package:workmate/attendance/device/device_bridge.dart';
import 'package:workmate/attendance/domain/location_verification.dart';

class FakeBridge implements DeviceBridge {
  int uptime = 1000000;
  int? boot = 3;
  @override
  Future<DeviceClockReading> clock() async => DeviceClockReading(uptimeMillis: uptime, bootCount: boot);
  @override
  Future<bool> isOnline() async => true;
  @override
  Future<DeviceFix> currentFix() async => const DeviceFix();
  @override
  Future<String> preparePhoto({required String source, required String target, required String caption, bool mirror = false}) async => target;
  @override
  Future<void> openLocationSettings() async {}
}

class ThrowingBridge extends FakeBridge {
  @override
  Future<DeviceClockReading> clock() async => throw StateError('channel down');
}

void main() {
  setUp(() => SharedPreferences.setMockInitialValues({}));

  test('a bridge that throws means no trusted time, never an exception', () async {
    final bridge = FakeBridge();
    final prefs = await SharedPreferences.getInstance();
    await ClockAnchorStore(prefs, bridge).recordServerDate('Sun, 27 Sep 2026 17:12:43 GMT');
    expect(await ClockAnchorStore(prefs, ThrowingBridge()).now(), isNull);
  });

  test('no Date header seen yet: no trusted time', () async {
    final store = ClockAnchorStore(await SharedPreferences.getInstance(), FakeBridge());
    expect(await store.now(), isNull);
  });

  test('trusted now = server Date + uptime elapsed since it arrived', () async {
    final bridge = FakeBridge();
    final store = ClockAnchorStore(await SharedPreferences.getInstance(), bridge);
    await store.recordServerDate('Sun, 27 Sep 2026 17:12:43 GMT');
    bridge.uptime += 90000;
    expect(await store.now(), DateTime.parse('2026-09-27T17:14:13Z'));
  });

  test('a reboot since the anchor voids it', () async {
    final bridge = FakeBridge();
    final store = ClockAnchorStore(await SharedPreferences.getInstance(), bridge);
    await store.recordServerDate('Sun, 27 Sep 2026 17:12:43 GMT');
    bridge.boot = 4;
    expect(await store.now(), isNull);
  });

  test('an unreadable Date header leaves the previous anchor alone', () async {
    final bridge = FakeBridge();
    final store = ClockAnchorStore(await SharedPreferences.getInstance(), bridge);
    await store.recordServerDate('Sun, 27 Sep 2026 17:12:43 GMT');
    await store.recordServerDate('garbage');
    expect(await store.now(), DateTime.parse('2026-09-27T17:12:43Z'));
  });

  test('an unknown boot count is stored as unknown, not as zero', () async {
    final bridge = FakeBridge()..boot = null;
    final store = ClockAnchorStore(await SharedPreferences.getInstance(), bridge);
    await store.recordServerDate('Sun, 27 Sep 2026 17:12:43 GMT');
    bridge.boot = 9;
    expect(await store.now(), isNotNull);
  });

  test('a garbled stored anchor is no anchor, not a crash', () async {
    for (final bad in ['garbage', '1|2', 'a|b|c', '1|2|3|4', '']) {
      SharedPreferences.setMockInitialValues({'clock.anchor': bad});
      final store = ClockAnchorStore(await SharedPreferences.getInstance(), FakeBridge());
      expect(await store.now(), isNull, reason: bad);
    }
  });
}
