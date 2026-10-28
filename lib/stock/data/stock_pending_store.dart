import 'dart:convert';

import 'package:shared_preferences/shared_preferences.dart';

import '../domain/stock_submission.dart';

/// A saved stock submission the phone can no longer read in full (R104):
/// kept exactly as stored, never dropped by a save. If its account and
/// operation id can still be read, the server can settle it by Check or
/// Cancel — its payload is never rebuilt. Otherwise it needs recovery.
class UnreadableSubmission {
  const UnreadableSubmission({required this.raw, this.opId, this.userId});

  /// The stored entry as it is (JSON text).
  final String raw;

  /// Read only if it is a well-formed id.
  final String? opId;
  final String? userId;

  /// Check and Cancel need only these two.
  bool get settleable => opId != null && userId != null;

  static final _uuid = RegExp(r'^[0-9a-fA-F]{8}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{12}$');

  static UnreadableSubmission of(Object? entry) {
    String? id(Object? v) => v is String && _uuid.hasMatch(v) ? v : null;
    final m = entry is Map ? entry : const {};
    return UnreadableSubmission(raw: jsonEncode(entry), opId: id(m['op_id']), userId: id(m['user_id']));
  }
}

/// What is stored on the phone: the submissions that read in full, the ones
/// that do not, and whether the stored text as a whole cannot be read.
class StockPendingLoad {
  const StockPendingLoad({this.readable = const [], this.unreadable = const [], this.damaged = false});
  final List<StockSubmission> readable;
  final List<UnreadableSubmission> unreadable;

  /// The stored text is not a list at all: nothing can be read or saved.
  final bool damaged;
}

/// Where unresolved stock submissions wait on the phone (R101, R104): they
/// survive closing a form, closing the app and a restart. Nothing here ever
/// sends. Unreadable data is never treated as empty and never overwritten.
abstract class StockPendingStore {
  Future<StockPendingLoad> load();

  /// Stores [readable] (every account's) — keeping every unreadable entry as
  /// it is now stored. Refuses (STOCK_STORE_DAMAGED) if the stored text
  /// cannot be read at all: it is never overwritten.
  Future<void> save(List<StockSubmission> readable);

  /// Removes the unreadable entries of this account and operation id — only
  /// after the server settled that id (recorded, or cancelled for good).
  Future<void> dropUnreadable(String userId, String opId);
}

/// The phone's settings file; every account's unresolved submissions in one
/// list (each carries its account, R103). Quantities and ids only — no peso.
class PrefsStockPendingStore implements StockPendingStore {
  PrefsStockPendingStore(this._prefs);

  static const key = 'stock.unresolved.v1';
  final SharedPreferences _prefs;

  /// The stored list, entry by entry (null: nothing stored; throws if damaged).
  List<Object?>? _entries() {
    final raw = _prefs.getString(key);
    if (raw == null) return null;
    final Object? list;
    try {
      list = jsonDecode(raw);
    } on FormatException {
      throw StateError('STOCK_STORE_DAMAGED');
    }
    if (list is! List) throw StateError('STOCK_STORE_DAMAGED');
    return list;
  }

  static StockSubmission? _read(Object? entry) {
    if (entry is! Map) return null;
    try {
      return StockSubmission.fromJson(Map<String, dynamic>.from(entry));
    } catch (_) {
      return null;
    }
  }

  @override
  Future<StockPendingLoad> load() async {
    final List<Object?>? entries;
    try {
      entries = _entries();
    } on StateError {
      return const StockPendingLoad(damaged: true);
    }
    final readable = <StockSubmission>[];
    final unreadable = <UnreadableSubmission>[];
    for (final e in entries ?? const []) {
      final s = _read(e);
      if (s != null) {
        readable.add(s);
      } else {
        unreadable.add(UnreadableSubmission.of(e));
      }
    }
    return StockPendingLoad(readable: readable, unreadable: unreadable);
  }

  @override
  Future<void> save(List<StockSubmission> readable) async {
    final kept = [for (final e in _entries() ?? const []) if (_read(e) == null) e];
    await _write([...kept, for (final s in readable) s.toJson()]);
  }

  @override
  Future<void> dropUnreadable(String userId, String opId) async {
    final entries = _entries() ?? const [];
    await _write([
      for (final e in entries)
        if (_read(e) != null || !(UnreadableSubmission.of(e).opId == opId && UnreadableSubmission.of(e).userId == userId)) e,
    ]);
  }

  Future<void> _write(List<Object?> entries) async {
    final ok = await _prefs.setString(key, jsonEncode(entries));
    if (!ok) throw StateError('STOCK_SAVE_FAILED');
  }
}
