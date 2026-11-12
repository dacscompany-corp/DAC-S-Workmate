import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:workmate/requests/data/requests_api.dart';
import 'package:workmate/requests/domain/remote_request.dart';
import 'package:workmate/requests/domain/request_draft.dart';
import 'package:workmate/requests/domain/request_status.dart';
import 'package:workmate/requests/list/requests_controller.dart';
import 'package:workmate/requests/list/requests_screen.dart';
import 'package:workmate/requests/requests_services.dart';
import 'package:workmate/ui/theme.dart';

import '../../attendance/fakes.dart' show useTallPhone;
import '../domain/request_models_test.dart' show requestDoc;
import '../request_fakes.dart';

void main() {
  late FakeRequestsApi api;
  late RequestsController controller;

  setUp(() {
    api = FakeRequestsApi();
    controller = RequestsController(api: api, now: () => DateTime.utc(2026, 10, 5, 2));
  });

  RequestEntry remote(String id, SyncState state, {bool mine = true, bool conflict = false}) {
    final doc = requestDoc(id: id, mine: mine);
    if (conflict) (doc['lines'] as List).first['has_conflict'] = true;
    return RequestEntry(state: state, remote: RemoteRequest.fromJson(doc));
  }

  Future<void> show(WidgetTester tester) async {
    useTallPhone(tester);
    // Taller than the shared phone: the Ahem test font makes the header and cards tall, so every card must be built.
    tester.view.physicalSize = const Size(1200, 9000);
    await controller.refresh();
    await tester.pumpWidget(MaterialApp(
      theme: workMateTheme(),
      home: Scaffold(body: RequestsScreen(controller: controller, services: RequestsServices(api: api, takePhoto: (_) async => null))),
    ));
    await tester.pumpAndSettle();
  }

  testWidgets('a spinner while the first read runs; then the empty text', (tester) async {
    useTallPhone(tester);
    api.viewGate = Completer<void>();
    unawaited(controller.refresh());
    await tester.pumpWidget(MaterialApp(
      theme: workMateTheme(),
      home: Scaffold(body: RequestsScreen(controller: controller, services: RequestsServices(api: api, takePhoto: (_) async => null))),
    ));
    await tester.pump();
    expect(find.byType(CircularProgressIndicator), findsOneWidget);
    api.viewGate!.complete();
    await tester.pumpAndSettle();
    expect(find.byType(CircularProgressIndicator), findsNothing);
    expect(find.text('Nothing here yet. Tap New request to ask for materials or tools.'), findsOneWidget);
  });

  void seed() {
    api.savedDrafts['d7'] = RequestDraft(id: 'd7', createdAt: DateTime.utc(2026, 10, 5), destination: site);
    api.view = RequestsView(entries: [
      remote('r1', SyncState.received),
      remote('r2', SyncState.pending),
      remote('r3', SyncState.needsResolution, conflict: true),
      remote('r4', SyncState.failed),
      remote('r5', SyncState.needsResolution, mine: false, conflict: true),
    ]);
  }

  Finder inCard(String key, Finder f) => find.descendant(of: find.byKey(Key('entry-$key')), matching: f);

  testWidgets('each chip shows its count; the title and New request are at the top', (tester) async {
    seed();
    await show(tester);
    expect(find.text('Requests'), findsOneWidget);
    expect(find.byKey(const Key('new-request')), findsOneWidget);
    for (final (key, n) in [('filter-all', '6'), ('filter-drafts', '1'), ('filter-pending', '1'), ('filter-attention', '3')]) {
      expect(find.descendant(of: find.byKey(Key(key)), matching: find.text(n)), findsOneWidget, reason: key);
    }
  });

  testWidgets('every card shows the 3-part bar and its status line', (tester) async {
    seed();
    await show(tester);
    for (final (key, line) in [
      ('d7', 'Not sent yet · finish and send'),
      ('r1', 'Received by the office'),
      ('r2', 'Saved on this phone · sends when there is signal'),
      ('r3', 'Needs attention · open it to see why'),
      ('r4', 'Needs attention · open it to see why'),
    ]) {
      await tester.ensureVisible(find.byKey(Key('entry-$key')));
      expect(inCard(key, find.text(line)), findsOneWidget, reason: key);
      expect(inCard(key, find.byKey(const Key('stage-seg-2'))), findsOneWidget, reason: key);
    }
  });

  testWidgets('the worker\'s own attention cards have a red border; a team member\'s does not', (tester) async {
    seed();
    await show(tester);
    Color border(String key) =>
        (tester.widget<Material>(inCard(key, find.byType(Material)).first).shape! as RoundedRectangleBorder).side.color;
    expect(border('r3'), WmColors.danger);
    expect(border('r4'), WmColors.danger);
    expect(border('r5'), WmColors.border);
    expect(border('r1'), WmColors.border);
  });

  testWidgets('switching chips filters the list', (tester) async {
    seed();
    await show(tester);
    await tester.ensureVisible(find.byKey(const Key('filter-attention')));
    await tester.tap(find.byKey(const Key('filter-attention')));
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('entry-r3')), findsOneWidget);
    expect(find.byKey(const Key('entry-r1')), findsNothing);
    expect(find.byKey(const Key('entry-d7')), findsNothing);
  });
}
