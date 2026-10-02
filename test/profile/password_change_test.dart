import 'dart:async';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:workmate/profile/password_change.dart';

/// Ported from PasswordChangeTest.kt. The worker doing this stands on a site
/// with one bar of signal: everything decidable without the network is decided first.
void main() {
  test('a good password and a matching confirmation passes', () {
    expect(PasswordChangeFailure.validate('bagongpass1', 'bagongpass1'), isNull);
  });

  test('too short is caught before the network', () {
    expect(PasswordChangeFailure.validate('abc123', 'abc123'), PasswordChangeFailure.tooShort);
  });

  test('eight spaces is not a password', () {
    expect(PasswordChangeFailure.validate('        ', '        '), PasswordChangeFailure.tooShort);
  });

  test('a mistyped confirmation is caught locally', () {
    expect(PasswordChangeFailure.validate('bagongpass1', 'bagongpass2'), PasswordChangeFailure.mismatch);
  });

  test('length is reported before the mismatch', () {
    expect(PasswordChangeFailure.validate('abc', 'abcd'), PasswordChangeFailure.tooShort);
  });

  test('no signal is not a rejected password', () {
    expect(PasswordChangeFailure.of(const SocketException('Unable to resolve host')), PasswordChangeFailure.noConnection);
    expect(PasswordChangeFailure.of(TimeoutException('slow')), PasswordChangeFailure.noConnection);
    expect(PasswordChangeFailure.of(AuthRetryableFetchException()), PasswordChangeFailure.noConnection);
  });

  test('the server refusing a reused password says so', () {
    expect(PasswordChangeFailure.of(Exception('New password should be different from the old password.')),
        PasswordChangeFailure.reused);
    expect(PasswordChangeFailure.of(const AuthException('nope', statusCode: '422', code: 'same_password')),
        PasswordChangeFailure.reused);
  });

  test('the server calling it weak is too short', () {
    expect(PasswordChangeFailure.of(const AuthException('Password should be at least 6 characters.', code: 'weak_password')),
        PasswordChangeFailure.tooShort);
  });

  test('an expired session is not a password problem', () {
    expect(PasswordChangeFailure.of(Exception('401: invalid JWT')), PasswordChangeFailure.sessionExpired);
    expect(PasswordChangeFailure.of(StateError('No session to change the password with')), PasswordChangeFailure.sessionExpired);
  });

  test('an unrecognised refusal never guesses', () {
    expect(PasswordChangeFailure.of(Exception('boom')), PasswordChangeFailure.unexpected);
  });

  test('every failure speaks English and Tagalog', () {
    for (final f in PasswordChangeFailure.values) {
      expect(f.english, isNotEmpty);
      expect(f.tagalog, isNotEmpty);
    }
    expect(PasswordChangeFailure.reused.tagalog, 'Iyan din ang password mo ngayon. Pumili ng iba.');
  });
}
