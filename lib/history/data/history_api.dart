import 'dart:io';

import '../domain/history_models.dart';

/// One item's page, fresh ([savedAt] null) or this phone's saved copy.
class HistoryItemView {
  const HistoryItemView({required this.item, this.savedAt});
  final HistoryItem item;
  final DateTime? savedAt;

  bool get fromSaved => savedAt != null;
}

/// What the Find Previous Item screens need. An interface so screens test
/// with a fake instead of a database and a server.
abstract interface class HistoryApi {
  /// One page of items (30). With no signal: the items saved on this phone
  /// that match, all at once, marked with [HistoryPage.savedAt].
  Future<HistoryPage> search(HistoryQuery q, {int offset = 0});

  /// One item. With no signal: the saved copy, if it is 14 days old or newer.
  Future<HistoryItemView> item(String itemId);

  /// Deletes every saved item, entry and photo the worker may no longer see
  /// (spec §4.4: per entry, not just per item). A cached cover whose item is still visible is kept.
  /// Quietly does nothing offline.
  Future<void> refreshSaved();

  /// The photo as a file on this phone (downloaded and kept on first use),
  /// or null when it cannot be shown now.
  Future<File?> photo(String path);

  /// Deletes everything saved for every worker but [workerId]; '' deletes
  /// it all (spec §4.4: wiped on sign-out or account switch).
  Future<void> keepOnly(String workerId);
}
