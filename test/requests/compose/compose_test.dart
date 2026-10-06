import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:workmate/requests/compose/compose_controller.dart';
import 'package:workmate/requests/compose/compose_screen.dart';
import 'package:workmate/requests/compose/item_editor_screen.dart';
import 'package:workmate/requests/data/requests_api.dart';
import 'package:workmate/requests/domain/request_draft.dart';
import 'package:workmate/requests/domain/request_failure.dart';
import 'package:workmate/requests/domain/request_models.dart';
import 'package:workmate/requests/requests_services.dart';
import 'package:workmate/ui/theme.dart';

import '../../attendance/fakes.dart' show useTallPhone;
import '../request_fakes.dart';

/// Scrolls the item editor's list until [key] is on screen, then taps it.
Future<void> tapKey(WidgetTester tester, String key) async {
  final f = find.byKey(Key(key));
  final list = find.descendant(of: find.byType(ItemEditorScreen), matching: find.byType(Scrollable)).first;
  await tester.scrollUntilVisible(f, 200, scrollable: list);
  await tester.ensureVisible(f);
  await tester.pumpAndSettle();
  await tester.tap(f);
  await tester.pumpAndSettle();
}

void main() {
  late FakeRequestsApi api;
  setUp(() => api = FakeRequestsApi());

  group('ComposeController', () {
    test('every change is saved on the phone at once', () async {
      final c = ComposeController(api: api, draft: api.newDraft());
      await c.load();
      await c.setDestination(fence);
      await c.putLine(DraftLine.fromCatalog('x1', pipe).copyWith(quantity: '4'));
      expect(api.savedDrafts.values.single.destination, fence);
      expect(api.savedDrafts.values.single.lines.single.quantity, '4');
    });

    test('changing the team clears members of the old team', () async {
      final c = ComposeController(api: api, draft: api.newDraft());
      await c.load();
      await c.setTeam(masonry);
      expect(c.iLead, isTrue);
      await c.putLine(DraftLine.fromCatalog('x1', pipe).copyWith(quantity: '4', memberId: 'u2', memberName: 'Pedro'));
      await c.setTeam(null);
      expect(c.draft.lines.single.memberId, isNull);
      expect(c.iLead, isFalse);
    });

    test('a team the worker does not lead keeps no member', () async {
      final c = ComposeController(api: api, draft: api.newDraft());
      await c.load();
      await c.setTeam(masonry);
      await c.putLine(DraftLine.fromCatalog('x1', pipe).copyWith(quantity: '4', memberId: 'u2', memberName: 'Pedro'));
      await c.setTeam(const MyTeam(id: 't2', name: 'Masonry B', iLead: false, members: [TeamMember(id: 'u2', name: 'Pedro')]));
      expect(c.draft.lines.single.memberId, isNull);
    });

    test('Send checks first and names what to fix', () async {
      final c = ComposeController(api: api, draft: api.newDraft());
      await c.load();
      expect(await c.send(), isFalse);
      expect(c.issues, contains(const DraftIssue(DraftIssueKind.noDestination)));
      expect(api.sent, isEmpty);
      await c.setDestination(site);
      expect(c.issues, isEmpty, reason: 'any change clears the old list');
      await c.putLine(DraftLine.fromCatalog('x1', pipe).copyWith(quantity: '10'));
      expect(await c.send(), isTrue);
      expect(api.sent.single.lines.single.catalogItemId, 'c1');
    });

    test('a removed item takes its photos with it', () async {
      final c = ComposeController(api: api, draft: api.newDraft());
      await c.putLine(DraftLine.fromCatalog('x1', pipe).copyWith(photos: ['/p/a.jpg']));
      await c.removeLine('x1');
      expect(c.draft.lines, isEmpty);
      expect(api.discarded, ['/p/a.jpg']);
    });

    test('a destination the server no longer offers is flagged (fresh lists only)', () async {
      final c = ComposeController(api: api, draft: api.newDraft().copyWith(destination: site));
      api.refs = const RequestReferences(destinations: [fence], teams: [], catalog: []);
      await c.load();
      expect(c.destinationClosed, isTrue);
      api.refs = const RequestReferences(destinations: [fence], teams: [], catalog: [], fromCache: true);
      await c.load();
      expect(c.destinationClosed, isFalse);
    });

    test('a team is cleared only from a fresh list, never from a cached one', () async {
      final d = api.newDraft().copyWith(teamId: 't1', teamName: 'Masonry A');
      api.refs = const RequestReferences(destinations: [site], teams: [], catalog: [], fromCache: true);
      final c = ComposeController(api: api, draft: d);
      await c.load();
      expect(c.draft.teamId, 't1', reason: 'an old copy may simply be old');
      api.refs = const RequestReferences(destinations: [site], teams: [], catalog: []);
      await c.load();
      expect(c.draft.teamId, isNull);
      expect(api.savedDrafts[d.id]!.teamId, isNull);
    });

    test('no lists and no copy: a failure to show, with retry', () async {
      api.refsError = StateError('AUTH_REQUIRED');
      final c = ComposeController(api: api, draft: api.newDraft());
      await c.load();
      expect(c.refsFailure, RequestFailure.sessionExpired);
    });
  });

  group('ComposeScreen', () {
    Future<NavigatorState> show(WidgetTester tester, RequestDraft draft, List<Object?> popped) async {
      useTallPhone(tester);
      final nav = GlobalKey<NavigatorState>();
      await tester.pumpWidget(MaterialApp(
        navigatorKey: nav,
        theme: workMateTheme(),
        home: Builder(
          builder: (context) => Scaffold(
            body: TextButton(
              onPressed: () async => popped.add(await Navigator.of(context).push<bool>(MaterialPageRoute(
                builder: (_) => ComposeScreen(
                  draft: draft,
                  services: RequestsServices(api: api, takePhoto: (_) async => '/raw/shot.jpg'),
                  now: () => DateTime(2026, 10, 5),
                ),
              ))),
              child: const Text('open'),
            ),
          ),
        ),
      ));
      await tester.tap(find.text('open'));
      await tester.pumpAndSettle();
      return nav.currentState!;
    }

    testWidgets('project → team → an item from the list → Send', (tester) async {
      final popped = <Object?>[];
      await show(tester, api.newDraft(), popped);
      await tester.tap(find.byKey(const Key('choose-destination')));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const Key('dest-f9')));
      await tester.pumpAndSettle();
      expect(find.text('AW-03 Fence'), findsOneWidget);

      await tester.tap(find.byKey(const Key('team-t1')));
      await tester.pumpAndSettle();

      await tester.tap(find.byKey(const Key('add-item')));
      await tester.pumpAndSettle();
      await tester.enterText(find.byKey(const Key('item-search')), 'pvc');
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const Key('catalog-c1')));
      await tester.pumpAndSettle();
      await tester.enterText(find.byKey(const Key('item-quantity')), '12');
      await tester.tap(find.byKey(const Key('item-member')));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Pedro').last);
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const Key('item-add-photo')));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const Key('item-save')));
      await tester.pumpAndSettle();

      expect(find.text('PVC pipe'), findsOneWidget);
      expect(find.textContaining('For Pedro'), findsOneWidget);
      await tester.tap(find.byKey(const Key('send-request')));
      await tester.pumpAndSettle();

      expect(popped, [true]);
      final sent = api.sent.single;
      expect(sent.destination, fence);
      expect(sent.teamId, 't1');
      expect(sent.lines.single.quantity, '12');
      expect(sent.lines.single.memberId, 'u2');
      expect(sent.lines.single.photos.single, startsWith('/kept/'));
    });

    testWidgets('an unlisted item is described, and urgency needs a reason and a date', (tester) async {
      final popped = <Object?>[];
      await show(tester, api.newDraft().copyWith(destination: site), popped);
      await tester.tap(find.byKey(const Key('add-item')));
      await tester.pumpAndSettle();
      await tester.enterText(find.byKey(const Key('item-search')), 'elbow 45');
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const Key('describe-item')));
      await tester.pumpAndSettle();
      expect(tester.widget<TextField>(find.byKey(const Key('item-name'))).controller!.text, 'elbow 45');
      await tester.enterText(find.byKey(const Key('item-unit')), 'pc');
      await tester.enterText(find.byKey(const Key('item-quantity')), '3');
      await tapKey(tester, 'item-urgent');
      await tapKey(tester, 'item-save');
      expect(find.text('Say why it is urgent.'), findsOneWidget);
      expect(find.text('Pick the date it is needed by.'), findsOneWidget);
      await tester.enterText(find.byKey(const Key('item-reason')), 'Leak at the kitchen');
      await tapKey(tester, 'item-needed-by');
      await tester.tap(find.text('OK'));
      await tester.pumpAndSettle();
      await tapKey(tester, 'item-save');
      expect(find.textContaining('Not in the list'), findsOneWidget);
      expect(find.textContaining('URGENT'), findsOneWidget);
      final line = api.savedDrafts.values.single.lines.single;
      expect(line.catalogItemId, isNull);
      expect(line.neededBy, '2026-10-05');
      expect(line.kind, ItemKind.material);
    });

    testWidgets('Send with nothing chosen says what is missing', (tester) async {
      await show(tester, api.newDraft(), []);
      await tester.tap(find.byKey(const Key('send-request')));
      await tester.pumpAndSettle();
      expect(find.text('Choose the project and the work.'), findsOneWidget);
      expect(find.text('Add at least one item.'), findsOneWidget);
      expect(api.sent, isEmpty);
    });

    testWidgets('Send on an untouched New request stores no empty draft', (tester) async {
      await show(tester, api.newDraft(), []);
      await tester.tap(find.byKey(const Key('send-request')));
      await tester.pumpAndSettle();
      expect(find.text('Choose the project and the work.'), findsOneWidget);
      expect(api.savedDrafts, isEmpty);
    });

    testWidgets('a note that cannot be saved raises no error on screen', (tester) async {
      api.saveError = StateError('disk full');
      await show(tester, api.newDraft(), []);
      await tester.enterText(find.byKey(const Key('request-note')), 'Back gate');
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull);
      expect(find.text('Back gate'), findsOneWidget, reason: 'what was typed stays in the field');
    });

    testWidgets('a team no longer in a FRESH list is cleared, members too', (tester) async {
      final d = api.newDraft().copyWith(
        destination: site,
        teamId: 't1',
        teamName: 'Masonry A',
        lines: [DraftLine.fromCatalog('x1', pipe).copyWith(quantity: '2', memberId: 'u2', memberName: 'Pedro')],
      );
      await api.saveDraft(d);
      api.refs = const RequestReferences(destinations: [site, fence], teams: [], catalog: [pipe, drill]);
      await show(tester, d, []);
      final stored = api.savedDrafts[d.id]!;
      expect(stored.teamId, isNull);
      expect(stored.teamName, isNull);
      expect(stored.lines.single.memberId, isNull);
      expect(tester.widget<ChoiceChip>(find.byKey(const Key('team-none'))).selected, isTrue);
    });

    testWidgets('a member who left the team opens as "The team", without an assert', (tester) async {
      final d = api.newDraft().copyWith(
        destination: site,
        teamId: 't1',
        teamName: 'Masonry A',
        lines: [DraftLine.fromCatalog('x1', pipe).copyWith(quantity: '2', memberId: 'u9', memberName: 'Gone')],
      );
      await api.saveDraft(d);
      await show(tester, d, []);
      await tester.tap(find.byKey(const Key('line-0')));
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull);
      expect(find.byKey(const Key('item-member')), findsOneWidget);
      expect(find.text('The team'), findsOneWidget);
    });

    testWidgets('removing an item asks first: Keep keeps it, Remove removes it', (tester) async {
      final d = api.newDraft().copyWith(destination: site, lines: [DraftLine.fromCatalog('x1', pipe).copyWith(quantity: '2', photos: ['/p/a.jpg'])]);
      await api.saveDraft(d);
      await show(tester, d, []);
      await tester.tap(find.byKey(const Key('line-0')));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const Key('item-remove')));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const Key('item-remove-keep')));
      await tester.pumpAndSettle();
      expect(find.byType(ItemEditorScreen), findsOneWidget, reason: 'still editing');
      expect(api.discarded, isEmpty);
      await tester.tap(find.byKey(const Key('item-remove')));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const Key('item-remove-confirm')));
      await tester.pumpAndSettle();
      expect(find.byType(ItemEditorScreen), findsNothing);
      expect(api.savedDrafts[d.id]!.lines, isEmpty);
      expect(api.discarded, ['/p/a.jpg']);
    });

    testWidgets('no project open: the worker is told, not shown an empty picker', (tester) async {
      api.refs = const RequestReferences(destinations: [], teams: [], catalog: []);
      await show(tester, api.newDraft(), []);
      expect(find.textContaining('No project is open for requests'), findsOneWidget);
    });

    testWidgets('the note is saved as it is typed, and a deleted draft stays deleted', (tester) async {
      final d = api.newDraft();
      await api.saveDraft(d);
      await show(tester, d, []);
      await tester.enterText(find.byKey(const Key('request-note')), 'Back gate');
      await tester.pump();
      expect(api.savedDrafts[d.id]!.note, 'Back gate');
      await tester.tap(find.byKey(const Key('draft-delete')));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Delete'));
      await tester.pumpAndSettle();
      expect(api.savedDrafts, isEmpty);
    });

    testWidgets('a photo that cannot be kept is explained in both languages', (tester) async {
      api.keepError = const FileSystemException('disk full');
      await show(tester, api.newDraft().copyWith(destination: site), []);
      await tester.tap(find.byKey(const Key('add-item')));
      await tester.pumpAndSettle();
      await tapKey(tester, 'item-add-photo');
      expect(find.text('The photo could not be kept. Try again.'), findsOneWidget);
      expect(find.text('Hindi naitabi ang litrato. Subukan ulit.'), findsOneWidget);
    });

    testWidgets('a photo taken for an item that is then abandoned is deleted', (tester) async {
      await show(tester, api.newDraft().copyWith(destination: site), []);
      await tester.tap(find.byKey(const Key('add-item')));
      await tester.pumpAndSettle();
      await tapKey(tester, 'item-add-photo');
      expect(api.discarded, isEmpty);
      await tester.pageBack();
      await tester.pumpAndSettle();
      expect(api.discarded.single, startsWith('/kept/'));
    });
  });
}
