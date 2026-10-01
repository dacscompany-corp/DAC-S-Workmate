import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:workmate/attendance/device/device_bridge.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  const channel = MethodChannel('com.dacs.workmate/attendance');
  final calls = <MethodCall>[];

  setUp(() {
    calls.clear();
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger.setMockMethodCallHandler(channel, (call) async {
      calls.add(call);
      switch (call.method) {
        case 'clock':
          return {'uptimeMillis': 123456789, 'bootCount': 7};
        case 'isOnline':
          return true;
        case 'currentFix':
          return {'latitude': 14.5, 'longitude': 121.0, 'accuracyMetres': 8.5, 'isMock': false};
        case 'preparePhoto':
          return (call.arguments as Map)['target'];
        case 'openLocationSettings':
          return null;
      }
      return null;
    });
  });

  tearDown(() => TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger.setMockMethodCallHandler(channel, null));

  test('clock reads uptime and boot count', () async {
    final c = await MethodChannelDeviceBridge().clock();
    expect(c.uptimeMillis, 123456789);
    expect(c.bootCount, 7);
  });

  test('a fix map becomes a DeviceFix', () async {
    final f = await MethodChannelDeviceBridge().currentFix();
    expect(f.latitude, 14.5);
    expect(f.accuracyMetres, 8.5);
    expect(f.permissionDenied, isFalse);
  });

  test('refusal flags and missing coordinates map faithfully', () {
    expect(deviceFixFromMap({'permissionDenied': true}).permissionDenied, isTrue);
    expect(deviceFixFromMap({'locationDisabled': true}).locationDisabled, isTrue);
    final none = deviceFixFromMap({});
    expect(none.latitude, isNull);
    expect(none.isMock, isFalse);
    expect(deviceFixFromMap({'latitude': 14, 'longitude': 121, 'accuracyMetres': 5}).latitude, 14.0);
  });

  test('preparePhoto passes source, target and caption', () async {
    final out = await MethodChannelDeviceBridge().preparePhoto(source: '/c/raw.jpg', target: '/f/e.jpg', caption: 'A · 1 Sep 2026 · 3:00 PM');
    expect(out, '/f/e.jpg');
    expect(calls.single.arguments, {'source': '/c/raw.jpg', 'target': '/f/e.jpg', 'caption': 'A · 1 Sep 2026 · 3:00 PM', 'mirror': false});
  });

  test('a front-camera photo asks the phone to mirror it', () async {
    await MethodChannelDeviceBridge().preparePhoto(source: '/c/raw.jpg', target: '/f/e.jpg', caption: 'A', mirror: true);
    expect((calls.single.arguments as Map)['mirror'], isTrue);
  });

  test("the phone's Location switch screen is opened natively", () async {
    await MethodChannelDeviceBridge().openLocationSettings();
    expect(calls.single.method, 'openLocationSettings');
  });
}
