import 'dart:async';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:supabase_flutter/supabase_flutter.dart' show AuthRetryableFetchException;
import 'package:workmate/auth/login_failure.dart';

void main() {
  test('stable codes from attendance-signin', () {
    expect(LoginFailure.forCode('INVALID_CREDENTIALS'), LoginFailure.wrongCredentials);
    expect(LoginFailure.forCode('NOT_A_WORKER'), LoginFailure.notAWorker);
    expect(LoginFailure.forCode('ACCOUNT_INACTIVE'), LoginFailure.accountInactive);
    expect(LoginFailure.forCode('TOO_MANY_ATTEMPTS'), LoginFailure.tooManyAttempts);
  });

  test('an unknown code is our problem, not the worker\'s password', () {
    expect(LoginFailure.forCode('SOMETHING_NEW'), LoginFailure.serverProblem);
    expect(LoginFailure.forCode(null), LoginFailure.serverProblem);
  });

  test('no signal is never reported as a wrong password', () {
    expect(LoginFailure.of(const SocketException('no route')), LoginFailure.noConnection);
    expect(LoginFailure.of(TimeoutException('slow')), LoginFailure.noConnection);
    expect(LoginFailure.of(http.ClientException('Connection closed')), LoginFailure.noConnection);
    expect(LoginFailure.of(AuthRetryableFetchException(message: 'offline')), LoginFailure.noConnection);
  });

  test('every failure has English and Tagalog copy', () {
    for (final f in LoginFailure.values) {
      expect(f.english, isNotEmpty);
      expect(f.tagalog, isNotEmpty);
    }
    expect(LoginFailure.wrongCredentials.english, 'That email and password do not match.');
    expect(LoginFailure.wrongCredentials.tagalog, 'Hindi tugma ang email at password.');
  });
}
