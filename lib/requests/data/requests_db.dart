import 'dart:convert';

import 'package:sqflite/sqflite.dart';

import '../domain/request_draft.dart';
import '../domain/request_op.dart';

/// Drafts, the send-once queue, what each sent draft became on the server,
/// and the last answers the app read (for offline use) — every row scoped by
/// worker, because site phones are shared (spec §4E). Its own file, apart
/// from the attendance database, so neither can break the other.
class RequestsDb {
  RequestsDb._(this._db);

  final Database _db;

  static Future<RequestsDb> open(DatabaseFactory factory, String path, {bool singleInstance = true}) async {
    final db = await factory.openDatabase(
      path,
      options: OpenDatabaseOptions(version: 1, onCreate: _create, singleInstance: singleInstance),
    );
    return RequestsDb._(db);
  }

  static Future<void> _create(Database db, int version) async {
    await db.execute('''
      create table request_draft (
        id text primary key,
        worker_id text not null,
        body text not null,
        queued integer not null default 0,
        created_at integer not null,
        updated_at integer not null
      )''');
    await db.execute('''
      create table request_op (
        op_id text primary key,
        worker_id text not null,
        kind text not null,
        draft_id text,
        request_id text,
        line_id text,
        line_position integer,
        body text not null,
        base_version integer,
        seq integer not null,
        attempts integer not null default 0,
        last_error text,
        failed_permanently integer not null default 0,
        created_at integer not null
      )''');
    await db.execute('''
      create table request_link (
        draft_id text primary key,
        worker_id text not null,
        request_id text not null
      )''');
    await db.execute('''
      create table request_cache (
        worker_id text not null,
        name text not null,
        body text not null,
        fetched_at integer not null,
        primary key (worker_id, name)
      )''');
  }

  Future<void> close() => _db.close();

  // ── drafts ─────────────────────────────────────────────────────────────

  /// Never rewrites a queued draft: once handed to the queue it changes only
  /// through [unqueueDraft], so a stray save can never make it editable twice.
  Future<void> saveDraft(String workerId, RequestDraft d, DateTime now) => _db.transaction((txn) async {
        final queued = await txn.query('request_draft', columns: ['id'], where: 'id = ? and queued = 1', whereArgs: [d.id], limit: 1);
        if (queued.isNotEmpty) return;
        await txn.insert(
          'request_draft',
          {
            'id': d.id,
            'worker_id': workerId,
            'body': jsonEncode(d.toJson()),
            'queued': 0,
            'created_at': d.createdAt.millisecondsSinceEpoch,
            'updated_at': now.millisecondsSinceEpoch,
          },
          conflictAlgorithm: ConflictAlgorithm.replace,
        );
      });

  /// [queued] false = still being edited; true = handed to the queue.
  Future<List<RequestDraft>> drafts(String workerId, {required bool queued}) async => (await _db.query('request_draft',
          where: 'worker_id = ? and queued = ?', whereArgs: [workerId, queued ? 1 : 0], orderBy: 'created_at desc'))
      .map((m) => RequestDraft.fromJson(Map<String, dynamic>.from(jsonDecode(m['body']! as String) as Map)))
      .toList();

  Future<RequestDraft?> draft(String workerId, String id) async {
    final rows = await _db.query('request_draft', where: 'worker_id = ? and id = ?', whereArgs: [workerId, id], limit: 1);
    return rows.isEmpty
        ? null
        : RequestDraft.fromJson(Map<String, dynamic>.from(jsonDecode(rows.first['body']! as String) as Map));
  }

  /// The row only; its photo files belong to the caller (they may still be
  /// owed to the server by a queued photo op).
  Future<void> deleteDraft(String workerId, String id) =>
      _db.delete('request_draft', where: 'worker_id = ? and id = ?', whereArgs: [workerId, id]);

