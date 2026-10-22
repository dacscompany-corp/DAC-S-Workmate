import 'package:flutter_test/flutter_test.dart';
import 'package:workmate/app_controller.dart';
import 'package:workmate/auth/worker_profile.dart';
import 'package:workmate/purchasing/data/purchasing_account_wipe.dart';

import '../purchasing_api_fake.dart';

void main() {
  const s1 = WorkerProfile(id: 's1', role: 'staff');
  const s2 = WorkerProfile(id: 's2', role: 'staff');
  const w1 = WorkerProfile(id: 'w1', role: 'worker');

  test('a buyer keeps only their saved copy; signed out, a worker or buying off keeps none', () {
    final api = FakePurchasingApi();
    final wipe = PurchasingAccountWipe(api);
    wipe.onAppState(Starting());
    expect(api.calls, isEmpty, reason: 'startup decides nothing');
    wipe.onAppState(BuyerReady(s1));
    wipe.onAppState(BuyerReady(s1));
    expect(api.calls, ['keepOnly:s1'], reason: 'once per change');
    wipe.onAppState(BuyingOff(s1));
    expect(api.calls.last, 'keepOnly:', reason: 'R2: no prices once buying is off');
    wipe.onAppState(BuyerReady(s2));
    expect(api.calls.last, 'keepOnly:s2');
    wipe.onAppState(Ready(w1));
    expect(api.calls.last, 'keepOnly:', reason: 'a worker on the same phone sees no prices');
    wipe.onAppState(BuyerUnavailable(s1));
    wipe.onAppState(NeedsTerms(w1));
    expect(api.calls, ['keepOnly:s1', 'keepOnly:', 'keepOnly:s2', 'keepOnly:'], reason: 'gates decide nothing');
  });

  test('a failed wipe is tried again on the next state', () async {
    final api = FakePurchasingApi()..keepError = Exception('disk');
    final wipe = PurchasingAccountWipe(api);
    wipe.onAppState(BuyerReady(s1));
    await Future<void>.delayed(Duration.zero);
    api.keepError = null;
    wipe.onAppState(BuyerReady(s1));
    expect(api.calls, ['keepOnly:s1', 'keepOnly:s1']);
  });
}
