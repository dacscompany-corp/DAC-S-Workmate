import 'dart:io';

import '../domain/history_failure.dart';
import '../domain/history_models.dart';
import 'history_api.dart';
import 'history_db.dart';
import 'history_remote.dart';

/// Results per page (the server caps at 50).
const historyPageSize = 30;

/// The offline copy's limits (spec 1b §4.4).
const maxSavedItems = 200;
const maxSavedPhotos = 200;
const maxSavedPhotoBytes = 20 * 1024 * 1024;
const maxSavedAge = Duration(days: 14);

/// Find Previous Item: the server first; this phone's bounded, per-worker
/// copy when there is no signal. Nothing here claims stock: it is history.
class HistoryRepository implements HistoryApi {
  HistoryRepository({
    required this.db,
    required this.remote,
    required this.currentWorkerId,
    required this.photoDir,
    DateTime Function()? now,
  }) : _now = now ?? DateTime.now;

  final HistoryDb db;
  final HistoryRemote remote;

  /// The worker the app let in, or '' — the scope of every read and write.
  final String Function() currentWorkerId;

  /// App-private folder for saved gallery photos (never the phone's gallery).
  final Future<Directory> Function() photoDir;
  final DateTime Function() _now;

  String _worker() {
    final w = currentWorkerId();
    if (w.isEmpty) throw StateError('AUTH_REQUIRED');
    return w;
  }

  bool _tooOld(DateTime savedAt) => _now().difference(savedAt) > maxSavedAge;

  static bool _offline(Object e) => HistoryFailure.of(e) == HistoryFailure.noConnection;

  // ── search ─────────────────────────────────────────────────────────────

  @override
  Future<HistoryPage> search(HistoryQuery q, {int offset = 0}) async {
    final w = _worker();
    try {
      return HistoryPage.fromJson(await remote.search(q, offset: offset, limit: historyPageSize));
    } catch (e) {
      if (!_offline(e)) rethrow;
      final saved = [for (final s in await db.items(w)) if (!_tooOld(s.savedAt)) s];
      if (saved.isEmpty) {
        // Check if all saved items exist but are too old.
        final allSaved = await db.items(w);
        if (allSaved.isNotEmpty) throw const HistoryUnavailable(HistoryFailure.savedTooOld);
        throw const HistoryUnavailable(HistoryFailure.noConnection);
      }
      // Page 1 offline shows everything (hasMore false), so a next page asked
      // for after the signal dropped is "no connection".
      if (offset > 0) throw const HistoryUnavailable(HistoryFailure.noConnection);
      final hits = saved.where((s) => _matches(s.item, q)).toList()
        ..sort((a, b) => a.item.name.toLowerCase().compareTo(b.item.name.toLowerCase()));
      final oldest = saved.map((s) => s.savedAt).reduce((a, b) => a.isBefore(b) ? a : b);
      return HistoryPage(items: [for (final s in hits) s.item.toCard()], hasMore: false, savedAt: oldest);
    }
  }

  /// The server's search rules, on the saved copy: name, size, brand,
  /// category or another name; kind; category; project; date range.
  static bool _matches(HistoryItem i, HistoryQuery q) {
    final t = q.text.trim().toLowerCase();
    if (t.isNotEmpty && ![i.name, i.spec, i.brand, i.category, ...i.aliases].any((s) => s.toLowerCase().contains(t))) return false;
    if (q.kind != null && i.kind != q.kind) return false;
    if (q.category != null && i.category.toLowerCase() != q.category!.toLowerCase()) return false;
    bool inRange(HistoryEntry e) {
      if (q.projectId != null && e.projectId != q.projectId) return false;
      if (q.from == null && q.to == null) return true;
      final d = e.date;
      if (d == null) return false;
      return (q.from == null || d.compareTo(q.from!) >= 0) && (q.to == null || d.compareTo(q.to!) <= 0);
    }

    return (q.projectId == null && q.from == null && q.to == null) || i.entries.any(inRange);
  }

  // ── one item ───────────────────────────────────────────────────────────

  @override
  Future<HistoryItemView> item(String itemId) async {
    final w = _worker();
    try {
      final item = HistoryItem.fromJson(await remote.item(itemId));
      if (item == null) throw StateError('unknown item kind');
      final now = _now();
      await db.putItem(w, item, savedAt: now, viewedAt: now);
      await _keepItemLimit(w);
      return HistoryItemView(item: item);
    } catch (e) {
      final f = HistoryFailure.of(e);
      // No longer visible to this worker: the saved copy goes too.
      if (f == HistoryFailure.notAvailable) await _forgetItem(w, itemId);
      if (f != HistoryFailure.noConnection) rethrow;
      final saved = await db.item(w, itemId);
      if (saved == null) throw const HistoryUnavailable(HistoryFailure.noConnection);
      if (_tooOld(saved.savedAt)) throw const HistoryUnavailable(HistoryFailure.savedTooOld);
      await db.touchItem(w, itemId, _now());
      return HistoryItemView(item: saved.item, savedAt: saved.savedAt);
    }
  }

  // ── cleanup ────────────────────────────────────────────────────────────

