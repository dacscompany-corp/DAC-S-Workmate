import 'dart:async';
import 'dart:io';

import 'package:http/http.dart' as http;
import 'package:supabase_flutter/supabase_flutter.dart' show AuthRetryableFetchException;

/// Every way a My Work operation can be refused. The 0093 RPCs raise stable
/// codes; anything else is [unexpected], never a guess.
enum WpFailure {
  /// No longer on the task, or the task was cancelled / taken back as a draft.
  notAssigned,
  notResponsible,

  /// The task moved on meanwhile (started, reported, approved…).
  badState,
  taskBlocked,

  /// The office changed the task after this phone read it: read the new
  /// version first (0093 wp_start_work).
  notAcknowledged,
  noteRequired,
  badRequest,
  ownWork,
  notLeader,
  badDestination,
  titleRequired,
  photoNotUploaded,
  notARequester,
  appUpdateRequired,
  sessionExpired,
  noConnection,
  unexpected;

  // No code is a substring of another, so the first match is the only match.
  static const _byCode = <String, WpFailure>{
    'NOT_ASSIGNED': notAssigned,
    'NOT_RESPONSIBLE': notResponsible,
    'BAD_STATE': badState,
    'TASK_BLOCKED': taskBlocked,
    'NOT_ACKNOWLEDGED': notAcknowledged,
    'NOTE_REQUIRED': noteRequired,
    'BAD_REQUEST': badRequest,
    'OWN_WORK': ownWork,
    'NOT_LEADER': notLeader,
    'BAD_DESTINATION': badDestination,
    'TITLE_REQUIRED': titleRequired,
    'PHOTO_NOT_UPLOADED': photoNotUploaded,
    'NOT_A_REQUESTER': notARequester,
    'APP_UPDATE_REQUIRED': appUpdateRequired,
    'AUTH_REQUIRED': sessionExpired,
  };

  static WpFailure of(Object error) {
    // A file problem is not a missing signal: [unexpected] counts toward
    // [maxWpAttempts], so one unreadable photo is given up after 10 tries
    // instead of blocking the worker's queue.
    if (error is FileSystemException) return unexpected;
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

  /// A stored failure name back to the failure (local codes such as
  /// 'PHOTO_MISSING' read as [unexpected]).
  static WpFailure fromStored(String? name) => values.where((f) => f.name == name).firstOrNull ?? unexpected;

  /// Worth sending again later: the connection, the session or the moment —
  /// never the operation's own content, which would be refused again.
  bool get retryable => switch (this) {
        noConnection || sessionExpired || appUpdateRequired || photoNotUploaded || unexpected => true,
        _ => false,
      };

  /// Counts toward [maxWpAttempts]: one bad operation must not hold the
  /// worker's queue forever. Waiting for signal, a session or an update never counts.
  bool get countsTowardCap => this == unexpected || this == photoNotUploaded;
}

/// A failure that [WpFailure.countsTowardCap] this many times in a row is
/// treated as permanent.
const maxWpAttempts = 10;
