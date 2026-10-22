import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:workmate/auth/sign_in_api.dart';
import 'package:workmate/auth/workmate_access.dart';

void main() {
  test('posts to attendance-signin with the anon key and returns the session', () async {
    late http.Request seen;
    final api = SignInApi(MockClient((req) async {
      seen = req;
      return http.Response(jsonEncode({
        'session': {'access_token': 'A', 'refresh_token': 'R', 'expires_in': 3600, 'token_type': 'bearer'},
        'worker': {'id': 'u1', 'email': 'juan@x.com', 'role': 'worker', 'status': 'active'},
      }), 200);
    }));
    final out = await api.signIn('juan@x.com', 'pw');
    expect(seen.url.toString(), 'https://hqbgduyonlbbsvjuapre.supabase.co/functions/v1/attendance-signin');
    expect(seen.headers['apikey'], isNotEmpty);
    expect(jsonDecode(seen.body), {'email': 'juan@x.com', 'password': 'pw'});
    expect(out, isA<SignInSuccess>());
    final ok = out as SignInSuccess;
    expect(ok.accessToken, 'A');
    expect(ok.refreshToken, 'R');
    expect(ok.worker.id, 'u1');
    // No `access` field (a function older than 0101): a worker.
    expect(ok.access, WorkMateAccess.worker);
  });

  test('2A-3a: a buyer is let in as a buyer', () async {
    final api = SignInApi(MockClient((_) async => http.Response(jsonEncode({
          'session': {'access_token': 'A', 'refresh_token': 'R', 'expires_in': 3600, 'token_type': 'bearer'},
          'worker': {'id': 's1', 'email': 'staff@x.com', 'role': 'staff', 'status': 'active'},
          'access': 'buyer',
        }), 200)));
    final ok = await api.signIn('staff@x.com', 'pw') as SignInSuccess;
    expect(ok.access, WorkMateAccess.buyer);
    expect(ok.worker.role, 'staff');
  });

  test('2A-3a: an unknown access value is never a buyer', () {
    expect(WorkMateAccess.parse('worker'), WorkMateAccess.worker);
    expect(WorkMateAccess.parse('owner'), WorkMateAccess.worker);
    expect(WorkMateAccess.parse(null), WorkMateAccess.worker);
    expect(WorkMateAccess.parse('buyer'), WorkMateAccess.buyer);
  });

  test('a refusal carries the function\'s code', () async {
    final api = SignInApi(MockClient((_) async => http.Response('{"error":"ACCOUNT_INACTIVE"}', 403)));
    final out = await api.signIn('a', 'b');
    expect((out as SignInRefused).code, 'ACCOUNT_INACTIVE');
  });

  test('an unreadable refusal is still a refusal, with no code', () async {
    final api = SignInApi(MockClient((_) async => http.Response('<html>502</html>', 502)));
    expect((await api.signIn('a', 'b') as SignInRefused).code, isNull);
  });
}
