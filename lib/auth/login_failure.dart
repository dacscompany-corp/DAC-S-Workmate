import 'dart:async';
import 'dart:io';

import 'package:http/http.dart' as http;
import 'package:supabase_flutter/supabase_flutter.dart' show AuthRetryableFetchException;

/// Every way signing in can fail, reduced to one sentence the worker sees.
/// A raw HTTP or Postgres string never reaches the screen.
enum LoginFailure {
  missingFields('Fill in your email and password.', 'Punan ang email at password.'),
  wrongCredentials('That email and password do not match.', 'Hindi tugma ang email at password.'),
  accountInactive('This account is turned off. Call the office.', 'Naka-off ang account na ito. Tawagan ang opisina.'),
  notAWorker('This is not a worker account.', 'Hindi ito worker account.'),
  tooManyAttempts('Too many tries. Wait a minute, then try again.', 'Sobrang dami nang subok. Maghintay ng isang minuto.'),
  noConnection('No signal right now. Try again in a moment.', 'Walang signal ngayon. Subukan ulit mamaya.'),
  serverProblem('Something went wrong. Try again.', 'May nasira. Subukan ulit.');

  const LoginFailure(this.english, this.tagalog);

  final String english;
  final String tagalog;

  /// The stable codes `attendance-signin` returns.
  static LoginFailure forCode(String? code) => switch (code) {
        'INVALID_CREDENTIALS' => wrongCredentials,
        'NOT_A_WORKER' => notAWorker,
        'ACCOUNT_INACTIVE' => accountInactive,
        'TOO_MANY_ATTEMPTS' => tooManyAttempts,
        // An unknown code means the function and the app drifted apart.
        _ => serverProblem,
      };

  /// Transport failures. No signal is not a wrong password: on site the
  /// two mean "try again in a minute" versus "walk to the office".
  static LoginFailure of(Object error) {
    if (error is SocketException || error is TimeoutException || error is http.ClientException ||
        error is AuthRetryableFetchException) {
      return noConnection;
    }
    final text = error.toString().toLowerCase();
    if (text.contains('invalid_credentials') || text.contains('invalid login credentials')) {
      return wrongCredentials;
    }
    return serverProblem;
  }
}
