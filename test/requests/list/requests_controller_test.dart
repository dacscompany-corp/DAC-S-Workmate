import 'dart:async';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:workmate/requests/data/requests_api.dart';
import 'package:workmate/requests/domain/remote_request.dart';
import 'package:workmate/requests/domain/request_draft.dart';
import 'package:workmate/requests/domain/request_failure.dart';
import 'package:workmate/requests/domain/request_status.dart';
import 'package:workmate/requests/home/request_updates.dart';
import 'package:workmate/requests/home/request_updates_card.dart';
import 'package:workmate/requests/list/requests_controller.dart';
import 'package:workmate/ui/theme.dart';

import '../domain/request_models_test.dart' show requestDoc;
import '../request_fakes.dart';

RequestEntry remoteEntry(String id, SyncState state, {bool conflict = false}) {
  final doc = requestDoc(id: id);
  if (conflict) (doc['lines'] as List).first['has_conflict'] = true;
  return RequestEntry(state: state, remote: RemoteRequest.fromJson(doc));
}

void main() {
  late FakeRequestsApi api;
  final now = DateTime.utc(2026, 10, 5, 2); // Mon 5 Oct, 10:00 Manila

  setUp(() => api = FakeRequestsApi());

  test('drafts come first, then the server\'s list, and filters narrow it', () async {
    api.savedDrafts['d9'] = RequestDraft(id: 'd9', createdAt: DateTime.utc(2026, 10, 4));
    api.view = RequestsView(entries: [
      remoteEntry('r1', SyncState.received),
      remoteEntry('r2', SyncState.pending),
      remoteEntry('r3', SyncState.needsResolution, conflict: true),
      remoteEntry('r4', SyncState.failed),
    ]);
    final c = RequestsController(api: api, now: () => now);
    await c.refresh();
    expect(c.loading, isFalse);
    expect(c.rows.map((e) => e.key), ['d9', 'r1', 'r2', 'r3', 'r4']);
    c.setFilter(RequestFilter.drafts);
    expect(c.rows.map((e) => e.key), ['d9']);
    c.setFilter(RequestFilter.pending);
    expect(c.rows.map((e) => e.key), ['r2']);
    c.setFilter(RequestFilter.attention);
    expect(c.rows.map((e) => e.key), ['r3', 'r4']);
    expect(c.entry('r2')!.state, SyncState.pending);
    expect(c.updates.needsAction, 2);
    expect(c.updates.pending, 1);
    expect(c.updates.drafts, 1);
    expect(c.updates.nextDelivery, '2026-10-14');
  });

  test('no signal: the phone\'s copy stays, with the reason', () async {
    api.view = RequestsView(entries: [remoteEntry('r1', SyncState.received)], fromCache: true, error: const SocketException('down'));
    final c = RequestsController(api: api, now: () => now);
    await c.refresh();
    expect(c.failure, RequestFailure.noConnection);
    expect(c.rows.single.key, 'r1');
  });

  test('a read that fails outright is a failure, not an empty list', () async {
    api.viewError = StateError('AUTH_REQUIRED');
    final c = RequestsController(api: api, now: () => now);
    await c.refresh();
    expect(c.failure, RequestFailure.sessionExpired);
  });

  test('a refresh asked for during a read runs once more afterwards', () async {
    final gate = Completer<void>();
    api.viewGate = gate;
    final c = RequestsController(api: api, now: () => now);
    final first = c.refresh();
    api.view = RequestsView(entries: [remoteEntry('r1', SyncState.received)]);
    final second = c.refresh();
    api.viewGate = null;
    gate.complete();
    await Future.wait([first, second]);
    expect(api.viewReads, 2);
    expect(c.rows.single.key, 'r1');
  });

  test('summary counts and the next delivery', () {
    final u = summarizeRequests([remoteEntry('r1', SyncState.received)], now);
    expect(u.isEmpty, isFalse);
    expect(u.nextDelivery, '2026-10-14');
    expect(summarizeRequests(const [], now).isEmpty, isTrue);
  });

  testWidgets('Home\'s card says what needs the worker and opens Requests', (tester) async {
    var opened = 0;
    await tester.pumpWidget(MaterialApp(
      theme: workMateTheme(),
      home: Scaffold(
        body: RequestUpdatesCard(
          updates: const RequestUpdates(needsAction: 1, pending: 2, drafts: 1, nextDelivery: '2026-10-14'),
          onOpen: () => opened++,
        ),
      ),
    ));
    expect(find.text('1 needs your attention'), findsOneWidget);
    expect(find.text('2 waiting for signal'), findsOneWidget);
    expect(find.text('1 draft not sent'), findsOneWidget);
    expect(find.text('Next delivery Wed 14 Oct'), findsOneWidget);
    await tester.tap(find.byKey(const Key('request-updates')));
    expect(opened, 1);
    await tester.pumpWidget(MaterialApp(home: Scaffold(body: RequestUpdatesCard(updates: const RequestUpdates(), onOpen: () {}))));
    expect(find.byKey(const Key('request-updates')), findsNothing);
  });
}
