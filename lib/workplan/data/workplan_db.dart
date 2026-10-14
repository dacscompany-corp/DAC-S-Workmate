import 'dart:convert';

import 'package:sqflite/sqflite.dart';

import '../domain/wp_op.dart';

/// My Work's send-once queue and the last answers the app read (for offline
/// use) — every row scoped by worker, because site phones are shared. Its own
/// file, apart from attendance and requests, so none can break another.
class WorkPlanDb {
  WorkPlanDb._(this._db);

  final Database _db;

  static Future<WorkPlanDb> open(DatabaseFactory factory, String path, {bool singleInstance = true}) async {
    final db = await factory.openDatabase(
      path,
      options: OpenDatabaseOptions(version: 1, onCreate: _create, singleInstance: singleInstance),
    );
    return WorkPlanDb._(db);
  }

  static Future<void> _create(Database db, int version) async {
    await db.execute('''
      create table wp_op (
        op_id text primary key,
        worker_id text not null,
        kind text not null,
        task_id text,
        parent_op_id text,
        blocker_id text,
        event_id integer,
        body text not null,
        seq integer not null,
        attempts integer not null default 0,
        last_error text,
        failed_permanently integer not null default 0,
        created_at integer not null
      )''');
    await db.execute('''
      create table wp_cache (
        worker_id text not null,
        name text not null,
        body text not null,
        fetched_at integer not null,
        primary key (worker_id, name)
      )''');
    // The server's answer to each accepted action, numbered per worker, so a
    // read that started BEFORE the action can never overwrite it.
    await db.execute('''
      create table wp_accepted (
        worker_id text not null,
        task_id text not null,
        seq integer not null,
        body text not null,
        primary key (worker_id, task_id)
      )''');
    await db.execute('''
      create table wp_accepted_seq (
        worker_id text primary key,
        seq integer not null
      )''');
  }

  Future<void> close() => _db.close();

  // ── the queue ──────────────────────────────────────────────────────────

  /// Appended in list order (one transaction: a report and its photo are
  /// queued together or not at all).
  Future<void> addOps(List<WpOp> ops) => _db.transaction((txn) async {
        var seq = (await txn.rawQuery('select coalesce(max(seq), 0) as s from wp_op')).first['s']! as int;
        for (final o in ops) {
          seq++;
          await txn.insert('wp_op', {...o.toMap(), 'seq': seq});
        }
      });

  /// This worker's ops that may still be sent, in queue order.
  Future<List<WpOp>> sendable(String workerId) async =>
      (await _db.query('wp_op', where: 'worker_id = ? and failed_permanently = 0', whereArgs: [workerId], orderBy: 'seq asc'))
          .map(WpOp.fromMap)
          .toList();

  /// Every op of this worker, refused ones included, in queue order.
  Future<List<WpOp>> ops(String workerId) async =>
      (await _db.query('wp_op', where: 'worker_id = ?', whereArgs: [workerId], orderBy: 'seq asc')).map(WpOp.fromMap).toList();

  Future<WpOp?> op(String opId) async {
    final rows = await _db.query('wp_op', where: 'op_id = ?', whereArgs: [opId], limit: 1);
    return rows.isEmpty ? null : WpOp.fromMap(rows.first);
  }

  /// Any worker: the app-closed sweeper asks this before it touches auth.
  Future<bool> hasAnySendable() async =>
      (await _db.query('wp_op', columns: ['op_id'], where: 'failed_permanently = 0', limit: 1)).isNotEmpty;

  /// [countsTowardCap]: an unexpected failure adds one; any other failure
  /// starts the run again at zero, so only such failures IN A ROW give up.
  Future<void> recordAttempt(String opId, String error, {bool countsTowardCap = true}) => _db.rawUpdate(
      'update wp_op set attempts = case when ? then attempts + 1 else 0 end, last_error = ? where op_id = ?',
      [countsTowardCap ? 1 : 0, error, opId]);

  Future<void> markFailed(String opId, String error) =>
      _db.rawUpdate('update wp_op set failed_permanently = 1, last_error = ? where op_id = ?', [error, opId]);

  /// A refused report takes its photos with it: they can never be linked.
  Future<void> failChildren(String parentOpId, String error) => _db.rawUpdate(
      'update wp_op set failed_permanently = 1, last_error = ? where parent_op_id = ? and failed_permanently = 0',
      [error, parentOpId]);

  /// The photos queued with a report.
  Future<List<WpOp>> children(String parentOpId) async =>
      (await _db.query('wp_op', where: 'parent_op_id = ?', whereArgs: [parentOpId], orderBy: 'seq asc')).map(WpOp.fromMap).toList();

  Future<void> deleteOp(String opId) => _db.delete('wp_op', where: 'op_id = ?', whereArgs: [opId]);

  /// An action the server accepted, in ONE transaction: its photos are
  /// pointed at what it created, the task the server answered with replaces
  /// the saved copy of that task, and only then does the action leave the
  /// queue. A refresh that fails afterwards can then never bring back the
  /// state from before the action (e.g. unlock Report done after a problem
  /// was accepted).
  Future<void> settle(WpOp op, {Map<String, dynamic>? task, String? blockerId, int? eventId}) => _db.transaction((txn) async {
        if (blockerId != null || eventId != null) {
          await txn.update('wp_op', {'blocker_id': blockerId, 'event_id': eventId},
              where: 'parent_op_id = ?', whereArgs: [op.opId]);
        }
        final id = task?['id'];
        if (id is String) {
          final seq = await _nextAccepted(txn, op.workerId);
          await txn.insert('wp_accepted', {'worker_id': op.workerId, 'task_id': id, 'seq': seq, 'body': jsonEncode(task)},
              conflictAlgorithm: ConflictAlgorithm.replace);
          await _patchSavedTask(txn, op.workerId, id, task!);
        }
        await txn.delete('wp_op', where: 'op_id = ?', whereArgs: [op.opId]);
      });

