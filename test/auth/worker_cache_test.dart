import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:workmate/auth/worker_cache.dart';
import 'package:workmate/auth/worker_profile.dart';

void main() {
  const juan = WorkerProfile(id: 'u1', email: 'juan@x.com', displayName: 'Juan dela Cruz', role: 'worker', status: 'active', workerNo: 42);

  setUp(() => SharedPreferences.setMockInitialValues({}));

  test('remembers who signed in and their profile', () async {
    final cache = WorkerCache(await SharedPreferences.getInstance());
    await cache.remember(juan);
    expect(cache.lastSignedInId, 'u1');
    expect(cache.recall('u1')!.toRow(), juan.toRow());
  });

  test('records the Terms version this device saw accepted', () async {
    final cache = WorkerCache(await SharedPreferences.getInstance());
    await cache.recordTermsAccepted('u1', '2026-09-v3');
    expect(cache.acceptedTermsVersion('u1'), '2026-09-v3');
  });

  test('forget clears everything about that worker (shared site phones)', () async {
    final cache = WorkerCache(await SharedPreferences.getInstance());
    await cache.remember(juan);
    await cache.recordTermsAccepted('u1', '2026-09-v3');
    await cache.forget('u1');
    expect(cache.lastSignedInId, isNull);
    expect(cache.recall('u1'), isNull);
    expect(cache.acceptedTermsVersion('u1'), isNull);
  });

  test('remembers when the Terms were accepted, and forgets it at sign-out', () async {
    final cache = WorkerCache(await SharedPreferences.getInstance());
    final at = DateTime.utc(2026, 8, 2, 17);
    await cache.recordTermsAcceptedAt('u1', 'v1', at);
    expect(cache.termsAcceptedAt('u1', 'v1'), at);
    await cache.forget('u1');
    expect(cache.termsAcceptedAt('u1', 'v1'), isNull);
  });

  test('a Terms date remembered for one version is not shown for another', () async {
    final cache = WorkerCache(await SharedPreferences.getInstance());
    await cache.recordTermsAcceptedAt('u1', 'v1', DateTime.utc(2026, 8, 2, 17));
    expect(cache.termsAcceptedAt('u1', 'v2'), isNull);
  });
}
