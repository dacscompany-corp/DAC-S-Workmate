import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import 'package:workmate/history/data/history_db.dart';
import 'package:workmate/history/data/history_remote.dart';
import 'package:workmate/history/data/history_repository.dart';
import 'package:workmate/history/domain/history_failure.dart';
import 'package:workmate/history/domain/history_models.dart';
import 'package:workmate/requests/domain/request_models.dart';

import '../history_fakes.dart';
import '../history_samples.dart';

void main() {
  late HistoryDb db;
  late FakeHistoryRemote remote;
  late Directory dir;
  late DateTime now;
  var worker = 'u1';
  late HistoryRepository repo;

  setUpAll(sqfliteFfiInit);
  setUp(() async {
    db = await HistoryDb.open(databaseFactoryFfi, inMemoryDatabasePath, singleInstance: false);
    remote = FakeHistoryRemote();
    dir = await Directory.systemTemp.createTemp('history-test');
    now = DateTime.utc(2026, 10, 9, 2);
    worker = 'u1';
    repo = HistoryRepository(db: db, remote: remote, currentWorkerId: () => worker, photoDir: () async => dir, now: () => now);
  });
  tearDown(() async {
    await db.close();
    await dir.delete(recursive: true);
  });

  const offline = SocketException('no signal');

  test('search asks the server with the exact 0090 arguments', () async {
    final page = await repo.search(const HistoryQuery(text: ' outlet ', kind: ItemKind.material, projectId: 'f1', from: '2026-10-01'));
    expect(page.items.single.id, 'i1');
    expect(page.fromSaved, isFalse);
    expect(searchParams(const HistoryQuery(text: ' outlet ', kind: ItemKind.material, projectId: 'f1', from: '2026-10-01'),
        offset: 30, limit: historyPageSize), {
      'p_query': 'outlet', 'p_kind': 'material', 'p_category': null, 'p_folder': 'f1',
      'p_from': '2026-10-01', 'p_to': null, 'p_limit': 30, 'p_offset': 30,
    });
  });

  test('nothing is read or saved under nobody', () async {
    worker = '';
    expect(() => repo.search(const HistoryQuery()), throwsA(isA<StateError>()));
  });

  test('opening an item saves it; offline it comes back marked saved', () async {
    final fresh = await repo.item('i1');
    expect(fresh.fromSaved, isFalse);
    remote.error = offline;
    now = now.add(const Duration(days: 3));
    final saved = await repo.item('i1');
    expect(saved.fromSaved, isTrue);
    expect(saved.savedAt, DateTime.utc(2026, 10, 9, 2));
    expect(saved.item.entries.length, 2);
  });

  test('a saved copy older than 14 days is not shown offline', () async {
    await repo.item('i1');
    remote.error = offline;
    now = now.add(const Duration(days: 15));
    expect(() => repo.item('i1'), throwsA(predicate((e) => HistoryFailure.of(e!) == HistoryFailure.savedTooOld)));
  });

  test('offline with nothing saved says so, never shows an empty list as if searched', () async {
    remote.error = offline;
    expect(() => repo.search(const HistoryQuery()), throwsA(predicate((e) => HistoryFailure.of(e!) == HistoryFailure.noConnection)));
  });

  test('offline search filters the saved copy by words, kind and project', () async {
    await repo.item('i1');
    remote.error = offline;
    final hit = await repo.search(const HistoryQuery(text: 'saksakan'));
    expect(hit.items.single.id, 'i1');
    expect(hit.fromSaved, isTrue);
    expect((await repo.search(const HistoryQuery(text: 'drill'))).items, isEmpty);
    expect((await repo.search(const HistoryQuery(kind: ItemKind.tool))).items, isEmpty);
    expect((await repo.search(const HistoryQuery(projectId: 'f9'))).items, isEmpty);
    expect((await repo.search(const HistoryQuery(from: '2026-08-01', to: '2026-08-31'))).items.single.id, 'i1');
  });

  test('another worker on the same phone never sees the saved copy', () async {
    await repo.item('i1');
    worker = 'u2';
    remote.error = offline;
    expect(() => repo.item('i1'), throwsA(predicate((e) => HistoryFailure.of(e!) == HistoryFailure.noConnection)));
  });

  test('an item no longer visible is forgotten, photos included', () async {
    await repo.item('i1');
    expect(await repo.photo('o1/i1/p1.jpg'), isNotNull);
    remote.items.remove('i1');
    await expectLater(repo.item('i1'), throwsA(predicate((e) => HistoryFailure.of(e!) == HistoryFailure.notAvailable)));
    expect(await db.item('u1', 'i1'), isNull);
    expect(await db.photos('u1'), isEmpty);
  });

  test('cleanup is per entry: a switched-off project\'s entries go while the item stays', () async {
    await repo.item('i1');
    await repo.photo('o1/i1/p1.jpg');
    await repo.photo('o1/i1/p2.jpg');
    remote.visibleAnswer = [
      {'item_id': 'i1', 'entries': ['request_line:l1'], 'photo_ids': ['p1']},
    ];
    await repo.refreshSaved();
    final s = (await db.item('u1', 'i1'))!;
    expect(s.item.entries.map((e) => e.key), ['request_line:l1']);
    expect(s.item.photos.map((p) => p.id), ['p1']);
    expect((await db.photos('u1')).map((p) => p.path), ['o1/i1/p1.jpg'], reason: 'the retired photo file is deleted');
  });

  test('cleanup forgets an item no longer visible at all', () async {
    await repo.item('i1');
    remote.visibleAnswer = const [];
    await repo.refreshSaved();
    expect(await db.items('u1'), isEmpty);
  });

  test('cleanup does nothing offline (keeps the saved copy)', () async {
    await repo.item('i1');
    remote.error = offline;
    await repo.refreshSaved();
    expect(await db.item('u1', 'i1'), isNotNull);
  });

  test('a photo is downloaded once, then read from the phone', () async {
    final f = await repo.photo('o1/i1/p1.jpg');
    expect(await f!.exists(), isTrue);
    await repo.photo('o1/i1/p1.jpg');
    expect(remote.downloads, ['o1/i1/p1.jpg']);
    remote.error = offline;
    expect(await repo.photo('o1/i1/p2.jpg'), isNull, reason: 'no signal and not saved: a placeholder shows');
  });

  test('at most 200 items: the least recently opened goes first', () async {
    for (var i = 0; i < maxSavedItems; i++) {
      remote.items['x$i'] = itemJson(id: 'x$i');
      now = now.add(const Duration(minutes: 1));
      await repo.item('x$i');
    }
    now = now.add(const Duration(minutes: 1));
    await repo.item('i1');
    final ids = (await db.items('u1')).map((s) => s.item.id).toList();
    expect(ids.length, maxSavedItems);
    expect(ids, isNot(contains('x0')));
    expect(ids, contains('i1'));
  });

  test('photos are capped by count and by size, least recently shown first', () async {
    remote.photoBytes = 8 * 1024 * 1024;
    await repo.photo('o1/i1/a.jpg');
    now = now.add(const Duration(minutes: 1));
    await repo.photo('o1/i1/b.jpg');
    now = now.add(const Duration(minutes: 1));
    await repo.photo('o1/i1/c.jpg');
    expect((await db.photos('u1')).map((p) => p.path), ['o1/i1/b.jpg', 'o1/i1/c.jpg'], reason: '24 MB > 20 MB: the oldest goes');
  });

  test('sign-out deletes everything saved for that worker, files included', () async {
    await repo.item('i1');
    final f = await repo.photo('o1/i1/p1.jpg');
    await repo.keepOnly('');
    expect(await db.items('u1'), isEmpty);
    expect(await db.photos('u1'), isEmpty);
    expect(await f!.exists(), isFalse);
  });

  test('an account switch keeps only the new worker\'s copy', () async {
    await repo.item('i1');
    worker = 'u2';
    await repo.item('i1');
    await repo.keepOnly('u2');
    expect(await db.items('u1'), isEmpty);
    expect(await db.items('u2'), hasLength(1));
  });

  test('cleanup drops a cached cover whose item is no longer visible', () async {
    await repo.photo('o1/i9/c.jpg');
    remote.visibleAnswer = const [];
    await repo.refreshSaved();
    expect(await db.photos('u1'), isEmpty);
    expect(remote.calls, contains('visible:i9'));
  });

  test('cleanup keeps a cached cover whose item is still visible', () async {
    await repo.photo('o1/i9/c.jpg');
    remote.visibleAnswer = [
      {'item_id': 'i9', 'entries': ['request_line:l9'], 'photo_ids': ['x']},
    ];
    await repo.refreshSaved();
    expect(await db.photos('u1'), hasLength(1));
  });

  test('an item opened while cleanup waits keeps its fresh copy', () async {
    await repo.item('i1');
    now = now.add(const Duration(days: 15));
    remote.visibleAnswer = const [];
    remote.beforeVisibleAnswer = () async {
      remote.beforeVisibleAnswer = null;
      await repo.item('i1');
    };
    await repo.refreshSaved();
    expect((await db.item('u1', 'i1'))!.savedAt, now);
  });

  test('offline, only copies older than 14 days: connect to refresh', () async {
    await repo.item('i1');
    remote.error = offline;
    now = now.add(const Duration(days: 15));
    expect(() => repo.search(const HistoryQuery()), throwsA(predicate((e) => HistoryFailure.of(e!) == HistoryFailure.savedTooOld)));
  });

  test('sign-out also removes photo files the database never recorded', () async {
    final sep = Platform.pathSeparator;
    final stray = File('${dir.path}${sep}u1${sep}stray.jpg')..createSync(recursive: true);
    stray.writeAsBytesSync([1]);
    await repo.keepOnly('u1');
    expect(Directory('${dir.path}${sep}u1').existsSync(), isTrue);
    await repo.keepOnly('');
    expect(Directory('${dir.path}${sep}u1').existsSync(), isFalse);
  });

  test('offline, a next page after an online first page says no connection', () async {
    await repo.item('i1');
    remote.error = offline;
    await expectLater(
      repo.search(const HistoryQuery(), offset: 30),
      throwsA(predicate((e) => HistoryFailure.of(e!) == HistoryFailure.noConnection)),
    );
  });
}
