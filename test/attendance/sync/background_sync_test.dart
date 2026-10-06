import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:workmate/attendance/sync/background_sync.dart';
import 'package:workmate/attendance/sync/submission_sync.dart';

void main() {
  group('drainInOrder', () {
    test('attendance tells Home and the widget BEFORE the requests drain ends', () async {
      final log = <String>[];
      final requestsGate = Completer<DrainOutcome>();
      final done = drainInOrder(
        attendance: () async {
          log.add('attendance');
          return (result: SyncResult.done, settled: 1);
        },
        requests: () {
          log.add('requests started');
          return requestsGate.future;
        },
        attendanceWaiting: () async => false,
        afterAttendance: () async => log.add('afterAttendance'),
        onRequestsSettled: () => log.add('onRequestsSettled'),
      );
      await Future<void>.delayed(Duration.zero);
      expect(log, ['attendance', 'afterAttendance', 'requests started'], reason: 'the Time In reads Sent while photos still upload');
      requestsGate.complete((result: SyncResult.done, settled: 2));
      expect(await done, isTrue);
      expect(log.last, 'onRequestsSettled');
      expect(log.where((e) => e == 'afterAttendance'), hasLength(1), reason: 'requests never re-publish the widget');
    });

    test('nothing settled: nobody is told', () async {
      final log = <String>[];
      expect(
        await drainInOrder(
          attendance: () async => (result: SyncResult.done, settled: 0),
          requests: () async => (result: SyncResult.done, settled: 0),
          attendanceWaiting: () async => false,
          afterAttendance: () async => log.add('afterAttendance'),
          onRequestsSettled: () => log.add('onRequestsSettled'),
        ),
        isTrue,
      );
      expect(log, isEmpty);
    });

    test('a Time In queued during the requests phase is sent in the same run', () async {
      var attendanceRuns = 0;
      var afterCalls = 0;
      final result = await drainInOrder(
        attendance: () async => (result: SyncResult.done, settled: ++attendanceRuns == 1 ? 0 : 1),
        requests: () async => (result: SyncResult.done, settled: 1),
        attendanceWaiting: () async => true,
        afterAttendance: () async => afterCalls++,
      );
      expect(result, isTrue);
      expect(attendanceRuns, 2);
      expect(afterCalls, 1, reason: 'the second pass settled the new row');
    });

    test('no new attendance row: one attendance pass only', () async {
      var attendanceRuns = 0;
      await drainInOrder(
        attendance: () async {
          attendanceRuns++;
          return (result: SyncResult.done, settled: 1);
        },
        requests: () async => (result: SyncResult.done, settled: 0),
        attendanceWaiting: () async => false,
      );
      expect(attendanceRuns, 1);
    });

    test('an attendance pass that must retry is not run again in the same run', () async {
      var attendanceRuns = 0;
      final result = await drainInOrder(
        attendance: () async {
          attendanceRuns++;
          return (result: SyncResult.retry, settled: 0);
        },
        requests: () async => (result: SyncResult.done, settled: 0),
        attendanceWaiting: () async => true,
      );
      expect(result, isFalse);
      expect(attendanceRuns, 1);
    });

    test('a request failure never costs attendance its signal', () async {
      final log = <String>[];
      final result = await drainInOrder(
        attendance: () async => (result: SyncResult.done, settled: 1),
        requests: () async => throw StateError('requests db broken'),
        attendanceWaiting: () async => throw StateError('probe broken'),
        afterAttendance: () async => log.add('afterAttendance'),
        onRequestsSettled: () => throw StateError('never called'),
      );
      expect(result, isFalse, reason: 'WorkManager comes back for the requests');
      expect(log, ['afterAttendance']);
    });

    test('a failing screen notice changes nothing', () async {
      final result = await drainInOrder(
        attendance: () async => (result: SyncResult.done, settled: 1),
        requests: () async => (result: SyncResult.done, settled: 1),
        attendanceWaiting: () async => false,
        afterAttendance: () async => throw StateError('widget'),
        onRequestsSettled: () => throw StateError('screens'),
      );
      expect(result, isTrue);
    });
  });
}
