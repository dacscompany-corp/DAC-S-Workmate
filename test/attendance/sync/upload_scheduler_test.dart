import 'package:flutter_test/flutter_test.dart';
import 'package:workmate/attendance/sync/upload_scheduler.dart';

class RecordingRegistrar implements WorkRegistrar {
  final calls = <String>[];
  @override
  Future<void> oneOff({required String uniqueName, required bool replace}) async =>
      calls.add('oneOff $uniqueName ${replace ? 'REPLACE' : 'KEEP'}');
  @override
  Future<void> periodic({required String uniqueName, required Duration frequency}) async =>
      calls.add('periodic $uniqueName ${frequency.inMinutes}m');
}

void main() {
  test('every upload attempt shares ONE unique name, so only one is ever in flight', () async {
    final r = RecordingRegistrar();
    final s = WorkmanagerUploadScheduler(r);
    await s.enqueue('e1');
    await s.enqueue('e2');
    await s.sendNow();
    await s.ensureSweeper();
    expect(r.calls, [
      'oneOff attendance-submission KEEP',
      'oneOff attendance-submission KEEP',
      'oneOff attendance-submission REPLACE',
      'periodic attendance-submission-sweep 15m',
    ]);
  });
}
