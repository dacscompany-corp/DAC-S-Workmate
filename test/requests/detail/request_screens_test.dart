import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:workmate/requests/compose/compose_screen.dart';
import 'package:workmate/requests/data/requests_api.dart';
import 'package:workmate/requests/detail/request_sheet.dart';
import 'package:workmate/requests/domain/remote_request.dart';
import 'package:workmate/requests/domain/request_draft.dart';
import 'package:workmate/requests/domain/request_op.dart';
import 'package:workmate/requests/domain/request_status.dart';
import 'package:workmate/requests/list/request_openers.dart';
import 'package:workmate/requests/list/requests_controller.dart';
import 'package:workmate/requests/list/requests_screen.dart';
import 'package:workmate/requests/requests_services.dart';
import 'package:workmate/requests/ui/requests_copy.dart';
import 'package:workmate/requests/ui/sync_chip.dart';
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

  RequestEntry entry(Map<String, dynamic> doc, {SyncState state = SyncState.received, List<RequestOp> pending = const [], List<RequestOp> failed = const []}) =>
      RequestEntry(state: state, remote: RemoteRequest.fromJson(doc), pendingOps: pending, failedOps: failed);

  /// The request opens as a sheet over a plain page, as from the tab or Home.
  Future<void> showDetail(WidgetTester tester, String key) async {
    useTallPhone(tester);
    await controller.refresh();
    await tester.pumpWidget(MaterialApp(
      theme: workMateTheme(),
      home: Scaffold(
        body: Builder(
          builder: (context) => Center(
            child: TextButton(
              onPressed: () => openRequestEntry(context, controller, RequestsServices(api: api, takePhoto: (_) async => null), controller.entry(key)!),
              child: const Text('open'),
            ),
          ),
        ),
      ),
    ));
    await tester.tap(find.text('open'));
    await tester.pumpAndSettle();
  }

  testWidgets('a received request shows each portion\'s expected delivery', (tester) async {
    api.view = RequestsView(entries: [entry(requestDoc())]);
    await showDetail(tester, 'r1');
    expect(find.text('Santos Townhouse · Main Contract'), findsOneWidget);
    expect(find.descendant(of: find.byType(SyncChip), matching: find.text('Received')), findsOneWidget);
    expect(find.text('10 pc · Arranged · Expected Wed 14 Oct'), findsOneWidget);
    expect(find.text('2.5 pc · Expected Wed 21 Oct'), findsOneWidget);
    expect(find.text('Office is checking a change'), findsOneWidget);
    expect(find.textContaining('URGENT · by Wed 7 Oct'), findsOneWidget);
  });

  testWidgets('2B-b: what the office sent from stock shows on the line; nothing while it is 0', (tester) async {
    api.view = RequestsView(entries: [entry(requestDoc())]);
    await showDetail(tester, 'r1');
    expect(find.byKey(const Key('line-from-stock-l1')), findsNothing);
    final doc = requestDoc();
    (doc['lines'] as List).first['from_stock'] = 4;
    api.view = RequestsView(entries: [entry(doc)]);
    await controller.refresh();
    await tester.pumpAndSettle();
    expect(find.text('From stock: 4 pc · Galing sa stock'), findsOneWidget);
  });

  testWidgets('the requester changes a quantity; it shows as pending sync', (tester) async {
    api.view = RequestsView(entries: [entry(requestDoc())]);
    await showDetail(tester, 'r1');
    await tester.tap(find.byKey(const Key('change-l1')));
    await tester.pumpAndSettle();
    await tester.enterText(find.byKey(const Key('qty-field')), '8');
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('qty-save')));
    await tester.pumpAndSettle();
    expect(api.calls, ['quantity:l1:8']);

    api.view = RequestsView(entries: [
      entry(requestDoc(), state: SyncState.pending, pending: [
        RequestOp(opId: 'o', workerId: 'u1', kind: OpKind.quantity, createdAt: DateTime.utc(2026), lineId: 'l1', body: const {'quantity': 8}),
      ]),
    ]);
    await controller.refresh();
    await tester.pumpAndSettle();
    expect(find.text('Changing to 8 pc · Pending sync'), findsOneWidget);
  });

  testWidgets('cancelling asks first', (tester) async {
    api.view = RequestsView(entries: [entry(requestDoc())]);
    await showDetail(tester, 'r1');
    await tester.tap(find.byKey(const Key('cancel-l1')));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Keep'));
    await tester.pumpAndSettle();
    expect(api.calls, isEmpty);
    await tester.tap(find.byKey(const Key('cancel-request')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('confirm-cancel')));
    await tester.pumpAndSettle();
    expect(api.calls, ['cancelRequest:r1']);
  });

  testWidgets('a team member\'s request is read-only for the leader', (tester) async {
    api.view = RequestsView(entries: [entry(requestDoc(mine: false))]);
    await showDetail(tester, 'r1');
    expect(find.textContaining('From Juan dela Cruz'), findsOneWidget);
    expect(find.byKey(const Key('change-l1')), findsNothing);
    expect(find.byKey(const Key('cancel-request')), findsNothing);
  });

  testWidgets('a refused change is explained in both languages and can be dismissed', (tester) async {
    final op = RequestOp(
      opId: 'o9',
      workerId: 'u1',
      kind: OpKind.quantity,
      createdAt: DateTime.utc(2026),
      lineId: 'l1',
      body: const {'quantity': 3},
      lastError: 'lineClosed',
      failedPermanently: true,
    );
    api.view = RequestsView(entries: [entry(requestDoc(), state: SyncState.failed, failed: [op])]);
    await showDetail(tester, 'r1');
    expect(find.text('This item is already cancelled.'), findsOneWidget);
    expect(find.text('Naka-cancel na ang item na ito.'), findsOneWidget);
    expect(find.textContaining('Changing PVC pipe to 3'), findsOneWidget);
    await tester.tap(find.text('Dismiss · Isara'));
    await tester.pumpAndSettle();
    expect(api.calls, ['dismiss:o9']);
  });

  testWidgets('the list shows each state and opens a draft in the editor', (tester) async {
    useTallPhone(tester);
    api.savedDrafts['d7'] = RequestDraft(id: 'd7', createdAt: DateTime.utc(2026, 10, 5), destination: site);
    api.view = RequestsView(entries: [entry(requestDoc()), entry(requestDoc(id: 'r2'), state: SyncState.pending)]);
    await controller.refresh();
    await tester.pumpWidget(MaterialApp(
      theme: workMateTheme(),
      home: Scaffold(body: RequestsScreen(controller: controller, services: RequestsServices(api: api, takePhoto: (_) async => null))),
    ));
    await tester.pumpAndSettle();
    expect(find.text('Draft'), findsOneWidget);
    expect(find.text('Received'), findsOneWidget);
    expect(find.text('Pending sync'), findsWidgets);
    await tester.ensureVisible(find.byKey(const Key('filter-pending')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('filter-pending')));
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('entry-r2')), findsOneWidget);
    expect(find.byKey(const Key('entry-r1')), findsNothing);
    await tester.ensureVisible(find.byKey(const Key('filter-all')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('filter-all')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('entry-d7')));
    await tester.pumpAndSettle();
    expect(find.text('New request'), findsWidgets);
    expect(find.byKey(const Key('send-request')), findsOneWidget);
  });

  testWidgets('a cancelled request shows Cancelled on the list, not Received', (tester) async {
    useTallPhone(tester);
    api.view = RequestsView(entries: [
      entry(requestDoc(status: 'cancelled'), state: remoteState(RemoteRequest.fromJson(requestDoc(status: 'cancelled')), pending: false, failed: false)),
    ]);
    await controller.refresh();
    await tester.pumpWidget(MaterialApp(
      theme: workMateTheme(),
      home: Scaffold(body: RequestsScreen(controller: controller, services: RequestsServices(api: api, takePhoto: (_) async => null))),
    ));
    await tester.pumpAndSettle();
    final card = find.byKey(const Key('entry-r1'));
    expect(find.descendant(of: find.descendant(of: card, matching: find.byType(SyncChip)), matching: find.text('Cancelled')), findsOneWidget);
    expect(find.descendant(of: card, matching: find.text('Cancelled')), findsNWidgets(2), reason: 'the pill and the status line');
    expect(find.text('Received'), findsNothing);
  });

  testWidgets('the sheet: pill and meta, the status box with Saved · Sent · Received, then ITEMS', (tester) async {
    api.view = RequestsView(entries: [entry(requestDoc())]);
    await showDetail(tester, 'r1');
    expect(find.byKey(const Key('request-sheet')), findsOneWidget);
    expect(find.text('Santos Townhouse · Main Contract'), findsOneWidget, reason: 'the title');
    expect(find.text('Just me · Received 5 Oct, 11:00 AM'), findsOneWidget);
    expect(find.byKey(const Key('request-status')), findsOneWidget);
    for (final label in ['Saved', 'Sent']) {
      expect(find.text(label), findsOneWidget);
    }
    expect(find.text('Received by the office'), findsOneWidget);
    expect(find.text('Back gate'), findsOneWidget, reason: 'the note');
    expect(find.text('ITEMS (1)'), findsOneWidget);
    expect(find.byKey(const Key('line-l1')), findsOneWidget);
    expect(find.byKey(const Key('cancel-request')), findsOneWidget, reason: 'in the footer');
  });

  testWidgets('a request still on the phone shows the saved-on-phone line and no cancel button', (tester) async {
    api.view = RequestsView(entries: [
      RequestEntry(state: SyncState.pending, draft: RequestDraft(id: 'd3', createdAt: DateTime.utc(2026, 10, 5), destination: site)),
    ]);
    await showDetail(tester, 'd3');
    expect(find.text('Santos Townhouse · Main Contract'), findsOneWidget);
    expect(find.text('Saved on this phone. It is sent as soon as there is signal.'), findsOneWidget);
    expect(find.text('Saved on this phone · sends when there is signal'), findsOneWidget, reason: 'the status line');
    expect(find.text('ITEMS (0)'), findsOneWidget);
    expect(find.byKey(const Key('cancel-request')), findsNothing);
  });

  testWidgets('dragging the sheet down closes it; a request that left the list says so', (tester) async {
    api.view = RequestsView(entries: [entry(requestDoc())]);
    await showDetail(tester, 'r1');
    api.view = const RequestsView(entries: []);
    await controller.refresh();
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('request-gone')), findsOneWidget);
    expect(find.text('This request is no longer on the list.'), findsOneWidget);
    await tester.timedDrag(find.byKey(const Key('wm-sheet-handle')), const Offset(0, 160), const Duration(milliseconds: 800));
    await tester.pumpAndSettle();
    expect(find.byType(RequestSheet), findsNothing);
    expect(api.calls, isEmpty);
  });

  group('a refused draft back to editing', () {
    final draft = RequestDraft(id: 'd5', createdAt: DateTime.utc(2026, 10, 5), destination: site);
    final refusedSubmit = RequestOp(
      opId: 's5',
      workerId: 'u1',
      kind: OpKind.submit,
      createdAt: DateTime.utc(2026, 10, 5),
      draftId: 'd5',
      lastError: 'destinationClosed',
      failedPermanently: true,
    );

    Future<void> openRefused(WidgetTester tester) async {
      useTallPhone(tester);
      api.view = RequestsView(entries: [RequestEntry(state: SyncState.failed, draft: draft, failedOps: [refusedSubmit])]);
      await controller.refresh();
      await tester.pumpWidget(MaterialApp(
        theme: workMateTheme(),
        home: Scaffold(body: RequestsScreen(controller: controller, services: RequestsServices(api: api, takePhoto: (_) async => null))),
      ));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const Key('entry-d5')));
      await tester.pumpAndSettle();
      await tester.tap(find.text(backToDraftsLabel));
      await tester.pumpAndSettle();
    }

    testWidgets('refused by the phone: the editor does not open on a queued draft', (tester) async {
      api.returnToDraftsResult = false;
      await openRefused(tester);
      expect(api.calls, ['returnToDrafts:d5']);
      expect(find.byType(ComposeScreen), findsNothing);
      expect(find.byType(RequestSheet), findsOneWidget);
    });

    testWidgets('accepted: the draft opens in the editor', (tester) async {
      await openRefused(tester);
      expect(find.byType(ComposeScreen), findsOneWidget);
      expect(find.byType(RequestSheet, skipOffstage: false), findsNothing, reason: 'the sheet closed before the editor opened');
    });
  });

  testWidgets('New request then straight back leaves no empty draft', (tester) async {
    useTallPhone(tester);
    await controller.refresh();
    await tester.pumpWidget(MaterialApp(
      theme: workMateTheme(),
      home: Scaffold(body: RequestsScreen(controller: controller, services: RequestsServices(api: api, takePhoto: (_) async => null))),
    ));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('new-request')));
    await tester.pumpAndSettle();
    await tester.binding.handlePopRoute();
    await tester.pumpAndSettle();
    expect(api.savedDrafts, isEmpty);
    expect(find.byKey(const Key('entry-d1')), findsNothing);
  });
}
