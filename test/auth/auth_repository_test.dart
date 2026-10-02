import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:workmate/auth/auth_backend.dart';
import 'package:workmate/auth/auth_repository.dart';
import 'package:workmate/auth/login_failure.dart';
import 'package:workmate/auth/session_gate.dart';
import 'package:workmate/auth/sign_in_api.dart';
import 'package:workmate/auth/worker_cache.dart';
import 'package:workmate/auth/worker_profile.dart';

class FakeBackend implements AuthBackend {
  SessionPresence presenceValue = SessionPresence.absent;
  String? userId;
  Map<String, dynamic>? profileRow;
  Object? profileError;
  Object? adoptError;
  bool signedOut = false;
  String? adoptedRefresh;
  final passwords = <String>[];
  Object? passwordError;

  @override
  Future<void> changePassword(String newPassword) async {
    if (passwordError != null) throw passwordError!;
    passwords.add(newPassword);
  }

  @override
  Future<void> adopt({required String accessToken, required String refreshToken}) async {
    if (adoptError != null) throw adoptError!;
    adoptedRefresh = refreshToken;
  }

  @override
  Future<SessionPresence> presence() async => presenceValue;
  @override
  String? get currentUserId => userId;
  @override
  Future<Map<String, dynamic>?> readProfile(String userId) async {
    if (profileError != null) throw profileError!;
    return profileRow;
  }

  @override
  Future<void> signOut() async => signedOut = true;
}

SignInApi apiReturning(int status, String body) => SignInApi(MockClient((_) async => http.Response(body, status)));

const okBody = '{"session":{"access_token":"A","refresh_token":"R","expires_in":3600},'
    '"worker":{"id":"u1","display_name":"Juan dela Cruz","role":"worker","status":"active"}}';

void main() {
  late WorkerCache cache;
  late FakeBackend backend;

  setUp(() async {
    SharedPreferences.setMockInitialValues({});
    cache = WorkerCache(await SharedPreferences.getInstance());
    backend = FakeBackend();
  });

  group('signIn', () {
    test('empty fields never reach the server', () async {
      final repo = AuthRepository(api: apiReturning(500, ''), backend: backend, cache: cache);
      expect(() => repo.signIn(' ', 'x'),
          throwsA(isA<LoginRejected>().having((e) => e.failure, 'failure', LoginFailure.missingFields)));
    });

    test('success adopts the session and remembers the worker for the first offline launch', () async {
      final repo = AuthRepository(api: apiReturning(200, okBody), backend: backend, cache: cache);
      final w = await repo.signIn('juan@x.com', 'pw');
      expect(w.id, 'u1');
      expect(backend.adoptedRefresh, 'R');
      expect(cache.lastSignedInId, 'u1');
    });

    test('a refusal code becomes its message', () async {
      final repo = AuthRepository(api: apiReturning(401, '{"error":"INVALID_CREDENTIALS"}'), backend: backend, cache: cache);
      expect(() => repo.signIn('a@b.c', 'x'),
          throwsA(isA<LoginRejected>().having((e) => e.failure, 'failure', LoginFailure.wrongCredentials)));
    });

    test('no signal is reported as no signal', () async {
      final repo = AuthRepository(
          api: SignInApi(MockClient((_) async => throw const SocketException('down'))), backend: backend, cache: cache);
      expect(() => repo.signIn('a@b.c', 'x'),
          throwsA(isA<LoginRejected>().having((e) => e.failure, 'failure', LoginFailure.noConnection)));
    });
  });

  group('currentWorker', () {
    test('confirmed session: the server row wins and is cached', () async {
      backend
        ..presenceValue = SessionPresence.confirmed
        ..userId = 'u1'
        ..profileRow = {'id': 'u1', 'role': 'worker', 'status': 'inactive'};
      final repo = AuthRepository(api: apiReturning(500, ''), backend: backend, cache: cache);
      final w = await repo.currentWorker();
      expect(w!.status, 'inactive');
      expect(cache.recall('u1')!.status, 'inactive');
    });

    test('confirmed session but the read fails (no signal): last known profile', () async {
      await cache.remember(const WorkerProfileForTest().profile);
      backend
        ..presenceValue = SessionPresence.confirmed
        ..userId = 'u1'
        ..profileError = const SocketException('down');
      final repo = AuthRepository(api: apiReturning(500, ''), backend: backend, cache: cache);
      expect((await repo.currentWorker())!.id, 'u1');
    });

    test('unverifiable session: last known profile, no read made', () async {
      await cache.remember(const WorkerProfileForTest().profile);
      backend
        ..presenceValue = SessionPresence.unverifiable
        ..profileError = StateError('must not read without a session');
      final repo = AuthRepository(api: apiReturning(500, ''), backend: backend, cache: cache);
      expect((await repo.currentWorker())!.id, 'u1');
    });

    test('no session: signed out even with a cached profile', () async {
      await cache.remember(const WorkerProfileForTest().profile);
      backend.presenceValue = SessionPresence.absent;
      final repo = AuthRepository(api: apiReturning(500, ''), backend: backend, cache: cache);
      expect(await repo.currentWorker(), isNull);
    });
  });

  test('signOut forgets the worker BEFORE the session goes', () async {
    await cache.remember(const WorkerProfileForTest().profile);
    backend.userId = null; // offline: the client reports nobody
    final repo = AuthRepository(api: apiReturning(500, ''), backend: backend, cache: cache);
    await repo.signOut();
    expect(cache.lastSignedInId, isNull);
    expect(cache.recall('u1'), isNull);
    expect(backend.signedOut, isTrue);
  });

  test('a password change goes to the signed-in session, unchanged', () async {
    final backend = FakeBackend();
    SharedPreferences.setMockInitialValues({});
    final repo = AuthRepository(api: apiReturning(200, '{}'), backend: backend, cache: WorkerCache(await SharedPreferences.getInstance()));
    await repo.changePassword('bagongpass1');
    expect(backend.passwords, ['bagongpass1']);
  });

  test('a refused password change reaches the caller to be explained', () async {
    final backend = FakeBackend()..passwordError = const SocketException('down');
    SharedPreferences.setMockInitialValues({});
    final repo = AuthRepository(api: apiReturning(200, '{}'), backend: backend, cache: WorkerCache(await SharedPreferences.getInstance()));
    expect(() => repo.changePassword('bagongpass1'), throwsA(isA<SocketException>()));
  });
}

class WorkerProfileForTest {
  const WorkerProfileForTest();
  WorkerProfile get profile => const WorkerProfile(id: 'u1', displayName: 'Juan dela Cruz', role: 'worker', status: 'active');
}
