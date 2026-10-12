import 'dart:async';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:workmate/history/data/history_api.dart';
import 'package:workmate/history/domain/history_models.dart';
import 'package:workmate/history/ui/find_previous_screen.dart';
import 'package:workmate/history/ui/history_copy.dart';
import 'package:workmate/history/ui/history_item_screen.dart';
import 'package:workmate/requests/domain/request_models.dart';
import 'package:workmate/ui/theme.dart';

import '../../attendance/fakes.dart' show useTallPhone;
import '../history_fakes.dart';
import '../history_samples.dart';

void main() {
  late FakeHistoryApi api;
  HistoryPick? picked;
  setUp(() {
    api = FakeHistoryApi();
    picked = null;
  });

  /// A host page that opens [screen] and keeps what it pops.
  Future<void> open(WidgetTester tester, Widget screen) async {
    useTallPhone(tester);
    await tester.pumpWidget(MaterialApp(
      theme: workMateTheme(),
      home: Builder(
        builder: (context) => Scaffold(
          body: TextButton(
            key: const Key('host-open'),
            onPressed: () async => picked = await Navigator.of(context).push<HistoryPick>(MaterialPageRoute(builder: (_) => screen)),
            child: const Text('open'),
          ),
        ),
      ),
    ));
    await tester.tap(find.byKey(const Key('host-open')));
    await tester.pumpAndSettle();
  }

  Future<void> openFind(WidgetTester tester) => open(
      tester,
      FindPreviousScreen(
        history: api,
        projects: const {'f1': 'Barlin Residence', 'f2': 'Santos Townhouse'},
        categories: const ['electrical'],
        now: () => DateTime(2026, 10, 11, 9),
      ));

  group('Find previous item', () {
    testWidgets('shows cards with the latest entry, and cleans the saved copy on open', (tester) async {
      await openFind(tester);
      expect(find.byKey(const Key('history-card-i1')), findsOneWidget);
      expect(find.text('Outlet'), findsOneWidget);
      expect(find.text('2-gang · pc · Omni'), findsOneWidget);
      expect(find.text('Latest: Requested · 3 Oct 2026 · Barlin Residence'), findsOneWidget);
      expect(api.refreshes, 1);
    });

    testWidgets('typing searches after a pause; filters narrow the next search', (tester) async {
      await openFind(tester);
      await tester.enterText(find.byKey(const Key('history-search')), 'saksakan');
      await tester.pump(const Duration(milliseconds: 500));
      await tester.pumpAndSettle();
      expect(api.queries.last.text, 'saksakan');

      await tester.tap(find.byKey(const Key('history-kind-tool')));
      await tester.pumpAndSettle();
      expect(api.queries.last.kind, ItemKind.tool);
      expect(api.queries.last.text, 'saksakan', reason: 'filters keep the words');

      await tester.tap(find.byKey(const Key('history-period-month')));
      await tester.pumpAndSettle();
      expect(api.queries.last.from, '2026-09-11', reason: 'a local calendar date, 30 days back');

      await tester.tap(find.byKey(const Key('history-kind-all')));
      await tester.pumpAndSettle();
      expect(api.queries.last.kind, isNull);
      expect(api.queries.last.from, '2026-09-11');
    });

    testWidgets('the project filter lists only the worker\'s own projects', (tester) async {
      await openFind(tester);
      await tester.tap(find.byKey(const Key('history-project')));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Santos Townhouse').last);
      await tester.pumpAndSettle();
      expect(api.queries.last.projectId, 'f2');
    });

    testWidgets('no matches says so', (tester) async {
      api.page = HistoryPage.fromJson({'items': [], 'has_more': false});
      await openFind(tester);
      expect(find.text(noMatchesText), findsOneWidget);
    });

    testWidgets('show more asks for the next page and appends it', (tester) async {
      api.page = HistoryPage.fromJson({'items': [cardJson()], 'has_more': true});
      await openFind(tester);
      api.page = HistoryPage.fromJson({'items': [cardJson(id: 'i2', name: 'Pipe')], 'has_more': false});
      await tester.tap(find.byKey(const Key('history-more')));
      await tester.pumpAndSettle();
      expect(find.byKey(const Key('history-card-i1')), findsOneWidget);
      expect(find.byKey(const Key('history-card-i2')), findsOneWidget);
      expect(find.byKey(const Key('history-more')), findsNothing);
    });

    testWidgets('offline with saved results shows them under a dated banner', (tester) async {
      api.page = HistoryPage(items: [HistoryCard.fromJson(cardJson())!], hasMore: false, savedAt: DateTime(2026, 10, 9, 10, 42));
      await openFind(tester);
      expect(find.byKey(const Key('history-saved-banner')), findsOneWidget);
      expect(find.textContaining('showing saved results from'), findsOneWidget);
      expect(find.byKey(const Key('history-card-i1')), findsOneWidget);
    });

    testWidgets('offline with nothing saved shows the bilingual notice and retries', (tester) async {
      api.error = const SocketException('no signal');
      await openFind(tester);
      expect(find.byKey(const Key('history-failure')), findsOneWidget);
      expect(find.byKey(const Key('history-card-i1')), findsNothing);
      api.error = null;
      await tester.tap(find.text('TRY AGAIN'));
      await tester.pumpAndSettle();
      expect(find.byKey(const Key('history-card-i1')), findsOneWidget);
    });

    testWidgets('an item no longer listed is marked on its card', (tester) async {
      api.page = HistoryPage.fromJson({'items': [cardJson(active: false)], 'has_more': false});
      await openFind(tester);
      expect(find.text('No longer listed'), findsOneWidget);
    });

    testWidgets('while a refined search runs, the old list shows it is refreshing and Show more is off', (tester) async {
      api.page = HistoryPage.fromJson({'items': [cardJson()], 'has_more': true});
      await openFind(tester);
      final gate = Completer<void>();
      api.gate = gate;
      await tester.tap(find.byKey(const Key('history-kind-tool')));
      await tester.pump();
      expect(find.byKey(const Key('history-refreshing')), findsOneWidget);
      expect(tester.widget<OutlinedButton>(find.byKey(const Key('history-more'))).onPressed, isNull);
      api.gate = null;
      gate.complete();
      await tester.pumpAndSettle();
      expect(find.byKey(const Key('history-refreshing')), findsNothing);
      expect(tester.widget<OutlinedButton>(find.byKey(const Key('history-more'))).onPressed, isNotNull);
    });

    testWidgets('a failed Show more says so and keeps the list', (tester) async {
      api.page = HistoryPage.fromJson({'items': [cardJson()], 'has_more': true});
      await openFind(tester);
      api.error = const SocketException('no signal');
      await tester.tap(find.byKey(const Key('history-more')));
      await tester.pumpAndSettle();
      expect(find.byKey(const Key('history-more-failed')), findsOneWidget);
      expect(find.byKey(const Key('history-card-i1')), findsOneWidget);
      expect(find.byKey(const Key('history-more')), findsOneWidget);
    });

    testWidgets('opening a card and choosing Request again returns the pick', (tester) async {
      await openFind(tester);
      await tester.tap(find.byKey(const Key('history-card-i1')));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const Key('history-request-again')));
      await tester.pumpAndSettle();
      expect(picked!.itemId, 'i1');
      expect(picked!.refKind, 'request_line');
      expect(picked!.refId, 'l1');
      expect(find.byKey(const Key('host-open')), findsOneWidget, reason: 'both screens closed');
    });
  });

  group('Item history', () {
    testWidgets('shows photos, details and each dated entry — never who asked', (tester) async {
      await open(tester, HistoryItemScreen(history: api, itemId: 'i1'));
      expect(find.byKey(const Key('history-photos')), findsOneWidget);
      expect(find.text('2 photos — swipe'), findsOneWidget);
      expect(find.text('Also called: saksakan'), findsOneWidget);
      expect(find.text('Requested'), findsOneWidget);
      expect(find.text('Historical reference'), findsOneWidget);
      expect(find.text('3 Oct 2026 · 6 pc'), findsOneWidget);
      expect(find.text('around Aug 2026'), findsOneWidget);
      expect(find.text('Kitchen outlets — old Messenger photo'), findsOneWidget);
    });

    testWidgets('Request again on a reference row links that reference', (tester) async {
      await open(tester, HistoryItemScreen(history: api, itemId: 'i1'));
      await tester.tap(find.byKey(const Key('history-again-r1')));
      await tester.pumpAndSettle();
      expect(picked!.refKind, 'reference');
      expect(picked!.refId, 'r1');
    });

    testWidgets('an item no longer listed cannot be requested again', (tester) async {
      api.items['i1'] = HistoryItemView(item: HistoryItem.fromJson(itemJson(active: false))!);
      await open(tester, HistoryItemScreen(history: api, itemId: 'i1'));
      expect(find.byKey(const Key('history-not-listed')), findsOneWidget);
      expect(find.byKey(const Key('history-request-again')), findsNothing);
      expect(find.byKey(const Key('history-again-l1')), findsNothing);
    });

    testWidgets('no photos shows a placeholder', (tester) async {
      api.items['i1'] = HistoryItemView(item: HistoryItem.fromJson(itemJson(photos: []))!);
      await open(tester, HistoryItemScreen(history: api, itemId: 'i1'));
      expect(find.text(noPhotoText), findsOneWidget);
      expect(find.byKey(const Key('history-photos')), findsNothing);
    });

    testWidgets('a saved copy is labelled with when it was saved', (tester) async {
      api.items['i1'] = HistoryItemView(item: HistoryItem.fromJson(itemJson())!, savedAt: DateTime(2026, 10, 9, 10, 42));
      await open(tester, HistoryItemScreen(history: api, itemId: 'i1'));
      expect(find.byKey(const Key('history-item-saved')), findsOneWidget);
    });

    testWidgets('history switched off shows the bilingual notice', (tester) async {
      api.items.remove('i1');
      await open(tester, HistoryItemScreen(history: api, itemId: 'i1'));
      expect(find.byKey(const Key('history-item-failure')), findsOneWidget);
      expect(find.textContaining('switched it off for this project'), findsOneWidget);
    });
  });
}