  /// Deletes an UNSENT draft and returns what was stored, so its photos can
  /// go too; null (nothing deleted) when it is queued or not this worker's.
  Future<RequestDraft?> deleteUnsentDraft(String workerId, String id) => _db.transaction((txn) async {
        final rows = await txn.query('request_draft',
            where: 'worker_id = ? and id = ? and queued = 0', whereArgs: [workerId, id], limit: 1);
        if (rows.isEmpty) return null;
        await txn.delete('request_draft', where: 'id = ?', whereArgs: [id]);
        return RequestDraft.fromJson(Map<String, dynamic>.from(jsonDecode(rows.first['body']! as String) as Map));
      });

  /// One transaction: the draft is marked queued AND its ops exist, or
  /// neither — a queued draft with no ops would sit "Pending" forever. False
  /// (and nothing written) when the draft is already queued: a second Send
  /// must never queue a second request.
  Future<bool> queueDraft(String workerId, RequestDraft d, List<RequestOp> ops, DateTime now) => _db.transaction((txn) async {
        final already = await txn.query('request_draft', columns: ['id'], where: 'id = ? and queued = 1', whereArgs: [d.id], limit: 1);
        if (already.isNotEmpty) return false;
        await txn.insert(
          'request_draft',
          {
            'id': d.id,
            'worker_id': workerId,
            'body': jsonEncode(d.toJson()),
            'queued': 1,
            'created_at': d.createdAt.millisecondsSinceEpoch,
            'updated_at': now.millisecondsSinceEpoch,
          },
          conflictAlgorithm: ConflictAlgorithm.replace,
        );
        await _insertOps(txn, ops);
        return true;
      });

  /// A refused draft back to editing: its (all refused) ops go, it is no
  /// longer queued. Refused if any of its ops could still be sent.
  Future<bool> unqueueDraft(String workerId, String draftId) => _db.transaction((txn) async {
        // Its request already reached the server: sending it again would duplicate it.
        final landed = await txn.query('request_link', where: 'draft_id = ?', whereArgs: [draftId], limit: 1);
        if (landed.isNotEmpty) return false;
        final live = await txn.query('request_op',
            where: 'worker_id = ? and draft_id = ? and failed_permanently = 0', whereArgs: [workerId, draftId], limit: 1);
        if (live.isNotEmpty) return false;
        await txn.delete('request_op', where: 'worker_id = ? and draft_id = ?', whereArgs: [workerId, draftId]);
        await txn.update('request_draft', {'queued': 0}, where: 'worker_id = ? and id = ?', whereArgs: [workerId, draftId]);
        return true;
      });

  // ── the queue ──────────────────────────────────────────────────────────

  Future<void> addOps(List<RequestOp> ops) => _db.transaction((txn) => _insertOps(txn, ops));

  /// Appended in list order: seq continues from the highest in the table.
  Future<void> _insertOps(Transaction txn, List<RequestOp> ops) async {
    final top = (await txn.rawQuery('select coalesce(max(seq), 0) as s from request_op')).first['s']! as int;
    var seq = top;
    for (final o in ops) {
      seq++;
      await txn.insert('request_op', {...o.toMap(), 'seq': seq});
    }
  }

  /// This worker's ops that may still be sent, in queue order.
  Future<List<RequestOp>> sendable(String workerId) async => (await _db.query('request_op',
          where: 'worker_id = ? and failed_permanently = 0', whereArgs: [workerId], orderBy: 'seq asc'))
      .map(RequestOp.fromMap)
      .toList();

  /// Every op of this worker, refused ones included, in queue order.
  Future<List<RequestOp>> ops(String workerId) async =>
      (await _db.query('request_op', where: 'worker_id = ?', whereArgs: [workerId], orderBy: 'seq asc'))
          .map(RequestOp.fromMap)
          .toList();

  Future<RequestOp?> op(String opId) async {
    final rows = await _db.query('request_op', where: 'op_id = ?', whereArgs: [opId], limit: 1);
    return rows.isEmpty ? null : RequestOp.fromMap(rows.first);
  }

