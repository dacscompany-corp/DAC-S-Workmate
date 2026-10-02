import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:workmate/auth/worker_cache.dart';
import 'package:workmate/auth/worker_profile.dart';
import 'package:workmate/terms/attendance_terms.dart';
import 'package:workmate/terms/terms_gates.dart';
import 'package:workmate/terms/terms_repository.dart';

class FakeTermsBackend implements TermsBackend {
  Set<String>? versions;
  Object? readError;
  Object? acceptanceError;
  final calls = <String>[];
  Map<String, dynamic>? evidence;

  @override
  Future<Set<String>> acceptedVersions(String workerId) async {
    if (readError != null) throw readError!;
    return versions ?? {};
  }

  DateTime? acceptedAtValue;
  Object? acceptedAtError;
  int acceptedAtReads = 0;

  @override
  Future<DateTime?> acceptedAt(String workerId, String version) async {
    acceptedAtReads++;
    if (acceptedAtError != null) throw acceptedAtError!;
    return acceptedAtValue;
  }

  @override
  Future<void> insertEvidence(Map<String, dynamic> row) async {
    calls.add('evidence');
    evidence = row;
  }

  @override
  Future<void> insertAcceptance(Map<String, dynamic> row) async {
    calls.add('acceptance');
    if (acceptanceError != null) throw acceptanceError!;
  }
}

void main() {
  const juan = WorkerProfile(id: 'u1', email: 'juan@x.com', role: 'worker');
  late WorkerCache cache;
  late FakeTermsBackend backend;
  late TermsRepository repo;

  setUp(() async {
    SharedPreferences.setMockInitialValues({});
    cache = WorkerCache(await SharedPreferences.getInstance());
    backend = FakeTermsBackend();
    repo = TermsRepository(backend: backend, cache: cache, userAgent: 'DacsWorkMate/0.1.0 (Android 14; X Y)');
  });

  test('accepted on the server (e.g. in the Attendance app): ready, and remembered', () async {
    backend.versions = {'2026-09-v3'};
    expect(await repo.startupDecision(juan), StartupDecision.ready);
    expect(cache.acceptedTermsVersion('u1'), '2026-09-v3');
  });

  test('offline and never recorded here: unavailable, not "must accept"', () async {
    backend.readError = Exception('no signal');
    expect(await repo.startupDecision(juan), StartupDecision.unavailable);
  });

  test('accept writes the evidence FIRST, then the flag, then remembers', () async {
    await repo.accept(juan);
    expect(backend.calls, ['evidence', 'acceptance']);
    expect(backend.evidence, {
      'user_id': 'u1',
      'email': 'juan@x.com',
      'audience': 'worker',
      'doc_type': 'attendance_terms',
      'doc_title': AttendanceTerms.title,
      'doc_sha256': AttendanceTerms.sha256Hex(),
      'doc_text': AttendanceTerms.canonicalText(),
      'user_agent': 'DacsWorkMate/0.1.0 (Android 14; X Y)',
    });
    expect(cache.acceptedTermsVersion('u1'), '2026-09-v3');
  });

  test('a duplicate acceptance (retry after a dropped response) is success', () async {
    backend.acceptanceError = const PostgrestException(message: 'duplicate key value', code: '23505');
    await repo.accept(juan);
    expect(cache.acceptedTermsVersion('u1'), '2026-09-v3');
  });

  test('any other acceptance failure is reported and nothing is remembered', () async {
    backend.acceptanceError = Exception('network');
    await expectLater(repo.accept(juan), throwsException);
    expect(cache.acceptedTermsVersion('u1'), isNull);
  });

  test('the accepted date comes from the server once, then from the phone', () async {
    backend.acceptedAtValue = DateTime.utc(2026, 8, 2, 17);
    expect(await repo.acceptedAt('u1'), DateTime.utc(2026, 8, 2, 17));
    expect(await repo.acceptedAt('u1'), DateTime.utc(2026, 8, 2, 17));
    expect(backend.acceptedAtReads, 1);
  });

  test('no signal and nothing remembered: no date, never an invented one', () async {
    backend.acceptedAtError = const SocketException('down');
    expect(await repo.acceptedAt('u1'), isNull);
  });

  test('no acceptance row: no date, and nothing cached', () async {
    expect(await repo.acceptedAt('u1'), isNull);
    expect(cache.termsAcceptedAt('u1', AttendanceTerms.version), isNull);
  });

  test('a date cached for an older Terms version is ignored and replaced', () async {
    await cache.recordTermsAcceptedAt('u1', 'old-version', DateTime.utc(2026, 1, 1));
    backend.acceptedAtValue = DateTime.utc(2026, 8, 2, 17);
    expect(await repo.acceptedAt('u1'), DateTime.utc(2026, 8, 2, 17));
    expect(backend.acceptedAtReads, 1);
  });
}
