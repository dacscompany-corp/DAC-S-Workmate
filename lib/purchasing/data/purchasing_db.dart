import 'dart:convert';

import 'package:sqflite/sqflite.dart';

import '../domain/pur_op.dart';
import '../domain/purchase_draft.dart';

/// Purchases being recorded, the send-once queue and the last answers read
/// (for use with no signal) — every row scoped by account. Its own file, apart
/// from attendance, requests and My Work, so none can break the others.
class PurchasingDb {
  PurchasingDb._(this._db);

  final Database _db;

  static Future<PurchasingDb> open(DatabaseFactory factory, String path, {bool singleInstance = true}) async {
    final db = await factory.openDatabase(
      path,
      options: OpenDatabaseOptions(version: 1, onCreate: _create, singleInstance: singleInstance),
    );
    return PurchasingDb._(db);
  }

  static Future<void> _create(Database db, int version) async {
    await db.execute('''
      create table pur_draft (
        id text primary key,
        user_id text not null,
        body text not null,
        queued integer not null default 0,
        created_at integer not null,
        updated_at integer not null
      )''');
    await db.execute('''
      create table pur_op (
        op_id text primary key,
        user_id text not null,
        kind text not null,
        draft_id text,
        body text not null,
        seq integer not null,
        attempts integer not null default 0,
        last_error text,
        failed_permanently integer not null default 0,
        created_at integer not null
      )''');
    await db.execute('''
      create table pur_cache (
        user_id text not null,
        name text not null,
        body text not null,
        fetched_at integer not null,
        primary key (user_id, name)
      )''');
  }

  Future<void> close() => _db.close();

  PurchaseDraft _draft(Map<String, Object?> row) => PurchaseDraft.fromJson(Map<String, dynamic>.from(jsonDecode(row['body']! as String) as Map));

  // ── drafts ─────────────────────────────────────────────────────────────

  /// Never rewrites a queued draft: once handed to the queue it changes only
  /// through [unqueueDraft].
  Future<void> saveDraft(String userId, PurchaseDraft d, DateTime now) => _db.transaction((txn) async {
        final queued = await txn.query('pur_draft', columns: ['id'], where: 'id = ? and queued = 1', whereArgs: [d.id], limit: 1);
        if (queued.isNotEmpty) return;
        await txn.insert(
          'pur_draft',
          {
            'id': d.id,
            'user_id': userId,
            'body': jsonEncode(d.toJson()),
            'queued': 0,
            'created_at': d.createdAt.millisecondsSinceEpoch,
            'updated_at': now.millisecondsSinceEpoch,
          },
          conflictAlgorithm: ConflictAlgorithm.replace,
        );
      });

  /// [queued] false = still being edited; true = handed to the queue.
  Future<List<PurchaseDraft>> drafts(String userId, {required bool queued}) async => (await _db.query('pur_draft',
          where: 'user_id = ? and queued = ?', whereArgs: [userId, queued ? 1 : 0], orderBy: 'created_at desc'))
      .map(_draft)
      .toList();

  Future<PurchaseDraft?> draft(String userId, String id) async {
    final rows = await _db.query('pur_draft', where: 'user_id = ? and id = ?', whereArgs: [userId, id], limit: 1);
    return rows.isEmpty ? null : _draft(rows.first);
  }

  /// Deletes an UNSENT draft and returns it (so its photos can go too); null
  /// when it is queued or not this account's.
  Future<PurchaseDraft?> deleteUnsentDraft(String userId, String id) => _db.transaction((txn) async {
        final rows = await txn.query('pur_draft', where: 'user_id = ? and id = ? and queued = 0', whereArgs: [userId, id], limit: 1);
        if (rows.isEmpty) return null;
        await txn.delete('pur_draft', where: 'id = ?', whereArgs: [id]);
        return _draft(rows.first);
      });

  /// One transaction: the draft is marked queued AND its op exists, or
  /// neither. False (nothing written) when it is already queued: a second
  /// Send must never record a second purchase.
  Future<bool> queueDraft(String userId, PurchaseDraft d, PurOp op, DateTime now) => _db.transaction((txn) async {
        final already = await txn.query('pur_draft', columns: ['id'], where: 'id = ? and queued = 1', whereArgs: [d.id], limit: 1);
        if (already.isNotEmpty) return false;
        await txn.insert(
          'pur_draft',
          {
            'id': d.id,
            'user_id': userId,
            'body': jsonEncode(d.toJson()),
            'queued': 1,
            'created_at': d.createdAt.millisecondsSinceEpoch,
            'updated_at': now.millisecondsSinceEpoch,
          },
          conflictAlgorithm: ConflictAlgorithm.replace,
        );
        final top = (await txn.rawQuery('select coalesce(max(seq), 0) as s from pur_op')).first['s']! as int;
        await txn.insert('pur_op', {...op.toMap(), 'seq': top + 1});
        return true;
      });

