import 'package:flutter_test/flutter_test.dart';
import 'package:workmate/app_controller.dart';
import 'package:workmate/auth/worker_profile.dart';
import 'package:workmate/workplan/data/workplan_account_wipe.dart';

import '../workplan_fakes.dart';

void main() {
  const u1 = WorkerProfile(id: 'u1');
  const u2 = WorkerProfile(id: 'u2');

  test('signed in keeps only that worker; signed out keeps nothing; switching keeps the new one', () {
    final api = FakeWorkPlanApi();
    final wipe = WorkPlanAccountWipe(api);
    wipe.onAppState(Starting());
    expect(api.calls, isEmpty, reason: 'startup decides nothing');
    wipe.onAppState(Ready(u1));
    wipe.onAppState(Ready(u1));
    expect(api.calls, ['keepOnly:u1'], reason: 'once per change');
    wipe.onAppState(SignedOut());
    wipe.onAppState(NeedsTerms(u2));
    expect(api.calls, ['keepOnly:u1', 'keepOnly:'], reason: 'not let in yet');
    wipe.onAppState(Ready(u2));
    expect(api.calls, ['keepOnly:u1', 'keepOnly:', 'keepOnly:u2']);
  });

  test('a failed wipe is tried again on the next state', () async {
    final api = FakeWorkPlanApi()..keepError = Exception('disk');
    final wipe = WorkPlanAccountWipe(api);
    wipe.onAppState(Ready(u1));
    await Future<void>.delayed(Duration.zero);
    api.keepError = null;
    wipe.onAppState(Ready(u1));
    expect(api.calls, ['keepOnly:u1', 'keepOnly:u1']);
  });
}