  /// Any worker: the app-closed sweeper asks this before it touches auth.
  Future<bool> hasAnySendable() async =>
      (await _db.query('request_op', columns: ['op_id'], where: 'failed_permanently = 0', limit: 1)).isNotEmpty;

  /// [countsTowardCap]: an unexpected failure (or a photo the server never
  /// saw) adds one; any other failure (no signal, an expired session) starts
  /// the run again at zero, so only such failures IN A ROW can give an op up.
  Future<void> recordAttempt(String opId, String error, {bool countsTowardCap = true}) => _db.rawUpdate(
      'update request_op set attempts = case when ? then attempts + 1 else 0 end, last_error = ? where op_id = ?',
      [countsTowardCap ? 1 : 0, error, opId]);

  Future<void> markFailed(String opId, String error) =>
      _db.rawUpdate('update request_op set failed_permanently = 1, last_error = ? where op_id = ?', [error, opId]);

  /// A refused submit takes its photo ops with it: they can never land.
  Future<void> failDraftOps(String draftId, String error) => _db.rawUpdate(
      'update request_op set failed_permanently = 1, last_error = ? where draft_id = ? and failed_permanently = 0',
      [error, draftId]);

  Future<void> setBase(String opId, int base) =>
      _db.update('request_op', {'base_version': base}, where: 'op_id = ?', whereArgs: [opId]);

  Future<void> deleteOp(String opId) => _db.delete('request_op', where: 'op_id = ?', whereArgs: [opId]);

  // ── what a sent draft became ───────────────────────────────────────────

  /// The draft's submit landed: remember the request, and point its photo
  /// ops at the request and at each photo's line (by position). One
  /// transaction, so a photo op never waits on a link that half-exists.
  Future<void> link(String workerId, String draftId, String requestId, List<String> lineIds) => _db.transaction((txn) async {
        await txn.insert('request_link', {'draft_id': draftId, 'worker_id': workerId, 'request_id': requestId},
            conflictAlgorithm: ConflictAlgorithm.replace);
        final photos = await txn.query('request_op',
            where: "worker_id = ? and draft_id = ? and kind = 'photo'", whereArgs: [workerId, draftId]);
        for (final p in photos) {
          final pos = p['line_position'] as int?;
          await txn.update(
            'request_op',
            {'request_id': requestId, 'line_id': (pos != null && pos < lineIds.length) ? lineIds[pos] : null},
            where: 'op_id = ?',
            whereArgs: [p['op_id']],
          );
        }
      });

  /// draft id → request id, for this worker.
  Future<Map<String, String>> links(String workerId) async => {
        for (final m in await _db.query('request_link', where: 'worker_id = ?', whereArgs: [workerId]))
          m['draft_id']! as String: m['request_id']! as String,
      };

  Future<void> deleteLink(String draftId) => _db.delete('request_link', where: 'draft_id = ?', whereArgs: [draftId]);

  // ── last answers read, for offline ─────────────────────────────────────

  Future<void> putCache(String workerId, String name, Object json, DateTime at) => _db.insert(
        'request_cache',
        {'worker_id': workerId, 'name': name, 'body': jsonEncode(json), 'fetched_at': at.millisecondsSinceEpoch},
        conflictAlgorithm: ConflictAlgorithm.replace,
      );

  Future<({Object? body, DateTime at})?> cache(String workerId, String name) async {
    final rows = await _db.query('request_cache', where: 'worker_id = ? and name = ?', whereArgs: [workerId, name], limit: 1);
    if (rows.isEmpty) return null;
    return (
      body: jsonDecode(rows.first['body']! as String),
      at: DateTime.fromMillisecondsSinceEpoch(rows.first['fetched_at']! as int, isUtc: true),
    );
  }
}

/// The database file on the phone, shared by the app and the background sync.
Future<RequestsDb> openDeviceRequestsDb({bool singleInstance = true}) async =>
    RequestsDb.open(databaseFactory, '${await getDatabasesPath()}/workmate_requests.db', singleInstance: singleInstance);
