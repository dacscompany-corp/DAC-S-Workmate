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

  test('registering again while still mapped keeps the same port', () async {
    host = AttendanceSyncHost(drain: () async => true)..register();
    final first = IsolateNameServer.lookupPortByName(syncPortName);
    expect(first, isNotNull);
    host!.register();
    expect(IsolateNameServer.lookupPortByName(syncPortName), first);
    expect(await delegateToLiveApp(), isTrue);
  });

  test('concurrent delegations never overlap: the late one gets one more drain', () async {
    var calls = 0;
    var running = 0;
    var overlapped = false;
    final gate = Completer<bool>();
    host = AttendanceSyncHost(drain: () async {
      calls++;
      if (++running > 1) overlapped = true;
      try {
        return await gate.future;
      } finally {
        running--;
      }
    })..register();
    final a = delegateToLiveApp();
    final b = delegateToLiveApp();
    await Future<void>.delayed(const Duration(milliseconds: 200));
    expect(calls, 1, reason: 'never two at once');
    gate.complete(true);
    expect(await a, isTrue);
    expect(await b, isTrue);
    expect(calls, 2);
    expect(overlapped, isFalse);
  });

  test('a call during a drain runs one more drain; both callers get its result', () async {
    var calls = 0;
    final gates = [Completer<bool>(), Completer<bool>()];
    host = AttendanceSyncHost(drain: () => gates[calls++].future);
    final first = host!.drainNow();
    await Future<void>.delayed(Duration.zero);
    final second = host!.drainNow();
    gates[0].complete(false);
    await Future<void>.delayed(Duration.zero);
    expect(calls, 2, reason: 'the row queued mid-drain gets a drain of its own');
    gates[1].complete(true);
    expect(await first, isTrue);
    expect(await second, isTrue);
    expect(calls, 2);
  });

  test('no call during a drain: exactly one drain', () async {
    var calls = 0;
    host = AttendanceSyncHost(drain: () async {
      calls++;
      return true;
    });
    expect(await host!.drainNow(), isTrue);
    expect(calls, 1);
  });

  test('a throwing drain returns false and frees the host for the next call', () async {
    var calls = 0;
    host = AttendanceSyncHost(drain: () async {
      if (calls++ == 0) throw StateError('boom');
      return true;
    });
    expect(await host!.drainNow(), isFalse);
    expect(await host!.drainNow(), isTrue);
    expect(calls, 2);
  });
}
