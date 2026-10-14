import 'dart:async';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import 'package:workmate/workplan/data/workplan_api.dart';
import 'package:workmate/workplan/data/workplan_db.dart';
import 'package:workmate/workplan/data/workplan_repository.dart';
import 'package:workmate/workplan/domain/wp_op.dart';
import 'package:workmate/workplan/domain/wp_rules.dart';
import 'package:workmate/workplan/domain/wp_task.dart';
import 'package:workmate/workplan/sync/workplan_sync.dart';

import '../../attendance/fakes.dart';
import '../workplan_fakes.dart';

void main() {
  late WorkPlanDb db;
  late FakeWorkPlanRemote remote;
  late Directory dir;
  late WorkPlanRepository repo;
  var worker = 'u1';
  var ids = 0;
  var kicks = 0;

  setUpAll(sqfliteFfiInit);
  setUp(() async {
    db = await WorkPlanDb.open(databaseFactoryFfi, inMemoryDatabasePath, singleInstance: false);
    remote = FakeWorkPlanRemote();
    dir = await Directory.systemTemp.createTemp('wp-repo');
    worker = 'u1';
    ids = 0;
    kicks = 0;
    repo = WorkPlanRepository(
      db: db,
      remote: remote,
      device: FakeDevice(),
      scheduler: FakeScheduler(),
      currentWorkerId: () => worker,
      photoDir: () async => dir,
      sendNow: () async => kicks++,
      now: () => DateTime.utc(2026, 10, 14, 2),
      newId: () => 'id${++ids}',
    );
  });
  tearDown(() async {
    await db.close();
    await dir.delete(recursive: true);
  });

  WorkPlanSync sync() => WorkPlanSync(db: db, remote: remote);

  test('the lists are saved, and shown from the phone with no signal — only to their own worker', () async {
    remote.proposals = [proposalDoc()];
    final fresh = await repo.load();
    expect(fresh.fromCache, isFalse);
    expect(fresh.entries.single.task.title, 'Wall prep');
    expect(fresh.notes.single.title, 'Site meeting');
    expect(fresh.proposals.single.state, WpProposalState.sent);
    remote.readError = const SocketException('down');
    final saved = await repo.load();
    expect(saved.fromCache, isTrue);
    expect(saved.error, isA<SocketException>());
    expect(saved.entries.single.task.id, 't1');
    expect(saved.fetchedAt, DateTime.utc(2026, 10, 14, 2));
    worker = 'u2';
    final other = await repo.load();
    expect(other.entries, isEmpty, reason: 'never another worker\'s saved tasks');
    expect(other.error, isNotNull);
  });

  test('keepOnly drops other workers\' saved copies but never unsent actions', () async {
    await repo.load();
    await repo.acknowledge(task0());
    await repo.keepOnly('u2');
    remote.readError = const SocketException('down');
    final v = await repo.load();
    expect(v.entries, isEmpty, reason: 'u1\'s saved tasks are gone');
    expect(await db.sendable('u1'), hasLength(1), reason: 'u1\'s "I\'ve read this" still waits for them');
  });

  test('"I\'ve read this" is queued once per version and sent', () async {
    final t = task0();
    await repo.acknowledge(t);
    await repo.acknowledge(t); // double tap
    expect(await db.sendable('u1'), hasLength(1));
    expect(kicks, 1);
    final v = await repo.load();
    expect(v.entries.single.ackPending, isTrue);
    expect(v.entries.single.toRead, isFalse);
    await sync().drain('u1');
    expect(remote.calls, ['ack:t1:1']);
    expect(await db.sendable('u1'), isEmpty);
  });

  test('keepOnly keeps the accepted-answer counter, so numbering never restarts', () async {
    remote.taskAnswer = taskDoc(status: 'in_progress', ackVersion: 1);
    await repo.startWork(task0());
    await sync().drain('u1');
    expect(await db.acceptedSeq('u1'), 1);
    await repo.keepOnly('u2');
    expect(await db.acceptedSeq('u1'), 1);
    await repo.reportDone(task0(taskDoc(status: 'in_progress', ackVersion: 1)), 'finished');
    remote.taskAnswer = taskDoc(status: 'reported_done', ackVersion: 1);
    await sync().drain('u1');
    expect(await db.acceptedSeq('u1'), 2);
  });

  test('a second tap after a fast accept queues nothing', () async {
    remote.work = [taskDoc(ackVersion: 1)];
    await repo.load();
    await repo.startWork(task0(remote.work.single));
    remote.taskAnswer = taskDoc(status: 'in_progress', ackVersion: 1);
    await sync().drain('u1');
    await repo.startWork(task0(remote.work.single)); // the screen's stale task
    expect(await db.sendable('u1'), isEmpty);
    expect(remote.calls.where((c) => c == 'start:t1'), hasLength(1));
  });

  test('a second "done" after a fast accept queues nothing', () async {
    remote.work = [taskDoc(status: 'in_progress', ackVersion: 1)];
    await repo.load();
    await repo.reportDone(task0(remote.work.single), 'finished');
    remote.taskAnswer = taskDoc(status: 'reported_done', ackVersion: 1);
    await sync().drain('u1');
    await repo.reportDone(task0(remote.work.single), 'finished');
    expect(await db.sendable('u1'), isEmpty);
    expect(remote.calls.where((c) => c.startsWith('done:')), hasLength(1));
  });

  test('offline, Report done after a queued Start is still queued', () async {
    remote.work = [taskDoc(ackVersion: 1)];
    await repo.load();
    await repo.startWork(task0(remote.work.single));
    await repo.reportDone(task0(remote.work.single), '');
    expect((await db.sendable('u1')).map((o) => o.kind), [WpOpKind.start, WpOpKind.done]);
  });

  test('a second check after a fast accept queues nothing; a check on a reported task is queued', () async {
    final reported = taskDoc(role: 'leader', status: 'reported_done', canCheck: true);
    remote.work = [reported];
    await repo.load();
    await repo.checkWork(task0(reported), 'ok');
    expect((await db.sendable('u1')).map((o) => o.kind), [WpOpKind.check]);
    remote.taskAnswer = taskDoc(role: 'leader', status: 'leader_checked', canCheck: false);
    await sync().drain('u1');
    await repo.checkWork(task0(reported), 'ok'); // the screen's stale task
    expect(await db.sendable('u1'), isEmpty);
    expect(remote.calls.where((c) => c.startsWith('check:')), hasLength(1));
  });

  test('a problem and its photo go in order; the photo is linked to the new problem', () async {
    final raw = File('${dir.path}/raw.jpg')..writeAsBytesSync([1]);
    final kept = await repo.keepPhoto(raw.path);
    File(kept).writeAsBytesSync([1]); // FakeDevice returns the target without writing it
    await repo.reportProblem(task0(), kind: 'materials', description: ' No cement ', requestId: 'r1', photo: kept);
    final queued = await db.sendable('u1');
    expect(queued.map((o) => o.kind), [WpOpKind.blocker, WpOpKind.photo]);
    expect(queued.last.parentOpId, queued.first.opId);
    await sync().drain('u1');
    expect(remote.calls, ['blocker:t1:materials:No cement:r1', 'photo:t1:b1:null']);
    expect(remote.attached.single, startsWith('u1/t1/'));
    expect(File(kept).existsSync(), isFalse, reason: 'sent: the phone copy goes');
  });

  test('a progress note\'s photo is linked to its history line', () async {
    final kept = File('${dir.path}/p.jpg')..writeAsBytesSync([1]);
    await repo.reportProgress(task0(), 'Half done', photo: kept.path);
    await sync().drain('u1');
    expect(remote.calls, ['progress:t1:Half done', 'photo:t1:null:1']);
  });

  test('a refused report takes its photo with it, shown and dismissed together', () async {
    final kept = File('${dir.path}/p.jpg')..writeAsBytesSync([1]);
    remote.writeError = Exception('NOT_ASSIGNED');
    await repo.reportProblem(task0(), kind: 'tool', description: 'No drill', photo: kept.path);
    await sync().drain('u1');
    expect(remote.calls, ['blocker:t1:tool:No drill:null'], reason: 'the photo is never sent');
    final v = await repo.load();
    final failed = v.entries.single.failedOps;
    expect(failed.map((o) => o.kind), [WpOpKind.blocker, WpOpKind.photo]);
    expect(failed.every((o) => o.lastError == 'notAssigned'), isTrue);
    await repo.dismissFailed(failed.first);
    expect(await db.ops('u1'), isEmpty);
    expect(kept.existsSync(), isFalse);
  });

  test('no signal: the queue waits and keeps its order', () async {
    remote.writeError = const SocketException('down');
    remote.writeErrorSticky = true;
    await repo.acknowledge(task0());
    await repo.startWork(task0());
    await sync().drain('u1');
    expect(remote.calls, ['ack:t1:1'], reason: 'Start never goes before the read');
    expect((await db.sendable('u1')).map((o) => o.kind), [WpOpKind.acknowledge, WpOpKind.start]);
    remote.writeErrorSticky = false;
    remote.writeError = null;
    await sync().drain('u1');
    expect(remote.calls, ['ack:t1:1', 'ack:t1:1', 'start:t1']);
  });

  test('an outdated read is answered, not refused; the Start after it is refused and shown', () async {
    remote.ackResult = {'stale': true, 'task': {}};
    remote.failOn['start'] = Exception('NOT_ACKNOWLEDGED');
    await repo.acknowledge(task0());
    await repo.startWork(task0());
    await sync().drain('u1');
    expect(remote.calls, ['ack:t1:1', 'start:t1']);
    final failed = (await repo.load()).entries.single.failedOps;
    expect(failed.single.kind, WpOpKind.start, reason: 'the read itself is not an error');
    expect(failed.single.lastError, 'notAcknowledged');
  });

  test('an accepted problem keeps the server\'s task: a failed refresh never unlocks Report done', () async {
    remote.work = [taskDoc(status: 'in_progress', ackVersion: 1)];
    await repo.load();
    await repo.reportProblem(task0(remote.work.single), kind: 'materials', description: 'No cement');
    remote.taskAnswer = taskDoc(status: 'in_progress', ackVersion: 1, blocked: true, blockers: [
      {'id': 'b1', 'kind': 'materials', 'description': 'No cement', 'request_id': null, 'reported_at': '2026-10-14T03:00:00+00:00', 'reported_by': 'John'},
    ]);
    await sync().drain('u1');
    expect(await db.sendable('u1'), isEmpty);
    remote.readError = const SocketException('down');
    final e = (await repo.load()).entries.single;
    expect(e.pendingOps, isEmpty);
    expect(e.task.blocked, isTrue, reason: 'the saved copy is the server\'s answer, not the list from before');
    expect(actionsFor(e).doneLock, WpLock.blocked);
  });

  test('an outdated read keeps the server\'s newer task: it stays Changed offline', () async {
    await repo.load();
    await repo.acknowledge(task0());
    remote.ackResult = {'stale': true, 'task': taskDoc(version: 2)};
    await sync().drain('u1');
    remote.readError = const SocketException('down');
    final t = (await repo.load()).entries.single.task;
    expect([t.version, t.needsReading], [2, isTrue]);
  });

  test('a list that arrives after sign-out is neither saved nor shown', () async {
    remote.readGate = Completer<void>();
    final reading = repo.load();
    worker = '';
    await repo.keepOnly('');
    remote.readGate!.complete();
    await expectLater(reading, throwsA(isA<StateError>()));
    expect(await db.cache('u1', 'work'), isNull, reason: 'the wiped copy is not written back');
  });

  test('a switch while a list travels never shows or saves it for either worker', () async {
    remote.readGate = Completer<void>();
    final reading = repo.load();
    worker = 'u2';
    remote.readGate!.complete();
    await expectLater(reading, throwsA(isA<StateError>()));
    expect(await db.cache('u1', 'work'), isNull);
    expect(await db.cache('u2', 'work'), isNull);
  });

  test('offline, a switch while the saved copy is read never shows it to the next worker', () async {
    await repo.load();
    remote.readError = const SocketException('down');
    remote.readGate = Completer<void>();
    final reading = repo.load();
    worker = 'u2';
    remote.readGate!.complete();
    await expectLater(reading, throwsA(isA<StateError>()));
  });

  test('proposal choices never mix two workers\' answers', () async {
    remote.readGate = Completer<void>();
    final choosing = repo.choices();
    worker = 'u2';
    remote.readGate!.complete();
    await expectLater(choosing, throwsA(isA<StateError>()));
    expect(await db.cache('u1', 'teams'), isNull);
    expect(await db.cache('u2', 'teams'), isNull);
  });

  test('a photo still waiting after its problem landed stays counted, once', () async {
    final kept = File('${dir.path}/p.jpg')..writeAsBytesSync([1]);
    await repo.reportProblem(task0(), kind: 'tool', description: 'No drill', photo: kept.path);
    expect(summarizeWork((await repo.load()).entries).pending, 1, reason: 'a report and its photo are one item');
    remote.failOn['photo'] = const SocketException('down');
    await sync().drain('u1');
    final e = (await repo.load()).entries.single;
    expect(e.pendingOps.single.kind, WpOpKind.photo);
    expect(e.shownPending.single.kind, WpOpKind.photo);
    expect(summarizeWork([e]).pending, 1, reason: 'the photo is still owed and still counted');
  });

  test('an older refresh cannot overwrite an accepted problem', () async {
    remote.work = [taskDoc(status: 'in_progress', ackVersion: 1)];
    await repo.load();
    remote.readGate = Completer<void>();
    final oldRead = repo.load(); // asked the server BEFORE the problem was accepted
    await repo.reportProblem(task0(remote.work.single), kind: 'materials', description: 'No cement');
    remote.taskAnswer = taskDoc(status: 'in_progress', ackVersion: 1, blocked: true, blockers: [
      {'id': 'b1', 'kind': 'materials', 'description': 'No cement', 'request_id': null, 'reported_at': '2026-10-14T03:00:00+00:00', 'reported_by': 'John'},
    ]);
    await sync().drain('u1');
    expect(await db.sendable('u1'), isEmpty);
    remote.readGate!.complete();
    final shown = (await oldRead).entries.single;
    expect(shown.task.blocked, isTrue, reason: 'the late old answer is not even shown');
    remote.readGate = null;
    remote.readError = const SocketException('down');
    final offline = (await repo.load()).entries.single;
    expect(offline.task.blocked, isTrue, reason: 'late old reads must not undo the accepted problem');
    expect(actionsFor(offline).doneLock, WpLock.blocked);
  });

  test('an action accepted by the background sync (its own connection) is not overwritten by an older read', () async {
    final file = '${dir.path}/shared.db';
    final appDb = await WorkPlanDb.open(databaseFactoryFfi, file, singleInstance: false);
    final bgDb = await WorkPlanDb.open(databaseFactoryFfi, file, singleInstance: false);
    addTearDown(() async {
      await appDb.close();
      await bgDb.close();
    });
    final app = WorkPlanRepository(
      db: appDb,
      remote: remote,
      device: FakeDevice(),
      scheduler: FakeScheduler(),
      currentWorkerId: () => worker,
      photoDir: () async => dir,
      newId: () => 'x${++ids}',
    );
    remote.work = [taskDoc(status: 'in_progress', ackVersion: 1)];
    await app.load();
    remote.readGate = Completer<void>();
    final oldRead = app.load();
    await app.reportProblem(task0(remote.work.single), kind: 'materials', description: 'No cement');
    remote.taskAnswer = taskDoc(status: 'in_progress', ackVersion: 1, blocked: true, blockers: [
      {'id': 'b1', 'kind': 'materials', 'description': 'No cement', 'request_id': null, 'reported_at': '2026-10-14T03:00:00+00:00', 'reported_by': 'John'},
    ]);
    await WorkPlanSync(db: bgDb, remote: remote).drain('u1'); // the WorkManager engine
    remote.readGate!.complete();
    await oldRead;
    remote.readGate = null;
    remote.readError = const SocketException('down');
    expect((await app.load()).entries.single.task.blocked, isTrue);
  });

  test('an accepted answer never hides a later office change: a newer read wins', () async {
    remote.work = [taskDoc(status: 'in_progress', ackVersion: 1)];
    await repo.load();
    await repo.reportProblem(task0(remote.work.single), kind: 'materials', description: 'No cement');
    remote.taskAnswer = taskDoc(status: 'in_progress', ackVersion: 1, blocked: true, blockers: [
      {'id': 'b1', 'kind': 'materials', 'description': 'No cement', 'request_id': null, 'reported_at': '2026-10-14T03:00:00+00:00', 'reported_by': 'John'},
    ]);
    await sync().drain('u1');
    // The office clears the problem; a read started after the problem landed shows it.
    remote.work = [taskDoc(status: 'in_progress', ackVersion: 1)];
    expect((await repo.load()).entries.single.task.blocked, isFalse);
    remote.readError = const SocketException('down');
    expect((await repo.load()).entries.single.task.blocked, isFalse, reason: 'the saved copy follows the newer read');
  });

  test('choices reject a switch during the awaited saves, and never write back a wiped copy', () async {
    var checks = 0;
    Future<void>? wiping;
    repo = WorkPlanRepository(
      db: db,
      remote: remote,
      device: FakeDevice(),
      scheduler: FakeScheduler(),
      currentWorkerId: () {
        final current = worker;
        if (++checks == 2) {
          scheduleMicrotask(() {
            worker = 'u2';
            wiping = repo.keepOnly('u2');
          });
        }
        return current;
      },
      photoDir: () async => dir,
    );
    await expectLater(repo.choices(), throwsA(isA<StateError>()), reason: 'a switch during database waits invalidates the result');
    await wiping;
    expect(await db.cache('u1', 'teams'), isNull, reason: 'the cleanup is not undone by a late save');
  });

  test('choices reject a switch that lands while the save commits', () async {
    var checks = 0;
    repo = WorkPlanRepository(
      db: db,
      remote: remote,
      device: FakeDevice(),
      scheduler: FakeScheduler(),
      currentWorkerId: () {
        final current = worker;
        // The third look is the one inside the save: the switch lands right after it.
        if (++checks == 3) scheduleMicrotask(() => worker = 'u2');
        return current;
      },
      photoDir: () async => dir,
    );
    await expectLater(repo.choices(), throwsA(isA<StateError>()));
  });

  test('nothing is read or queued under nobody', () async {
    worker = '';
    await expectLater(repo.load(), throwsA(isA<StateError>()));
    await expectLater(repo.acknowledge(task0()), throwsA(isA<StateError>()));
  });

  test('incomplete reports are refused before anything is queued', () async {
    await expectLater(repo.reportProgress(task0(), '  '), throwsA(isA<WpInvalid>()));
    await expectLater(repo.reportProblem(task0(), kind: 'materials', description: ''), throwsA(isA<WpInvalid>()));
    await expectLater(repo.reportProblem(task0(), kind: 'money', description: 'x'), throwsA(isA<WpInvalid>()));
    await expectLater(repo.propose(team: pilotB, destination: barlin, title: ' ', details: ''), throwsA(isA<WpInvalid>()));
    expect(await db.ops('u1'), isEmpty);
  });

  test('a proposal waits as Pending, then is sent with the 0093 arguments', () async {
    final choices = await repo.choices();
    expect(choices.teams.map((t) => t.id), ['tm1'], reason: 'only teams this leader leads');
    await repo.propose(team: pilotB, destination: barlin, title: ' Fix the gate ', details: 'Hinge broken');
    final v = await repo.load();
    expect(v.pendingProposals.single.body['title'], 'Fix the gate');
    await sync().drain('u1');
    expect(remote.calls, ['propose:Fix the gate:tm1:f1:f1']);
  });

  test('choices come from the phone with no signal', () async {
    await repo.choices();
    remote.readError = const SocketException('down');
    final saved = await repo.choices();
    expect(saved.fromCache, isTrue);
    expect(saved.teams.single.id, 'tm1');
  });

  test('a refused action for a task no longer on the list is still shown', () async {
    remote.writeError = Exception('NOT_ASSIGNED');
    await repo.startWork(task0());
    await sync().drain('u1');
    remote.work = [];
    final v = await repo.load();
    expect(v.entries, isEmpty);
    expect(v.otherFailed.single.kind, WpOpKind.start);
  });
}
