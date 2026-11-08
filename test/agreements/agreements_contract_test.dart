import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:workmate/agreements/data/agreements_remote.dart';

import 'agreement_fakes.dart';

/// The real SupabaseAgreementsRemote over a fake HTTP server: the one
/// function it calls and the parameters it sends, as PostgREST receives them.
/// The list it is held to (SupabaseAgreementsRemote.calls) is 0113's own
/// signature — `ll_my_agreements()`, no parameters.
void main() {
  late List<(String fn, Map<String, dynamic> body)> sent;
  late SupabaseClient client;

  Future<void> signIn(String id) {
    String part(Map<String, dynamic> m) => base64Url.encode(utf8.encode(jsonEncode(m))).replaceAll('=', '');
    final exp = DateTime.now().millisecondsSinceEpoch ~/ 1000 + 3600;
    final token = '${part({'alg': 'HS256', 'typ': 'JWT'})}.${part({'sub': id, 'exp': exp, 'aud': 'authenticated', 'role': 'authenticated'})}.c2ln';
    return client.auth.recoverSession(jsonEncode({
      'access_token': token,
      'token_type': 'bearer',
      'expires_in': 3600,
      'expires_at': exp,
      'refresh_token': 'refresh',
      'user': {
        'id': id, 'aud': 'authenticated', 'role': 'authenticated', 'app_metadata': <String, dynamic>{},
        'user_metadata': <String, dynamic>{}, 'created_at': '2026-11-08T00:00:00Z',
      },
    }));
  }

  setUp(() {
    sent = [];
    client = SupabaseClient(
      'https://example.test',
      'anon-key',
      httpClient: MockClient((req) async {
        final fn = req.url.pathSegments.last;
        final decoded = req.body.trim().isEmpty ? null : jsonDecode(req.body);
        sent.add((fn, decoded is Map ? Map<String, dynamic>.from(decoded) : <String, dynamic>{}));
        return http.Response(myAgreementsJson, 200, headers: {'content-type': 'application/json; charset=utf-8'}, request: req);
      }),
      authOptions: const AuthClientOptions(autoRefreshToken: false),
    );
  });

  tearDown(() => client.dispose());

  test('it calls only ll_my_agreements, with no parameters, and reads every agreement', () async {
    await signIn('w13');
    final list = await SupabaseAgreementsRemote(client).mine(userId: 'w13');
    expect(list.map((a) => a.id), ['a-main', 'a-aw', 'a-daily', 'a-over']);
    expect(sent.map((s) => s.$1), ['ll_my_agreements']);
    for (final (fn, body) in sent) {
      expect(SupabaseAgreementsRemote.calls.containsKey(fn), isTrue, reason: fn);
      expect(body.keys.toSet(), SupabaseAgreementsRemote.calls[fn]!.toSet(), reason: fn);
    }
    expect(SupabaseAgreementsRemote.calls, {'ll_my_agreements': <String>[]});
  });

  test('signed out, or signed in as someone else: refused before anything is asked', () async {
    final r = SupabaseAgreementsRemote(client);
    await expectLater(r.mine(userId: 'w13'), throwsA(predicate((e) => '$e'.contains('AUTH_REQUIRED'))));
    await signIn('w15');
    await expectLater(r.mine(userId: 'w13'), throwsA(predicate((e) => '$e'.contains('AUTH_REQUIRED'))));
    expect(sent, isEmpty);
  });
}
