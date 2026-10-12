import 'dart:async';
import 'dart:io';

import 'package:http/http.dart' as http;
import 'package:supabase_flutter/supabase_flutter.dart' show AuthRetryableFetchException;

/// Thrown by the history repository when the phone has no fresh copy to show.
class HistoryUnavailable implements Exception {
  const HistoryUnavailable(this.failure);
  final HistoryFailure failure;

  @override
  String toString() => 'HistoryUnavailable(${failure.name})';
}

/// Every way Find Previous Item can fail. The 0090 RPCs raise stable codes;
/// anything else is [unexpected], never a guess.
enum HistoryFailure {
  /// HISTORY_NOT_AVAILABLE: no entry of this item is visible (switched off, retired).
  notAvailable,

  /// No signal and nothing saved on this phone (or saved more than 14 days ago).
  noConnection,

  /// Offline, and this phone's copy is older than the 14-day limit.
  savedTooOld,
  sessionExpired,
  notARequester,
  appUpdateRequired,
  unexpected;

  static const _byCode = <String, HistoryFailure>{
    'HISTORY_NOT_AVAILABLE': notAvailable,
    'NOT_A_REQUESTER': notARequester,
    'APP_UPDATE_REQUIRED': appUpdateRequired,
    'AUTH_REQUIRED': sessionExpired,
  };

  static HistoryFailure of(Object error) {
    if (error is HistoryUnavailable) return error.failure;
    if (error is IOException ||
        error is TimeoutException ||
        error is http.ClientException ||
        error is AuthRetryableFetchException) {
      return noConnection;
    }
    final text = error.toString();
    for (final entry in _byCode.entries) {
      if (text.contains(entry.key)) return entry.value;
    }
    return unexpected;
  }
}
