import 'dart:async';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:workmate/app_controller.dart';
import 'package:workmate/auth/auth_backend.dart';
import 'package:workmate/auth/auth_repository.dart';
import 'package:workmate/auth/login_failure.dart';
import 'package:workmate/auth/session_gate.dart';
import 'package:workmate/auth/sign_in_api.dart';
import 'package:workmate/auth/worker_cache.dart';
import 'package:workmate/purchasing/buyer_access.dart';
import 'package:workmate/terms/terms_repository.dart';
import 'package:workmate/update/app_update_repository.dart';

import 'purchasing/buyer_access_test.dart' show FakeBuyerBackend;

class ExplodingCache extends WorkerCache {
  ExplodingCache(super.prefs);
  @override
  String? acceptedTermsVersion(String id) => throw StateError('boom');
}

class FakeAuth implements AuthBackend {
  SessionPresence p = SessionPresence.absent;
  Map<String, dynamic>? row;
  bool signedOut = false;
  bool signOutThrows = false;
  Future<void>? signOutGate;
  @override
  Future<void> adopt({required String accessToken, required String refreshToken}) async {}
  @override
  Future<SessionPresence> presence() async => p;
  @override
  String? get currentUserId => row?['id'] as String?;
  @override
  Future<Map<String, dynamic>?> readProfile(String userId) async => row;
  @override
  Future<void> changePassword(String newPassword) async {}
  @override
  Future<void> signOut() async {
    await signOutGate;
    if (signOutThrows) throw StateError('network');
    signedOut = true;
  }
}

class FakeTerms implements TermsBackend {
  Set<String>? versions = {};
  bool offline = false;
  @override
  Future<Set<String>> acceptedVersions(String workerId) async {
    if (offline) throw const SocketException('down');
    return versions!;
  }
  @override
  Future<DateTime?> acceptedAt(String workerId, String version) async => null;
  @override
  Future<void> insertEvidence(Map<String, dynamic> row) async {}
  @override
  Future<void> insertAcceptance(Map<String, dynamic> row) async {}
}

class FakeSource implements ReleaseSource {
  Map<String, dynamic>? row;
  @override
  Future<Map<String, dynamic>?> latestWorkMate() async => row;
}

