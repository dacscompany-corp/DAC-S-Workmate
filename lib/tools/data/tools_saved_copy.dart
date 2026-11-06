import 'dart:convert';

import 'package:shared_preferences/shared_preferences.dart';

/// The three lists the Tools screen reads.
enum ToolsPart { mine, team, records }

/// One list as last read from the server, and when.
class SavedTools {
  const SavedTools({required this.rows, required this.at});
  final List<Map<String, dynamic>> rows;
  final DateTime at;
}

/// The last good answer of each list, for weak signal: shown, with its time,
/// when a refresh can't reach the server. One account's copy at a time — a
/// copy for another account replaces it, and [keepOnly] drops it — so on a
/// shared phone nobody sees another's tools. It holds 0111's answers as they
/// came: no peso, purchase, note or photo is in them. Nothing here is ever
/// sent; writes need signal.
class ToolsSavedCopy {
  ToolsSavedCopy(this._prefs);

  static const key = 'tools.saved.v1';
  final SharedPreferences _prefs;

  Map<String, dynamic>? _stored() {
    final raw = _prefs.getString(key);
    if (raw == null) return null;
    try {
      final v = jsonDecode(raw);
      return v is Map<String, dynamic> ? v : null;
    } on FormatException {
      return null;
    }
  }

  /// The [part] saved for [userId], or null.
  SavedTools? load(String userId, ToolsPart part) {
    final s = _stored();
    if (s == null || s['user'] != userId) return null;
    final p = (s['parts'] as Map<String, dynamic>?)?[part.name];
    if (p is! Map) return null;
    final at = DateTime.tryParse(p['at'] as String? ?? '');
    final rows = p['rows'];
    if (at == null || rows is! List) return null;
    return SavedTools(rows: [for (final r in rows) if (r is Map) Map<String, dynamic>.from(r)], at: at);
  }

  Future<void> save(String userId, ToolsPart part, List<Map<String, dynamic>> rows, DateTime at) async {
    final s = _stored();
    final parts = s != null && s['user'] == userId ? Map<String, dynamic>.from(s['parts'] as Map? ?? const {}) : <String, dynamic>{};
    parts[part.name] = {'at': at.toUtc().toIso8601String(), 'rows': rows};
    await _prefs.setString(key, jsonEncode({'user': userId, 'parts': parts}));
  }

  /// Keeps only [userId]'s copy ('' keeps none).
  Future<void> keepOnly(String userId) async {
    final s = _stored();
    if (s == null && _prefs.getString(key) == null) return;
    if (s != null && s['user'] == userId && userId.isNotEmpty) return;
    await _prefs.remove(key);
  }

  /// Drops one list of [userId]'s (tools switched off, or no longer leading).
  Future<void> drop(String userId, ToolsPart part) async {
    final s = _stored();
    if (s == null || s['user'] != userId) return;
    final parts = Map<String, dynamic>.from(s['parts'] as Map? ?? const {})..remove(part.name);
    await _prefs.setString(key, jsonEncode({'user': userId, 'parts': parts}));
  }
}