  Future<int> _nextAccepted(Transaction txn, String workerId) async {
    final rows = await txn.query('wp_accepted_seq', columns: ['seq'], where: 'worker_id = ?', whereArgs: [workerId], limit: 1);
    final next = (rows.isEmpty ? 0 : rows.first['seq']! as int) + 1;
    await txn.insert('wp_accepted_seq', {'worker_id': workerId, 'seq': next}, conflictAlgorithm: ConflictAlgorithm.replace);
    return next;
  }

  /// The number of [workerId]'s newest accepted answer. A read takes it
  /// BEFORE asking the server: everything up to it is already in what the
  /// server will answer; anything above it arrived while the read travelled.
  Future<int> acceptedSeq(String workerId) async {
    final rows = await _db.query('wp_accepted_seq', columns: ['seq'], where: 'worker_id = ?', whereArgs: [workerId], limit: 1);
    return rows.isEmpty ? 0 : rows.first['seq']! as int;
  }

  /// Replaces one task in [workerId]'s saved task list. Never creates a list:
  /// a copy wiped at sign-out stays wiped.
  Future<void> _patchSavedTask(Transaction txn, String workerId, String taskId, Map<String, dynamic> doc) async {
    final rows =
        await txn.query('wp_cache', columns: ['body'], where: 'worker_id = ? and name = ?', whereArgs: [workerId, 'work'], limit: 1);
    if (rows.isEmpty) return;
    final list = [for (final d in jsonDecode(rows.first['body']! as String) as List<dynamic>) Map<String, dynamic>.from(d as Map)];
    final i = list.indexWhere((d) => d['id'] == taskId);
    if (i < 0) return;
    list[i] = doc;
    await txn.update('wp_cache', {'body': jsonEncode(list)}, where: 'worker_id = ? and name = ?', whereArgs: [workerId, 'work']);
  }

  // ── last answers read, for offline ─────────────────────────────────────

  /// Saves lists read from the server for [workerId], in ONE transaction that
  /// first asks [stillValid] — so a sign-out's cleanup (also a transaction)
  /// either ran before and refuses this save, or runs after and removes it.
  /// Throws AUTH_REQUIRED when the worker changed.
  ///
  /// [readSince] (the [acceptedSeq] taken before the read): in the task list
  /// ('work'), every task with an accepted answer numbered above it keeps that
  /// answer — the read is older than the action. Answers at or below it are
  /// in the server's list already and are forgotten. Returns the lists as
  /// saved (what the screen should show).
  Future<Map<String, List<Map<String, dynamic>>>> saveLists(
    String workerId,
    Map<String, List<Map<String, dynamic>>> lists,
    DateTime at, {
    required bool Function() stillValid,
    int? readSince,
  }) =>
      _db.transaction((txn) async {
        if (!stillValid()) throw StateError('AUTH_REQUIRED');
        final out = <String, List<Map<String, dynamic>>>{};
        for (final e in lists.entries) {
          var docs = e.value;
          if (e.key == 'work' && readSince != null) {
            final newer = {
              for (final r in await txn.query('wp_accepted', where: 'worker_id = ? and seq > ?', whereArgs: [workerId, readSince]))
                r['task_id']! as String: Map<String, dynamic>.from(jsonDecode(r['body']! as String) as Map),
            };
            docs = [for (final d in docs) newer[d['id']] ?? d];
            await txn.delete('wp_accepted', where: 'worker_id = ? and seq <= ?', whereArgs: [workerId, readSince]);
          }
          await txn.insert(
            'wp_cache',
            {'worker_id': workerId, 'name': e.key, 'body': jsonEncode(docs), 'fetched_at': at.millisecondsSinceEpoch},
            conflictAlgorithm: ConflictAlgorithm.replace,
          );
          out[e.key] = docs;
        }
        return out;
      });

  Future<({Object? body, DateTime at})?> cache(String workerId, String name) async {
    final rows = await _db.query('wp_cache', where: 'worker_id = ? and name = ?', whereArgs: [workerId, name], limit: 1);
    if (rows.isEmpty) return null;
    return (
      body: jsonDecode(rows.first['body']! as String),
      at: DateTime.fromMillisecondsSinceEpoch(rows.first['fetched_at']! as int, isUtc: true),
    );
  }

  /// Spec §11: another worker's saved tasks and notes are never shown on this
  /// phone — only [workerId]'s copy is kept ('' keeps none). Queued ops stay:
  /// cleanup must never delete unsent work; they wait for their own worker.
  /// The accepted-answer counter ([wp_accepted_seq]) is kept — it holds no
  /// private data, and restarting a worker's numbering could let a read
  /// already in flight forget a newer accepted answer.
  Future<void> keepCacheOnly(String workerId) => _db.transaction((txn) async {
        for (final table in ['wp_cache', 'wp_accepted']) {
          await txn.delete(table, where: 'worker_id <> ?', whereArgs: [workerId]);
        }
      });
}

/// The database file on the phone, shared by the app and the background sync.
Future<WorkPlanDb> openDeviceWorkPlanDb({bool singleInstance = true}) async =>
    WorkPlanDb.open(databaseFactory, '${await getDatabasesPath()}/workmate_workplan.db', singleInstance: singleInstance);
