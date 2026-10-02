import 'dart:async';
import 'dart:io';

import 'package:http/http.dart' as http;
import 'package:supabase_flutter/supabase_flutter.dart' show AuthException, AuthRetryableFetchException;

/// Supabase's own floor is 6; 8 is the project's, and the stricter wins.
const minPasswordLength = 8;

/// Every way changing a password can fail, local checks and server refusals
/// in ONE type, so the sheet renders one thing whichever side said no.
/// Ported from DACS Attendance domain/PasswordChange.kt.
enum PasswordChangeFailure {
  tooShort('Use at least 8 characters.', 'Kailangan ng 8 letra o numero pataas.'),
  mismatch('The two passwords do not match.', 'Hindi pareho ang dalawang password.'),

  /// The server refused it as identical to the current password.
  reused('That is your current password. Pick a different one.', 'Iyan din ang password mo ngayon. Pumili ng iba.'),

  /// The session died while the sheet was open; they must log in again.
  sessionExpired('Please log in again.', 'Mag-log in ulit.'),
  noConnection('No signal right now. Try again in a moment.', 'Walang signal ngayon. Subukan ulit mamaya.'),
  unexpected('Something went wrong. Try again.', 'May nasira. Subukan ulit.');

  const PasswordChangeFailure(this.english, this.tagalog);

  final String english;
  final String tagalog;

  /// Checked BEFORE the network: a too-short password should not cost a round
  /// trip on site signal, and the server never sees the confirmation box.
  static PasswordChangeFailure? validate(String password, String confirmation) {
    // Blank first: eight spaces passes a length check and nobody can retype it tomorrow.
    if (password.trim().isEmpty || password.length < minPasswordLength) return tooShort;
    if (password != confirmation) return mismatch;
    return null;
  }

  static PasswordChangeFailure of(Object error) {
    if (error is SocketException || error is TimeoutException || error is http.ClientException ||
        error is AuthRetryableFetchException) {
      return noConnection;
    }
    final text = (error is AuthException ? '${error.message} ${error.code ?? ''} ${error.statusCode ?? ''}' : error.toString())
        .toLowerCase();
    if (text.contains('should be different') || text.contains('same_password')) return reused;
    if (text.contains('at least') || text.contains('weak_password')) return tooShort;
    if (text.contains('401') || text.contains('jwt') || text.contains('session')) return sessionExpired;
    return unexpected;
  }
}
