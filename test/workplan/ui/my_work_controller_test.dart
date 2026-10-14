import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:workmate/workplan/ui/my_work_controller.dart';

import '../workplan_fakes.dart';

void main() {
  test('a disposed controller never reads again, even if a refresh was queued during its read', () async {
    final api = FakeWorkPlanApi()..loadGate = Completer<void>();
    final controller = MyWorkController(api: api);
    final first = controller.refresh();
    await Future<void>.delayed(Duration.zero);
    expect(api.loads, 1);
    final second = controller.refresh(); // sets the re-run flag
    controller.dispose();
    api.loadGate!.complete();
    await first;
    await second;
    expect(api.loads, 1, reason: 'a second reader would belong to the next worker');
  });
}