  /// A refused purchase back to editing: its op goes, it is no longer
  /// queued. Refused (false) while its op could still be sent.
  Future<bool> unqueueDraft(String userId, String draftId) => _db.transaction((txn) async {
        final live = await txn.query('pur_op',
            where: 'user_id = ? and draft_id = ? and failed_permanently = 0', whereArgs: [userId, draftId], limit: 1);
        if (live.isNotEmpty) return false;
        final queued = await txn.query('pur_draft', columns: ['id'], where: 'user_id = ? and id = ? and queued = 1', whereArgs: [userId, draftId]);
        if (queued.isEmpty) return false;
        await txn.delete('pur_op', where: 'user_id = ? and draft_id = ?', whereArgs: [userId, draftId]);
        await txn.update('pur_draft', {'queued': 0}, where: 'user_id = ? and id = ?', whereArgs: [userId, draftId]);
        return true;
      });

  /// A refused purchase the buyer chose to throw away: its op and draft go
  /// together; returns the draft (for its photos). Null while it could still be sent.
  Future<PurchaseDraft?> discardRefused(String userId, String draftId) => _db.transaction((txn) async {
        final live = await txn.query('pur_op',
            where: 'user_id = ? and draft_id = ? and failed_permanently = 0', whereArgs: [userId, draftId], limit: 1);
        if (live.isNotEmpty) return null;
        final rows = await txn.query('pur_draft', where: 'user_id = ? and id = ?', whereArgs: [userId, draftId], limit: 1);
        if (rows.isEmpty) return null;
        await txn.delete('pur_op', where: 'user_id = ? and draft_id = ?', whereArgs: [userId, draftId]);
        await txn.delete('pur_draft', where: 'id = ?', whereArgs: [draftId]);
        return _draft(rows.first);
      });

  /// Purchases on the phone not yet recorded: being edited, waiting to send
  /// or needing attention — for the Buying is turned off screen.
  Future<int> unsentCount(String userId) async =>
      Sqflite.firstIntValue(await _db.rawQuery('select count(*) from pur_draft where user_id = ?', [userId])) ?? 0;

  // ── the queue ──────────────────────────────────────────────────────────

  /// This account's ops that may still be sent, in queue order.
  Future<List<PurOp>> sendable(String userId) async => (await _db.query('pur_op',
          where: 'user_id = ? and failed_permanently = 0', whereArgs: [userId], orderBy: 'seq asc'))
      .map(PurOp.fromMap)
      .toList();

  /// Every op of this account, refused ones included, in queue order.
  Future<List<PurOp>> ops(String userId) async =>
      (await _db.query('pur_op', where: 'user_id = ?', whereArgs: [userId], orderBy: 'seq asc')).map(PurOp.fromMap).toList();

  /// Any account: the app-closed sweeper asks this before it touches auth.
  Future<bool> hasAnySendable() async =>
      (await _db.query('pur_op', columns: ['op_id'], where: 'failed_permanently = 0', limit: 1)).isNotEmpty;

  /// Progress kept between attempts (uploaded receipt links, the company).
  Future<void> updateOpBody(String opId, Map<String, dynamic> body) =>
      _db.update('pur_op', {'body': jsonEncode(body)}, where: 'op_id = ?', whereArgs: [opId]);

  /// [countsTowardCap]: an unexpected failure adds one; any other (no
  /// signal, a session, an update) starts again at zero.
  Future<void> recordAttempt(String opId, String error, {bool countsTowardCap = true}) => _db.rawUpdate(
      'update pur_op set attempts = case when ? then attempts + 1 else 0 end, last_error = ? where op_id = ?',
      [countsTowardCap ? 1 : 0, error, opId]);

  Future<void> markFailed(String opId, String error) =>
      _db.rawUpdate('update pur_op set failed_permanently = 1, last_error = ? where op_id = ?', [error, opId]);

  /// The purchase is recorded on the server: the op and its draft go
  /// together, so it is never shown twice.
  Future<void> finishRecord(String opId, String? draftId) => _db.transaction((txn) async {
        await txn.delete('pur_op', where: 'op_id = ?', whereArgs: [opId]);
        if (draftId != null) await txn.delete('pur_draft', where: 'id = ?', whereArgs: [draftId]);
      });

  // ── last answers read, for offline ─────────────────────────────────────

  Future<void> putCache(String userId, String name, Object json, DateTime at) => _db.insert(
        'pur_cache',
        {'user_id': userId, 'name': name, 'body': jsonEncode(json), 'fetched_at': at.millisecondsSinceEpoch},
        conflictAlgorithm: ConflictAlgorithm.replace,
      );

  Future<({Object? body, DateTime at})?> cache(String userId, String name) async {
    final rows = await _db.query('pur_cache', where: 'user_id = ? and name = ?', whereArgs: [userId, name], limit: 1);
    if (rows.isEmpty) return null;
    return (body: jsonDecode(rows.first['body']! as String), at: DateTime.fromMillisecondsSinceEpoch(rows.first['fetched_at']! as int, isUtc: true));
  }

  /// Keeps only [userId]'s saved copy ('' keeps none). Drafts and the queue
  /// are never touched: an unsent purchase waits for its buyer.
  Future<void> keepCacheOnly(String userId) => _db.delete('pur_cache', where: 'user_id <> ?', whereArgs: [userId]);
}

/// The database file on the phone, shared by the app and the background sync.
Future<PurchasingDb> openDevicePurchasingDb({bool singleInstance = true}) async =>
    PurchasingDb.open(databaseFactory, '${await getDatabasesPath()}/workmate_purchasing.db', singleInstance: singleInstance);
