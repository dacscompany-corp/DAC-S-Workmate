import 'dart:convert';

import 'package:http/http.dart' as http;

import '../config/app_config.dart';
import 'worker_profile.dart';

sealed class SignInOutcome {}

class SignInSuccess extends SignInOutcome {
  SignInSuccess({required this.accessToken, required this.refreshToken, required this.worker});
  final String accessToken;
  final String refreshToken;
  final WorkerProfile worker;
}

class SignInRefused extends SignInOutcome {
  SignInRefused(this.code);
  final String? code;
}

/// Sign-in through the `attendance-signin` Edge Function. Turnstile guards
/// the auth endpoint and has no native Android SDK; the function signs in
/// with the service role and refuses non-workers before any token exists.
class SignInApi {
  SignInApi(this._http);

  final http.Client _http;

  Future<SignInOutcome> signIn(String email, String password) async {
    final response = await _http
        .post(
          Uri.parse(AppConfig.signInFunctionUrl),
          headers: {
            'apikey': AppConfig.supabaseAnonKey,
            'Authorization': 'Bearer ${AppConfig.supabaseAnonKey}',
            'Content-Type': 'application/json',
          },
          body: jsonEncode({'email': email, 'password': password}),
        )
        // A worker in the sun needs "no signal" quickly, not a spinner.
        .timeout(const Duration(seconds: 20));

    if (response.statusCode >= 200 && response.statusCode < 300) {
      final body = jsonDecode(response.body) as Map<String, dynamic>;
      final session = body['session'] as Map<String, dynamic>;
      return SignInSuccess(
        accessToken: session['access_token'] as String,
        refreshToken: session['refresh_token'] as String,
        worker: WorkerProfile.fromRow(body['worker'] as Map<String, dynamic>),
      );
    }
    // A body we cannot parse is still a refusal, never a network problem.
    String? code;
    try {
      code = (jsonDecode(response.body) as Map<String, dynamic>)['error'] as String?;
    } catch (_) {}
    return SignInRefused(code);
  }
}
