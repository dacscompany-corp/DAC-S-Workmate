import 'dart:async';
import 'dart:isolate';
import 'dart:ui';

import 'package:flutter_test/flutter_test.dart';
import 'package:workmate/attendance/sync/sync_host.dart';

void main() {
  AttendanceSyncHost? host;
  setUp(() => IsolateNameServer.removePortNameMapping(syncPortName));
  tearDown(() {
    host?.dispose();
    host = null;
    IsolateNameServer.removePortNameMapping(syncPortName);
  });

  test('no host registered: null', () async {
    expect(await delegateToLiveApp(), isNull);
  });

  test("a registered host returns the drain's result", () async {
    var result = true;
    host = AttendanceSyncHost(drain: () async => result)..register();
    expect(await delegateToLiveApp(), isTrue);
    result = false;
    expect(await delegateToLiveApp(), isFalse);
  });

  test('a drain that throws means retry (false)', () async {
    host = AttendanceSyncHost(drain: () async => throw StateError('boom'))..register();
    expect(await delegateToLiveApp(), isFalse);
  });

  test('a stale mapping yields null and is removed', () async {
    final dead = ReceivePort();
    IsolateNameServer.registerPortWithName(dead.sendPort, syncPortName);
    dead.close();
    expect(await delegateToLiveApp(ackTimeout: const Duration(milliseconds: 200)), isNull);
    expect(IsolateNameServer.lookupPortByName(syncPortName), isNull);
  });

  test('concurrent delegations share one drain', () async {
    var calls = 0;
    final gate = Completer<bool>();
    host = AttendanceSyncHost(drain: () {
      calls++;
      return gate.future;
    })..register();
    final a = delegateToLiveApp();
    final b = delegateToLiveApp();
    await Future<void>.delayed(const Duration(milliseconds: 200));
    gate.complete(true);
    expect(await a, isTrue);
    expect(await b, isTrue);
    expect(calls, 1);
  });
}
