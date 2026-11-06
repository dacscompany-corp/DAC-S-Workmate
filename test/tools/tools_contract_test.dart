import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:workmate/profile/password_change.dart';
import 'package:workmate/profile/password_prompt.dart';
import 'package:workmate/tools/data/tools_remote.dart';
import 'package:workmate/tools/domain/tool_submission.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'server_answers.dart';

/// The real SupabaseToolsRemote, over a fake HTTP server: every function it
/// calls and every parameter name it sends, as PostgREST receives them. The
/// list it is held to (SupabaseToolsRemote.calls) is 0111's own signatures —
/// checked against the migration and the live definitions before review.
void main() {
  late List<(String fn, Map<String, dynamic> body)> sent;
  late List<String?> passwordChangedFor;
  late SupabaseClient client;

  /// Whose sign-in a request carries: the `sub` of its bearer token.
  String? caller(http.BaseRequest req) {
    final auth = req.headers['authorization'] ?? req.headers['Authorization'] ?? '';
    final parts = auth.replaceFirst('Bearer ', '').split('.');
    if (parts.length != 3) return null;
    try {
      return (jsonDecode(utf8.decode(base64Url.decode(base64Url.normalize(parts[1])))) as Map)['sub'] as String?;
    } catch (_) {
      return null;
    }
  }

  String answerFor(String fn) => switch (fn) {
        'tl_my_tools' => myToolsJson,
        'tl_my_tool' => myToolJson,
        'tl_team_tools' => teamToolsJson,
        'tl_team_tool' => teamToolJson,
        'tl_team_find' => findJson,
        'tl_team_choices' => choicesJson,
        'tl_team_request_lines' => requestLinesJson,
        'tl_team_my_records' => myRecordsJson,
        'wk_password_state' => passwordOwedJson,
        'wk_password_changed_for' => passwordChangedJson,
        _ => '{"record_id": "rec-1"}',
      };

  /// A signed-in account on this client, as a stored session restores it —
  /// no network: its access token is a well-formed token that hasn't expired.
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
        'user_metadata': <String, dynamic>{}, 'created_at': '2026-11-06T00:00:00Z',
      },
    }));
  }

  setUp(() {
    sent = [];
    passwordChangedFor = [];
    client = SupabaseClient(
      'https://example.test',
      'anon-key',
      httpClient: MockClient((req) async {
        final fn = req.url.pathSegments.last;
        // A call with no parameters sends no body, or JSON null.
        final decoded = req.body.trim().isEmpty ? null : jsonDecode(req.body);
        final body = decoded is Map ? Map<String, dynamic>.from(decoded) : <String, dynamic>{};
        sent.add((fn, body));
        // gotrue's PUT /auth/v1/user: it changes the password of whoever's
        // sign-in the request carries, and answers with that account.
        if (req.url.path.endsWith('/auth/v1/user')) {
          final who = caller(req);
          passwordChangedFor.add(who);
          return http.Response(
              jsonEncode({'id': who, 'aud': 'authenticated', 'role': 'authenticated', 'app_metadata': {}, 'user_metadata': {}, 'created_at': '2026-11-06T00:00:00Z'}),
              200,
              headers: {'content-type': 'application/json; charset=utf-8'},
              request: req);
        }
        return http.Response(answerFor(fn), 200, headers: {'content-type': 'application/json; charset=utf-8'}, request: req);
      }),
      authOptions: const AuthClientOptions(autoRefreshToken: false),
    );
  });

  tearDown(() => client.dispose());

  test('every read calls its 0111 function with exactly its parameters', () async {
    final r = SupabaseToolsRemote(client);
    expect((await r.myTools()).length, 2);
    expect((await r.myTool('t1')).records, isNotEmpty);
    expect((await r.teamTools()).length, 4);
    await r.teamTool('t2');
    expect((await r.find('TOOL-0003')).label, 'TOOL-0003');
    expect((await r.choices()).members, hasLength(4));
    expect(await r.requestLines('t3', 'f1'), hasLength(1));
    expect(await r.myRecords(), hasLength(3));
    for (final (fn, body) in sent) {
      expect(SupabaseToolsRemote.calls.containsKey(fn), isTrue, reason: fn);
      expect(body.keys.toSet(), SupabaseToolsRemote.calls[fn]!.toSet(), reason: fn);
    }
    expect(sent.map((s) => s.$1), [
      'tl_my_tools', 'tl_my_tool', 'tl_team_tools', 'tl_team_tool', 'tl_team_find', 'tl_team_choices', 'tl_team_request_lines',
      'tl_team_my_records',
    ]);
    expect(sent[4].$2, {'p_number': 'TOOL-0003'});
    expect(sent[6].$2, {'p_tool': 't3', 'p_folder': 'f1'});
  });

  test('the five writes are 0111\'s team and report functions — never the office\'s own', () {
    for (final w in ToolWrite.values) {
      expect(SupabaseToolsRemote.calls.containsKey(w.fn), isTrue, reason: w.fn);
    }
    expect(ToolWrite.values.map((w) => w.fn).where((fn) => !fn.startsWith('tl_team_') && fn != 'tl_report_problem'), isEmpty);
  });

  test('a write, a Check or a Cancel for an account that is not signed in is refused on the phone: nothing is sent', () async {
    final r = SupabaseToolsRemote(client);
    for (final call in [
      () => r.write(ToolWrite.issue, {'p_op': 'op1', 'p_body': <String, dynamic>{}}, userId: 'u1'),
      () => r.opState('op1', userId: 'u1'),
      () => r.cancelOp('op1', userId: 'u1'),
    ]) {
      await expectLater(call(), throwsA(isA<StateError>().having((e) => e.message, 'message', 'AUTH_REQUIRED')));
    }
    expect(sent, isEmpty);
  });

  test('signed in, a write is its 0111 function with exactly the payload given', () async {
    await signIn('u7');
    final r = SupabaseToolsRemote(client);
    final body = {'tool_id': 't3', 'holder_id': 'u5', 'folder_id': 'f1', 'request_line_id': null, 'note': ''};
    await r.write(ToolWrite.issue, {'p_op': 'op1', 'p_body': body}, userId: 'u7');
    expect(sent.single.$1, 'tl_team_issue');
    expect(sent.single.$2, {'p_op': 'op1', 'p_body': body});
    await expectLater(r.write(ToolWrite.issue, {'p_op': 'op2', 'p_body': body}, userId: 'u5'),
        throwsA(isA<StateError>().having((e) => e.message, 'message', 'AUTH_REQUIRED')), reason: 'another account than the one signed in');
    expect(sent, hasLength(1));
  });

  group('the password prompt (0112)', () {
    late SharedPreferences prefs;
    setUp(() async {
      SharedPreferences.setMockInitialValues({});
      prefs = await SharedPreferences.getInstance();
    });

    test('nobody signed in: asking and confirming are refused on the phone — nothing is sent', () async {
      final p = PasswordPromptServices.supabase(client, prefs);
      await expectLater(p.owed('u7'), throwsA(isA<StateError>().having((e) => e.message, 'message', 'AUTH_REQUIRED')));
      await expectLater(p.confirm('u7', 1), throwsA(isA<StateError>().having((e) => e.message, 'message', 'AUTH_REQUIRED')));
      expect(sent, isEmpty);
    });

    test('signed in: it reads the open reset, and confirms that one reset with exactly 0112\'s parameter', () async {
      await signIn('u7');
      final p = PasswordPromptServices.supabase(client, prefs);
      final o = await p.owed('u7');
      expect([o.mustChange, o.resetId], [true, 1], reason: 'the real 0112 answer');
      expect(await p.confirm('u7', 1), isTrue);
      expect(sent.map((s) => [s.$1, s.$2]), [
        ['wk_password_state', <String, dynamic>{}],
        ['wk_password_changed_for', {'p_reset': 1}],
      ]);
      for (final (fn, body) in sent) {
        expect(body.keys.toSet(), PasswordPromptServices.calls[fn]!.toSet(), reason: fn);
      }
    });

    test('signed in as one account, nothing is asked or confirmed for another', () async {
      await signIn('u5');
      final p = PasswordPromptServices.supabase(client, prefs);
      await expectLater(p.owed('u7'), throwsA(isA<StateError>().having((e) => e.message, 'message', 'AUTH_REQUIRED')));
      await expectLater(p.confirm('u7', 1), throwsA(isA<StateError>().having((e) => e.message, 'message', 'AUTH_REQUIRED')));
      expect(sent, isEmpty);
    });

    test('the password change, signed in as the prompt\'s account: one request, carrying that account\'s sign-in', () async {
      await signIn('u7');
      final p = PasswordPromptServices.supabase(client, prefs);
      await p.changePassword('u7', 'typed-for-a-1');
      expect(passwordChangedFor, ['u7']);
      expect(sent.single.$2, {'password': 'typed-for-a-1'});
    });

    test('A\'s password change while B is signed in: refused on the phone — no request leaves, B\'s password is untouched', () async {
      await signIn('u5');
      final p = PasswordPromptServices.supabase(client, prefs);
      Object? why;
      try {
        await p.changePassword('u7', 'typed-for-a-1');
      } catch (e) {
        why = e;
      }
      expect(why, isA<StateError>());
      expect(PasswordChangeFailure.of(why!), PasswordChangeFailure.sessionExpired);
      expect([passwordChangedFor, sent], [isEmpty, isEmpty]);
    });

    test('0111\'s wk_password_changed — which closes whatever reset is open — is never called', () {
      expect(PasswordPromptServices.calls.keys, isNot(contains('wk_password_changed')));
      expect(PasswordPromptServices.calls.keys.toSet(), {'wk_password_state', 'wk_password_changed_for'});
    });
  });
}
