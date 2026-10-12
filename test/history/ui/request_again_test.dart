import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:workmate/history/domain/history_models.dart';
import 'package:workmate/history/ui/find_previous_screen.dart';
import 'package:workmate/requests/compose/compose_screen.dart';
import 'package:workmate/requests/compose/item_editor_screen.dart';
import 'package:workmate/requests/domain/request_draft.dart';
import 'package:workmate/requests/list/requests_controller.dart';
import 'package:workmate/requests/list/requests_screen.dart';
import 'package:workmate/requests/requests_services.dart';
import 'package:workmate/ui/theme.dart';

import '../../attendance/fakes.dart' show useTallPhone;
import '../../requests/compose/compose_test.dart' show tapKey;
import '../../requests/request_fakes.dart';
import '../history_fakes.dart';
import '../history_samples.dart';

void main() {
  late FakeRequestsApi api;
  late FakeHistoryApi history;
  setUp(() {
    api = FakeRequestsApi();
    history = FakeHistoryApi();
  });

  RequestsServices services({bool withHistory = true}) =>
      RequestsServices(api: api, takePhoto: (_) async => null, history: withHistory ? history : null);

  Future<void> openCompose(WidgetTester tester, {bool withHistory = true}) async {
    useTallPhone(tester);
    await tester.pumpWidget(MaterialApp(
      theme: workMateTheme(),
      home: ComposeScreen(draft: api.newDraft(), services: services(withHistory: withHistory), now: () => DateTime(2026, 10, 11)),
    ));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('add-item')));
    await tester.pumpAndSettle();
  }

  Future<void> requestAgainFromHistory(WidgetTester tester) async {
    await tester.tap(find.byKey(const Key('history-card-i1')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('history-request-again')));
    await tester.pumpAndSettle();
  }

  testWidgets('mid-request: the picked item comes back filled in with its link; the worker sets the quantity', (tester) async {
    await openCompose(tester);
    await tapKey(tester, 'item-find-previous');
    await requestAgainFromHistory(tester);
    expect(find.byType(ItemEditorScreen), findsOneWidget);
    expect(find.byKey(const Key('item-from-history')), findsOneWidget);
    expect(find.text('Outlet'), findsOneWidget);

    await tester.enterText(find.byKey(const Key('item-quantity')), '4');
    await tapKey(tester, 'item-save');
    final line = api.savedDrafts.values.single.lines.single;
    expect(line.catalogItemId, 'i1');
    expect(line.refKind, 'request_line');
    expect(line.refId, 'l1');
    expect(line.refCoverPath, 'o1/i1/p1.jpg');
    expect(line.quantity, '4');
    expect(line.photos, isEmpty, reason: 'the cover is for recognition, never a request photo');
    expect(find.byKey(const Key('line-cover')), findsOneWidget);
    expect(api.sent, isEmpty, reason: 'never sends by itself');
  });

  testWidgets('choosing another item from the list drops the history link', (tester) async {
    await openCompose(tester);
    await tapKey(tester, 'item-find-previous');
    await requestAgainFromHistory(tester);
    await tapKey(tester, 'item-change');
    await tapKey(tester, 'catalog-${pipe.id}');
    await tester.enterText(find.byKey(const Key('item-quantity')), '2');
    await tapKey(tester, 'item-save');
    final line = api.savedDrafts.values.single.lines.single;
    expect(line.catalogItemId, pipe.id);
    expect(line.refKind, isNull);
    expect(line.refId, isNull);
    expect(line.refCoverPath, isNull);
  });

  testWidgets('without Find Previous Item the link is not offered', (tester) async {
    await openCompose(tester, withHistory: false);
    expect(find.byKey(const Key('item-find-previous')), findsNothing);
  });

  testWidgets('standalone: from the Requests tab, a new draft opens on the picked item', (tester) async {
    useTallPhone(tester);
    final controller = RequestsController(api: api, now: () => DateTime.utc(2026, 10, 11, 2));
    await controller.refresh();
    await tester.pumpWidget(MaterialApp(
      theme: workMateTheme(),
      home: Scaffold(body: RequestsScreen(controller: controller, services: services())),
    ));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('find-previous')));
    await tester.pumpAndSettle();
    final screen = tester.widget<FindPreviousScreen>(find.byType(FindPreviousScreen));
    expect(screen.projects, {for (final d in api.refs.destinations) d.projectId: d.projectName}, reason: 'the worker\'s own projects');
    expect(screen.categories, ['plumbing']);

    await requestAgainFromHistory(tester);
    expect(find.byType(ComposeScreen, skipOffstage: false), findsOneWidget, reason: 'under the item editor');
    expect(find.byType(ItemEditorScreen), findsOneWidget, reason: 'opened on the item, for quantity and date');
    final draft = api.savedDrafts.values.single;
    expect(draft.destination, isNull, reason: 'the worker chooses the project and work');
    expect(draft.lines.single.refId, 'l1');
    expect(api.sent, isEmpty);
  });

  testWidgets('the Requests tab hides the button without Find Previous Item', (tester) async {
    useTallPhone(tester);
    final controller = RequestsController(api: api, now: () => DateTime.utc(2026, 10, 11, 2));
    await controller.refresh();
    await tester.pumpWidget(MaterialApp(
      theme: workMateTheme(),
      home: Scaffold(body: RequestsScreen(controller: controller, services: services(withHistory: false))),
    ));
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('find-previous')), findsNothing);
  });

  testWidgets('a double tap on Find previous item opens one search screen', (tester) async {
    useTallPhone(tester);
    final controller = RequestsController(api: api, now: () => DateTime.utc(2026, 10, 11, 2));
    await controller.refresh();
    await tester.pumpWidget(MaterialApp(
      theme: workMateTheme(),
      home: Scaffold(body: RequestsScreen(controller: controller, services: services())),
    ));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('find-previous')));
    await tester.tap(find.byKey(const Key('find-previous')));
    await tester.pumpAndSettle();
    expect(find.byType(FindPreviousScreen), findsOneWidget);
  });

  testWidgets("the picked line's editor does not open over one the worker already opened", (tester) async {
    useTallPhone(tester);
    final item = HistoryItem.fromJson(itemJson())!;
    final draft = api.newDraft().copyWith(lines: [DraftLine.fromHistory('x1', HistoryPick.of(item, item.entries.first))]);
    api.refsGate = Completer<void>();
    await tester.pumpWidget(MaterialApp(
      theme: workMateTheme(),
      home: ComposeScreen(draft: draft, services: services(), editLineOnOpen: 'x1', now: () => DateTime(2026, 10, 11)),
    ));
    await tester.pump();
    await tester.tap(find.byKey(const Key('line-0')));
    await tester.pumpAndSettle();
    api.refsGate!.complete();
    await tester.pumpAndSettle();
    expect(find.byType(ItemEditorScreen, skipOffstage: false), findsOneWidget);
  });
}
