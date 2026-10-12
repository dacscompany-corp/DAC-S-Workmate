import 'package:flutter_test/flutter_test.dart';
import 'package:workmate/app_controller.dart';
import 'package:workmate/auth/worker_profile.dart';
import 'package:workmate/history/data/history_account_wipe.dart';

import '../history_fakes.dart';

void main() {
  const u1 = WorkerProfile(id: 'u1');
  const u2 = WorkerProfile(id: 'u2');

  test('signed in keeps only that worker; signed out keeps nothing; switching keeps the new one', () {
    final api = FakeHistoryApi();
    final wipe = HistoryAccountWipe(api);
    wipe.onAppState(Starting());
    expect(api.kept, isEmpty, reason: 'startup decides nothing');
    wipe.onAppState(Ready(u1));
    wipe.onAppState(Ready(u1));
    expect(api.kept, ['u1'], reason: 'once per change');
    wipe.onAppState(SignedOut());
    expect(api.kept, ['u1', '']);
    wipe.onAppState(NeedsTerms(u2));
    expect(api.kept, ['u1', ''], reason: 'not let in yet');
    wipe.onAppState(Ready(u2));
    expect(api.kept, ['u1', '', 'u2']);
  });

  test('a failed wipe is tried again on the next state', () async {
    final api = FakeHistoryApi();
    final wipe = HistoryAccountWipe(api);
    api.keepError = Exception('disk');
    wipe.onAppState(Ready(u1));
    await Future<void>.delayed(Duration.zero);
    api.keepError = null;
    wipe.onAppState(Ready(u1));
    expect(api.kept, ['u1', 'u1']);
  });
}
