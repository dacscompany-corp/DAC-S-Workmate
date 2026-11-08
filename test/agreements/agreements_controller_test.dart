import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:workmate/agreements/domain/my_agreement.dart';
import 'package:workmate/agreements/ui/agreements_controller.dart';

import 'agreement_fakes.dart';

List<MyAgreement> all() => [
      for (final a in (jsonDecode(myAgreementsJson)['agreements'] as List)) MyAgreement.fromJson(Map<String, dynamic>.from(a as Map)),
    ];

void main() {
  late FakeAgreementsRemote remote;
  late AgreementsController c;
  final t0 = DateTime.utc(2026, 11, 8, 2);

  setUp(() {
    remote = FakeAgreementsRemote();
    c = AgreementsController(remote: remote, userId: 'w13', now: () => t0);
  });

  group('the model', () {
    test('fixed, Additional Works, daily and over-cap agreements read as the server sent them', () {
      final list = all();
      final main = list[0], aw = list[1], daily = list[2], over = list[3];
      expect([main.daily, main.agreed, main.paid, main.balance, main.progressPct], [false, 50000.0, 20000.0, 30000.0, 25.0]);
      expect(main.payments.map((p) => [p.date, p.amount, p.method]).toList(), [
        ['2026-10-08', 10000.0, 'gcash'],
        ['2026-10-01', 10000.0, 'cash'],
      ]);
      expect([aw.mainProject, aw.works, aw.progressPct], ['Alpha House', ['Wall', 'Coping'], 80.0]);
      expect([daily.daily, daily.agreed, daily.balance, daily.paid, daily.ended, daily.projectCompleted, daily.progressPct],
          [true, null, null, 700.0, true, true, null]);
      expect(daily.endedAt, DateTime.utc(2026, 11, 3, 2));
      expect([over.overPaid, over.balance], [true, -500.0]);
      expect(main.overPaid, isFalse);
    });

    test('a daily agreement never carries an agreed total or a balance, whatever arrives', () {
      final a = MyAgreement.fromJson({'id': 'x', 'pay_basis': 'daily', 'agreed': 999, 'balance': 1, 'paid': '50'});
      expect([a.agreed, a.balance, a.paid], [null, null, 50.0]);
    });
  });

  group('online only (Q2)', () {
    test('a good read shows the agreements for this account, with the time they were read', () async {
      remote.answers.add(all());
      await c.refresh();
      expect(c.agreements, hasLength(4));
      expect([c.fetchedAt, c.failure, c.showCard], [t0, null, true]);
      expect(remote.asked, ['w13']);
    });

    test('no signal afterwards CLEARS the amounts — never a stale balance', () async {
      remote.answers.addAll([all(), noSignal]);
      await c.refresh();
      await c.refresh();
      expect(c.agreements, isEmpty);
      expect([c.fetchedAt, c.failure, c.showCard], [null, AgreementsFailure.noConnection, false]);
    });

    test('a refused account (switched off, not a worker) clears them', () async {
      remote.answers.addAll([all(), notRequester]);
      await c.refresh();
      await c.refresh();
      expect(c.agreements, isEmpty);
      expect(c.failure, AgreementsFailure.notAllowed);
    });

    test('an agreement unlinked from this account disappears on the next read', () async {
      remote.answers.addAll([all(), all().where((a) => a.id != 'a-main').toList()]);
      await c.refresh();
      await c.refresh();
      expect(c.byId('a-main'), isNull);
      expect(c.agreements.map((a) => a.id), ['a-aw', 'a-daily', 'a-over']);
    });

    test('a phone signed in as someone else is refused, and nothing is shown', () async {
      remote.answers.addAll([all(), StateError('AUTH_REQUIRED')]);
      await c.refresh();
      await c.refresh();
      expect(c.agreements, isEmpty);
      expect(c.failure, AgreementsFailure.sessionExpired);
    });

    test('clear() drops everything now, and a read already in flight cannot bring it back', () async {
      remote.answers.add(all());
      await c.refresh();
      remote.gate = Completer<void>();
      remote.answers.add(all());
      final pending = c.refresh();
      c.clear();
      remote.gate!.complete();
      await pending;
      expect(c.agreements, isEmpty);
      expect(c.fetchedAt, isNull);
    });

    test('logging out (dispose) forgets the amounts, and a late answer changes nothing', () async {
      remote.answers.add(all());
      await c.refresh();
      remote.gate = Completer<void>();
      remote.answers.add(all());
      final pending = c.refresh();
      c.dispose();
      remote.gate!.complete();
      await pending;
      expect(c.agreements, isEmpty);
      expect(c.fetchedAt, isNull);
    });

    test('a fresh read hides the old amounts BEFORE it starts, and they stay hidden when it fails', () async {
      remote.answers.add(all());
      await c.refresh();
      expect(c.agreements, hasLength(4));
      remote.gate = Completer<void>();
      remote.answers.add(noSignal);
      final pending = c.refresh();
      // Checking: nothing from the last read is left to show.
      expect(c.agreements, isEmpty, reason: 'an old figure while checking');
      expect([c.fetchedAt, c.loading, c.showCard, c.failure], [null, true, false, null]);
      remote.gate!.complete();
      await pending;
      expect(c.agreements, isEmpty);
      expect([c.loading, c.failure], [false, AgreementsFailure.noConnection]);
    });

    test('only the latest read counts', () async {
      remote.gate = Completer<void>();
      // The second read answers first (empty); the first, older one answers
      // after it with every agreement — and must be ignored.
      remote.answers.addAll([<MyAgreement>[], all()]);
      final first = c.refresh();
      remote.gate!.complete();
      remote.gate = null;
      await c.refresh();
      await first;
      expect(c.agreements, isEmpty);
    });
  });

  test('Linked Labor keeps nothing on the phone: no database, preferences or file in its code', () {
    final dir = Directory('lib/agreements');
    final src = [for (final f in dir.listSync(recursive: true).whereType<File>()) f.readAsStringSync()].join('\n');
    for (final bad in ['shared_preferences', 'sqflite', 'path_provider', 'SharedPreferences', 'Database', 'writeAsString', 'File(']) {
      expect(src.contains(bad), isFalse, reason: bad);
    }
  });

  test('Failure codes read the way the server says them', () {
    expect(AgreementsFailure.of(const SocketException('x')), AgreementsFailure.noConnection);
    expect(AgreementsFailure.of(TimeoutException('x')), AgreementsFailure.noConnection);
    expect(AgreementsFailure.of(Exception('NOT_A_REQUESTER')), AgreementsFailure.notAllowed);
    expect(AgreementsFailure.of(StateError('AUTH_REQUIRED')), AgreementsFailure.sessionExpired);
    expect(AgreementsFailure.of(Exception('APP_UPDATE_REQUIRED')), AgreementsFailure.appUpdateRequired);
    expect(AgreementsFailure.of(Exception('boom')), AgreementsFailure.unexpected);
  });
}
