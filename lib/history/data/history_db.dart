import 'dart:convert';

import 'package:sqflite/sqflite.dart';

import '../domain/history_models.dart';

/// One saved item: what the server last sent, when, and when it was last opened.
typedef SavedItem = ({HistoryItem item, DateTime savedAt, DateTime viewedAt});

/// One saved photo file.
typedef SavedPhoto = ({String path, String itemId, String file, int bytes, DateTime viewedAt});

/// The offline copy of Find Previous Item (spec 1b §4.4): items the worker
/// opened and their photo files — every row scoped by worker, because site
/// phones are shared. Its own file, apart from the requests and attendance
/// databases, so none can break another.
class HistoryDb {
  HistoryDb._(this._db);

  final Database _db;

  static Future<HistoryDb> open(DatabaseFactory factory, String path, {bool singleInstance = true}) async {
    final db = await factory.openDatabase(
      path,
      options: OpenDatabaseOptions(version: 1, onCreate: _create, singleInstance: singleInstance),
    );
    return HistoryDb._(db);
  }

  static Future<void> _create(Database db, int version) async {
    await db.execute('''
      create table saved_item (
        worker_id text not null,
        item_id text not null,
        body text not null,
        saved_at integer not null,
        viewed_at integer not null,
        primary key (worker_id, item_id)
      )''');
    await db.execute('''
      create table saved_photo (
        worker_id text not null,
        path text not null,
        item_id text not null,
        file text not null,
        bytes integer not null,
        viewed_at integer not null,
        primary key (worker_id, path)
      )''');
  }

  Future<void> close() => _db.close();

  static DateTime _t(Object? ms) => DateTime.fromMillisecondsSinceEpoch(ms! as int, isUtc: true);

  // ── items ──────────────────────────────────────────────────────────────

  Future<void> putItem(String workerId, HistoryItem item, {required DateTime savedAt, required DateTime viewedAt}) => _db.insert(
        'saved_item',
        {
          'worker_id': workerId,
          'item_id': item.id,
          'body': jsonEncode(item.toJson()),
          'saved_at': savedAt.millisecondsSinceEpoch,
          'viewed_at': viewedAt.millisecondsSinceEpoch,
        },
        conflictAlgorithm: ConflictAlgorithm.replace,
      );

  SavedItem? _item(Map<String, Object?> row) {
    final item = HistoryItem.fromJson(Map<String, dynamic>.from(jsonDecode(row['body']! as String) as Map));
    if (item == null) return null;
    return (item: item, savedAt: _t(row['saved_at']), viewedAt: _t(row['viewed_at']));
  }

  Future<SavedItem?> item(String workerId, String itemId) async {
    final rows = await _db.query('saved_item', where: 'worker_id = ? and item_id = ?', whereArgs: [workerId, itemId], limit: 1);
    return rows.isEmpty ? null : _item(rows.first);
  }

  /// Least recently opened first.
  Future<List<SavedItem>> items(String workerId) async => [
        for (final r in await _db.query('saved_item', where: 'worker_id = ?', whereArgs: [workerId], orderBy: 'viewed_at asc'))
          ?_item(r),
      ];

  Future<void> touchItem(String workerId, String itemId, DateTime at) => _db.update(
      'saved_item', {'viewed_at': at.millisecondsSinceEpoch},
      where: 'worker_id = ? and item_id = ?', whereArgs: [workerId, itemId]);

  Future<void> deleteItem(String workerId, String itemId) =>
      _db.delete('saved_item', where: 'worker_id = ? and item_id = ?', whereArgs: [workerId, itemId]);

  // ── photos ─────────────────────────────────────────────────────────────

  Future<void> putPhoto(String workerId, {required String path, required String itemId, required String file, required int bytes, required DateTime at}) =>
      _db.insert(
        'saved_photo',
        {'worker_id': workerId, 'path': path, 'item_id': itemId, 'file': file, 'bytes': bytes, 'viewed_at': at.millisecondsSinceEpoch},
        conflictAlgorithm: ConflictAlgorithm.replace,
      );

  SavedPhoto _photo(Map<String, Object?> r) => (
        path: r['path']! as String,
        itemId: r['item_id']! as String,
        file: r['file']! as String,
        bytes: r['bytes']! as int,
        viewedAt: _t(r['viewed_at']),
      );

  Future<SavedPhoto?> photo(String workerId, String path) async {
    final rows = await _db.query('saved_photo', where: 'worker_id = ? and path = ?', whereArgs: [workerId, path], limit: 1);
    return rows.isEmpty ? null : _photo(rows.first);
  }

  /// Least recently shown first.
  Future<List<SavedPhoto>> photos(String workerId) async => [
        for (final r in await _db.query('saved_photo', where: 'worker_id = ?', whereArgs: [workerId], orderBy: 'viewed_at asc')) _photo(r),
      ];

  Future<void> touchPhoto(String workerId, String path, DateTime at) => _db.update(
      'saved_photo', {'viewed_at': at.millisecondsSinceEpoch},
      where: 'worker_id = ? and path = ?', whereArgs: [workerId, path]);

  Future<void> deletePhoto(String workerId, String path) =>
      _db.delete('saved_photo', where: 'worker_id = ? and path = ?', whereArgs: [workerId, path]);

  // ── a worker leaves ────────────────────────────────────────────────────

  /// Every worker with something saved on this phone.
  Future<List<String>> workerIds() async => [
        for (final r in await _db.rawQuery('SELECT worker_id FROM saved_item UNION SELECT worker_id FROM saved_photo'))
          r['worker_id']! as String,
      ];

  /// Deletes everything saved for [workerId]; returns the photo files to delete.
  Future<List<String>> forgetWorker(String workerId) => _db.transaction((txn) async {
        final files = [
          for (final r in await txn.query('saved_photo', columns: ['file'], where: 'worker_id = ?', whereArgs: [workerId])) r['file']! as String,
        ];
        await txn.delete('saved_photo', where: 'worker_id = ?', whereArgs: [workerId]);
        await txn.delete('saved_item', where: 'worker_id = ?', whereArgs: [workerId]);
        return files;
      });
}

/// The database file on the phone.
Future<HistoryDb> openDeviceHistoryDb() async => HistoryDb.open(databaseFactory, '${await getDatabasesPath()}/workmate_history.db');