  @override
  Future<void> refreshSaved() async {
    final w = _worker();
    final saved = await db.items(w);
    final photos = await db.photos(w);
    // Union of saved item ids and saved photo item ids (de-duplicated, skip empty itemIds).
    final itemIds = <String>{
      for (final s in saved) s.item.id,
      for (final p in photos) if (p.itemId.isNotEmpty) p.itemId,
    };
    if (itemIds.isEmpty) return;
    final List<Map<String, dynamic>> answer;
    try {
      answer = await remote.visible(itemIds.toList());
    } catch (e) {
      if (_offline(e)) return;
      rethrow;
    }
    final byItem = {for (final v in answer) v['item_id'] as String: v};
    final savedByItemId = {for (final s in saved) s.item.id: s};
    for (final s in saved) {
      // Re-read the item to detect if it was refreshed while we waited on the network.
      final now = await db.item(w, s.item.id);
      if (now == null || now.savedAt != s.savedAt) continue; // Fresh copy replaced it; fresh results win.
      final v = byItem[s.item.id];
      if (v == null || _tooOld(s.savedAt)) {
        await _forgetItem(w, s.item.id);
        continue;
      }
      final keys = {for (final k in (v['entries'] as List<dynamic>? ?? const [])) k as String};
      final photoIds = {for (final p in (v['photo_ids'] as List<dynamic>? ?? const [])) p as String};
      final kept = s.item.copyWith(
        entries: [for (final e in s.item.entries) if (keys.contains(e.key)) e],
        photos: [for (final p in s.item.photos) if (photoIds.contains(p.id)) p],
      );
      if (kept.entries.length != s.item.entries.length || kept.photos.length != s.item.photos.length) {
        await db.putItem(w, kept, savedAt: s.savedAt, viewedAt: s.viewedAt);
      }
      // A photo file of this item that is no longer approved goes.
      final keepPaths = {for (final p in kept.photos) p.path};
      for (final p in photos) {
        if (p.itemId == s.item.id && !keepPaths.contains(p.path)) await _deletePhoto(w, p);
      }
    }
    // Clean cached covers: photos whose item has no saved_item row.
    for (final p in photos) {
      if (!savedByItemId.containsKey(p.itemId)) {
        final v = byItem[p.itemId];
        if (v == null) {
          await _deletePhoto(w, p);
        }
        // Item still visible: keep the cached cover (will be evicted by limits or sign-out).
      }
    }
  }

  // ── photos ─────────────────────────────────────────────────────────────

  @override
  Future<File?> photo(String path) async {
    final w = _worker();
    final saved = await db.photo(w, path);
    if (saved != null) {
      final f = File(saved.file);
      if (await f.exists()) {
        await db.touchPhoto(w, path, _now());
        return f;
      }
      await db.deletePhoto(w, path);
    }
    try {
      final bytes = await remote.download(path);
      final dir = Directory('${(await photoDir()).path}${Platform.pathSeparator}$w');
      await dir.create(recursive: true);
      final file = File('${dir.path}${Platform.pathSeparator}${path.replaceAll('/', '_')}');
      await file.writeAsBytes(bytes, flush: true);
      // <company>/<item>/<uuid>.jpg — the item is the second segment.
      final parts = path.split('/');
      await db.putPhoto(w, path: path, itemId: parts.length > 1 ? parts[1] : '', file: file.path, bytes: bytes.length, at: _now());
      await _keepPhotoLimit(w);
      return file;
    } catch (_) {
      return null;
    }
  }

  // ── limits and forgetting ──────────────────────────────────────────────

  /// Least recently opened items go first (with their photos).
  Future<void> _keepItemLimit(String w) async {
    final items = await db.items(w);
    for (var i = 0; i < items.length - maxSavedItems; i++) {
      await _forgetItem(w, items[i].item.id);
    }
  }

  /// Least recently shown photos go first, until both limits hold.
  Future<void> _keepPhotoLimit(String w) async {
    final photos = await db.photos(w);
    var count = photos.length;
    var bytes = photos.fold<int>(0, (sum, p) => sum + p.bytes);
    for (final p in photos) {
      if (count <= maxSavedPhotos && bytes <= maxSavedPhotoBytes) break;
      await _deletePhoto(w, p);
      count--;
      bytes -= p.bytes;
    }
  }

  Future<void> _forgetItem(String w, String itemId) async {
    await db.deleteItem(w, itemId);
    for (final p in await db.photos(w)) {
      if (p.itemId == itemId) await _deletePhoto(w, p);
    }
  }

  Future<void> _deletePhoto(String w, SavedPhoto p) async {
    await db.deletePhoto(w, p.path);
    try {
      await File(p.file).delete();
    } catch (_) {
      // Already gone.
    }
  }

  @override
  Future<void> keepOnly(String workerId) async {
    for (final w in await db.workerIds()) {
      if (w != workerId) await _forget(w);
    }
    // Photo files the database never recorded (a download cut short).
    try {
      final root = await photoDir();
      if (await root.exists()) {
        await for (final e in root.list()) {
          if (e is! Directory) continue;
          final name = e.uri.pathSegments.where((p) => p.isNotEmpty).last;
          if (name == workerId) continue;
          try {
            await e.delete(recursive: true);
          } catch (_) {
            // Already gone.
          }
        }
      }
    } catch (_) {
      // Nothing to sweep.
    }
  }

  Future<void> _forget(String workerId) async {
    for (final f in await db.forgetWorker(workerId)) {
      try {
        await File(f).delete();
      } catch (_) {
        // Already gone.
      }
    }
  }
}