void main() {
  late FakeAuth authBackend;
  late FakeTerms termsBackend;
  late FakeSource source;
  late StreamController<void> nudges;

  Future<AppController> build({bool explode = false, String signInBody = '{"error":"INVALID_CREDENTIALS"}', int signInStatus = 401}) async {
    final prefs = await SharedPreferences.getInstance();
    final cache = explode ? ExplodingCache(prefs) : WorkerCache(prefs);
    return AppController(
      auth: AuthRepository(
          api: SignInApi(MockClient((_) async => http.Response(signInBody, signInStatus))),
          backend: authBackend,
          cache: cache),
      terms: TermsRepository(backend: termsBackend, cache: cache, userAgent: 'test'),
      updates: AppUpdateRepository(
          source: source, prefs: prefs, installedVersionCode: 1000,
          download: MockClient((_) async => http.Response('', 404)), cacheDir: () async => Directory.systemTemp),
      nudges: nudges.stream,
    );
  }

  setUp(() {
    SharedPreferences.setMockInitialValues({});
    authBackend = FakeAuth();
    termsBackend = FakeTerms();
    source = FakeSource();
    nudges = StreamController<void>.broadcast();
  });

  test('signOut shows Starting at once and ends SignedOut even when the backend throws', () async {
    authBackend
      ..p = SessionPresence.confirmed
      ..row = {'id': 'u1', 'role': 'worker', 'status': 'active'}
      ..signOutThrows = true;
    termsBackend.versions = {'2026-09-v3'};
    final gate = Completer<void>();
    authBackend.signOutGate = gate.future;
    final c = await build();
    await c.start();
    expect(c.state, isA<Ready>());
    final done = c.signOut();
    expect(c.state, isA<Starting>());
    gate.complete();
    await done;
    expect(c.state, isA<SignedOut>());
  });

  test('no session: the login screen', () async {
    final c = await build();
    await c.start();
    expect(c.state, isA<SignedOut>());
  });

  test('restored session, accepted Terms (e.g. in the Attendance app): straight to home', () async {
    authBackend
      ..p = SessionPresence.confirmed
      ..row = {'id': 'u1', 'role': 'worker', 'status': 'active'};
    termsBackend.versions = {'2026-09-v3'};
    final c = await build();
    await c.start();
    expect(c.state, isA<Ready>());
  });

  test('restored session for a worker turned off since: signed out, told why', () async {
    authBackend
      ..p = SessionPresence.confirmed
      ..row = {'id': 'u1', 'role': 'worker', 'status': 'inactive'};
    final c = await build();
    await c.start();
    expect((c.state as SignedOut).notice, LoginFailure.accountInactive);
    expect(authBackend.signedOut, isTrue);
  });

  test('first launch offline with nothing recorded: the Terms cannot be checked, never assumed', () async {
    authBackend
      ..p = SessionPresence.confirmed
      ..row = {'id': 'u1', 'role': 'worker', 'status': 'active'};
    termsBackend.offline = true;
    final c = await build();
    await c.start();
    expect(c.state, isA<TermsUnavailable>());
  });

  test('sign-in, then Terms, then home', () async {
    final c = await build(
      signInStatus: 200,
      signInBody: '{"session":{"access_token":"A","refresh_token":"R"},"worker":{"id":"u1","role":"worker","status":"active"}}',
    );
    await c.start();
    authBackend.p = SessionPresence.confirmed;
    expect(await c.signIn('juan@x.com', 'pw'), isNull);
    expect(c.state, isA<NeedsTerms>());
    expect(await c.acceptTerms(), isNull);
    expect(c.state, isA<Ready>());
  });

  test('a wrong password stays on login with its message', () async {
    final c = await build();
    await c.start();
    expect(await c.signIn('a@b.c', 'x'), LoginFailure.wrongCredentials);
    expect(c.state, isA<SignedOut>());
  });

  test('a published newer build puts the update up; a server nudge re-checks', () async {
    final c = await build();
    await c.start();
    expect(c.requiredUpdate, isNull);
    source.row = {
      'version_code': 1001, 'version_name': '0.1.1', 'release_notes': null,
      'storage_path': 'workmate/1001.apk', 'size_bytes': 1, 'sha256': 'a',
    };
    nudges.add(null);
    await Future<void>.delayed(const Duration(milliseconds: 10));
    expect(c.requiredUpdate!.versionCode, 1001);
  });

  test('a corrupt cached update is dropped; the check still works and never throws', () async {
    SharedPreferences.setMockInitialValues({'update.required': 'not json'});
    final c = await build();
    source.row = {
      'version_code': 1001, 'version_name': '0.1.1', 'release_notes': null,
      'storage_path': 'workmate/1001.apk', 'size_bytes': 1, 'sha256': 'a',
    };
    await c.checkForUpdate();
    expect(c.requiredUpdate!.versionCode, 1001);
  });

  test('an unexpected throw during startup lands on Try again, never the spinner', () async {
    authBackend
      ..p = SessionPresence.confirmed
      ..row = {'id': 'u1', 'role': 'worker', 'status': 'active'};
    final c = await build(explode: true);
    await c.start();
    expect(c.state, isA<TermsUnavailable>());
  });

  test('a restored profile that is not a worker is signed out with its reason', () async {
    authBackend
      ..p = SessionPresence.confirmed
      ..row = {'id': 'u1', 'role': 'admin', 'status': 'active'};
    final c = await build();
    await c.start();
    expect((c.state as SignedOut).notice, LoginFailure.notAWorker);
  });

  group('2A-3b buyers', () {
    late FakeBuyerBackend buyerBackend;
    late BuyerAccess buyers;
    const buyerBody =
        '{"session":{"access_token":"A","refresh_token":"R"},"worker":{"id":"s1","role":"staff","status":"active"},"access":"buyer"}';

    Future<AppController> buildWithBuyers({String signInBody = buyerBody, int signInStatus = 200}) async {
      final prefs = await SharedPreferences.getInstance();
      final cache = WorkerCache(prefs);
      buyers = BuyerAccess(backend: buyerBackend, prefs: prefs);
      return AppController(
        auth: AuthRepository(
            api: SignInApi(MockClient((_) async => http.Response(signInBody, signInStatus))), backend: authBackend, cache: cache),
        terms: TermsRepository(backend: termsBackend, cache: cache, userAgent: 'test'),
        updates: AppUpdateRepository(
            source: source, prefs: prefs, installedVersionCode: 1000,
            download: MockClient((_) async => http.Response('', 404)), cacheDir: () async => Directory.systemTemp),
        nudges: nudges.stream,
        buyers: buyers,
      );
    }

    setUp(() => buyerBackend = FakeBuyerBackend());

    test('sign-in as a buyer: straight to the buyer app, never the Attendance Terms (Q23)', () async {
      termsBackend.versions = {};
      final c = await buildWithBuyers();
      await c.start();
      authBackend
        ..p = SessionPresence.confirmed
        ..row = {'id': 's1', 'role': 'staff', 'status': 'active'};
      expect(await c.signIn('staff@x.com', 'pw'), isNull);
      expect(c.state, isA<BuyerReady>());
    });

    test('sign-in as a buyer with no signal right after: still let in (the function said buyer)', () async {
      buyerBackend.offline = true;
      final c = await buildWithBuyers();
      await c.start();
      expect(await c.signIn('staff@x.com', 'pw'), isNull);
      expect(c.state, isA<BuyerReady>());
    });

    test('restored buyer session: the server is asked again (Q1 startup re-check)', () async {
      authBackend
        ..p = SessionPresence.confirmed
        ..row = {'id': 's1', 'role': 'staff', 'status': 'active'};
      final c = await buildWithBuyers();
      await c.start();
      expect(c.state, isA<BuyerReady>());
      expect(buyerBackend.asked, 1);
    });

    test('the switch was turned off since: Buying is turned off (R2), nobody is signed out', () async {
      authBackend
        ..p = SessionPresence.confirmed
        ..row = {'id': 's1', 'role': 'staff', 'status': 'active'};
      final c = await buildWithBuyers();
      await c.start();
      buyerBackend.answer = const BuyerStatus(canBuy: false, companyId: 'o1');
      await c.retryStartup();
      expect(c.state, isA<BuyingOff>());
      expect(authBackend.signedOut, isFalse);
      // Turned back on: TRY AGAIN lets them in.
      buyerBackend.answer = const BuyerStatus(canBuy: true, companyId: 'o1');
      await c.retryStartup();
      expect(c.state, isA<BuyerReady>());
    });

    test('an office account never a buyer here: signed out, "no WorkMate access"', () async {
      authBackend
        ..p = SessionPresence.confirmed
        ..row = {'id': 'a1', 'role': 'admin', 'status': 'active'};
      buyerBackend.answer = const BuyerStatus(canBuy: false, companyId: 'a1');
      final c = await buildWithBuyers();
      await c.start();
      expect((c.state as SignedOut).notice, LoginFailure.noWorkMateAccess);
      expect(authBackend.signedOut, isTrue);
    });

    test('a deactivated buyer is told so and signed out', () async {
      authBackend
        ..p = SessionPresence.confirmed
        ..row = {'id': 's1', 'role': 'staff', 'status': 'inactive'};
      final c = await buildWithBuyers();
      await c.start();
      expect((c.state as SignedOut).notice, LoginFailure.accountInactive);
      expect(buyerBackend.asked, 0);
    });

    test('first launch offline with nothing known: cannot be checked, never assumed', () async {
      authBackend
        ..p = SessionPresence.confirmed
        ..row = {'id': 's1', 'role': 'staff', 'status': 'active'};
      buyerBackend.offline = true;
      final c = await buildWithBuyers();
      await c.start();
      expect(c.state, isA<BuyerUnavailable>());
    });

    test('a buying screen refused BUYER_REQUIRED: Buying is turned off at once', () async {
      authBackend
        ..p = SessionPresence.confirmed
        ..row = {'id': 's1', 'role': 'staff', 'status': 'active'};
      final c = await buildWithBuyers();
      await c.start();
      await c.buyingTurnedOff();
      expect(c.state, isA<BuyingOff>());
      buyerBackend.offline = true;
      await c.retryStartup();
      expect(c.state, isA<BuyingOff>(), reason: 'offline, the last answer (off) stands');
    });

    test('log out forgets the buyer: nothing about them outlives it', () async {
      authBackend
        ..p = SessionPresence.confirmed
        ..row = {'id': 's1', 'role': 'staff', 'status': 'active'};
      final c = await buildWithBuyers();
      await c.start();
      await c.signOut();
      expect(c.state, isA<SignedOut>());
      expect(buyers.companyOf('s1'), isNull);
    });

    test('workers are unaffected: the Terms gate still applies, the buyer check is never asked', () async {
      authBackend
        ..p = SessionPresence.confirmed
        ..row = {'id': 'u1', 'role': 'worker', 'status': 'active'};
      termsBackend.versions = {};
      final c = await buildWithBuyers();
      await c.start();
      expect(c.state, isA<NeedsTerms>());
      expect(buyerBackend.asked, 0);
    });
  });
}
