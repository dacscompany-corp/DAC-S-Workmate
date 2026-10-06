import 'dart:async';
import 'dart:io';

import 'package:http/http.dart' as http;
import 'package:supabase_flutter/supabase_flutter.dart' show AuthRetryableFetchException;

/// Every way a request operation can be refused. The 0085 RPCs raise stable
/// codes; anything else is [unexpected], never a guess.
enum RequestFailure {
  destinationClosed,
  notInTeam,
  notTeamLeader,
  badMember,
  badCatalogItem,
  incomplete,
  badQuantity,
  urgentNeedsReason,
  lineClosed,
  notYours,
  notARequester,
  photoNotUploaded,
  appUpdateRequired,
  sessionExpired,
  noConnection,
  unexpected;

  // No code is a substring of another, so the first match is the only match.
  static const _byCode = <String, RequestFailure>{
    'DESTINATION_CLOSED': destinationClosed,
    'NOT_IN_TEAM': notInTeam,
    'NOT_TEAM_LEADER': notTeamLeader,
    'BAD_MEMBER': badMember,
    'BAD_CATALOG_ITEM': badCatalogItem,
    'BAD_LINE': incomplete,
    'NO_LINES': incomplete,
    'TOO_MANY_LINES': incomplete,
    'BAD_QUANTITY': badQuantity,
    'URGENT_NEEDS_REASON': urgentNeedsReason,
    'LINE_CLOSED': lineClosed,
    'NOT_YOUR_LINE': notYours,
    'NOT_YOUR_REQUEST': notYours,
    'NOT_A_REQUESTER': notARequester,
    'PHOTO_NOT_UPLOADED': photoNotUploaded,
    'APP_UPDATE_REQUIRED': appUpdateRequired,
    'AUTH_REQUIRED': sessionExpired,
  };

  static RequestFailure of(Object error) {
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

  /// A stored failure name back to the failure ('PHOTO_MISSING' and other
  /// local codes read as [unexpected]).
  static RequestFailure fromStored(String? name) => values.where((f) => f.name == name).firstOrNull ?? unexpected;

  /// Worth sending again later: the connection, the session or the moment —
  /// never the request's own content, which would be refused again.
  bool get retryable => switch (this) {
        noConnection || sessionExpired || appUpdateRequired || photoNotUploaded || unexpected => true,
        _ => false,
      };

  /// Counts toward [maxUnexpectedAttempts]. A photo the server never sees
  /// would otherwise hold the worker's whole queue forever. Waiting — for
  /// signal, a session or an app update — never counts.
  bool get countsTowardCap => this == unexpected || this == photoNotUploaded;
}

/// A failure that [RequestFailure.countsTowardCap] this many times in a row is
/// treated as permanent, so one bad operation cannot block the queue forever.
const maxUnexpectedAttempts = 10;
