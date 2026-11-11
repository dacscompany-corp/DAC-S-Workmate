import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:workmate/home/needs_you.dart';
import 'package:workmate/home/needs_you_card.dart';
import 'package:workmate/home/shortcut_row.dart';
import 'package:workmate/home/sync_badge.dart';
import 'package:workmate/home/sync_summary.dart';
import 'package:workmate/ui/theme.dart';

import '../attendance/fakes.dart' show useTallPhone;

Widget wrap(Widget w) => MaterialApp(theme: workMateTheme(), home: Scaffold(body: ListView(padding: const EdgeInsets.all(20), children: [w])));

/// Animations off, as the phone's "remove animations" setting does: a
/// waiting badge's blinking dot then never holds pumpAndSettle open.
Widget still(Widget w) => MaterialApp(
      theme: workMateTheme(),
      builder: (context, child) => MediaQuery(data: MediaQuery.of(context).copyWith(disableAnimations: true), child: child!),
      home: Scaffold(body: Center(child: w)),
    );

NeedsRow task(int i) => NeedsRow(kind: NeedsKind.read, title: 'Task $i', line: 'New task · read it first', action: 'Read', target: 't$i');

void main() {
  testWidgets('each row has its own button, and a tap opens that row', (tester) async {
    useTallPhone(tester);
    final opened = <String>[];
    await tester.pumpWidget(wrap(NeedsYouCard(
      needs: NeedsYou(allRead: true, rows: [
        task(1),
        const NeedsRow(kind: NeedsKind.finishDraft, title: 'Draft · Site', line: '2 items · not sent yet', action: 'Finish', target: 'd1'),
      ]),
      onOpen: (r) => opened.add(r.id),
    )));
    expect(find.text('NEEDS YOU'), findsOneWidget);
    expect(find.descendant(of: find.byKey(const Key('needs-count')), matching: find.text('2')), findsOneWidget);
    expect(find.text('Read'), findsOneWidget);
    expect(find.text('Finish'), findsOneWidget);
    await tester.tap(find.byKey(const Key('needs-finishDraft-d1')));
    expect(opened, ['finishDraft-d1']);
  });

  testWidgets('six rows: five, then "Show 1 more", then "Show fewer"; the count is always six', (tester) async {
    useTallPhone(tester);
    await tester.pumpWidget(wrap(NeedsYouCard(needs: NeedsYou(allRead: true, rows: [for (var i = 1; i <= 6; i++) task(i)]), onOpen: (_) {})));
    expect(find.text('Task 5'), findsOneWidget);
    expect(find.text('Task 6'), findsNothing);
    expect(find.descendant(of: find.byKey(const Key('needs-count')), matching: find.text('6')), findsOneWidget);
    await tester.tap(find.text('Show 1 more'));
    await tester.pump();
    expect(find.text('Task 6'), findsOneWidget);
    await tester.tap(find.text('Show fewer'));
    await tester.pump();
    expect(find.text('Task 6'), findsNothing);
  });

  testWidgets('opening a row folds the list back to five', (tester) async {
    useTallPhone(tester);
    await tester.pumpWidget(wrap(NeedsYouCard(needs: NeedsYou(allRead: true, rows: [for (var i = 1; i <= 6; i++) task(i)]), onOpen: (_) {})));
    await tester.tap(find.text('Show 1 more'));
    await tester.pump();
    await tester.tap(find.byKey(const Key('needs-read-t6')));
    await tester.pump();
    expect(find.text('Task 6'), findsNothing);
  });

  testWidgets('nothing to do and every source read: all caught up, and no count', (tester) async {
    await tester.pumpWidget(wrap(NeedsYouCard(needs: const NeedsYou(allRead: true, rows: []), onOpen: (_) {})));
    expect(find.text('You are all caught up'), findsOneWidget);
    expect(find.text('Nothing needs you right now.'), findsOneWidget);
    expect(find.byKey(const Key('needs-count')), findsNothing);
  });

  testWidgets('nothing known yet: the whole block is off Home', (tester) async {
    await tester.pumpWidget(wrap(NeedsYouCard(needs: const NeedsYou(allRead: false, rows: []), onOpen: (_) {})));
    expect(find.text('NEEDS YOU'), findsNothing);
    expect(find.text('You are all caught up'), findsNothing);
  });

  testWidgets('the next delivery line (moved from the old Requests card)', (tester) async {
    await tester.pumpWidget(wrap(const NextDeliveryLine(iso: '2026-10-14')));
    expect(find.text('Next delivery Wed 14 Oct'), findsOneWidget);
  });

  testWidgets('shortcuts: the ones shown sit side by side and share the row, a tap opens, no tile at all shows nothing',
      (tester) async {
    useTallPhone(tester);
    var taps = 0;
    await tester.pumpWidget(wrap(ShortcutRow(tiles: [
      ShortcutTile(id: 'tools', icon: Icons.handyman_outlined, label: 'My tools', onTap: () {}),
      null, // no agreements: no empty spot is kept for it (owner decision after the 11 Nov pilot)
      ShortcutTile(id: 'notes', icon: Icons.forum_outlined, label: 'Meeting notes', onTap: () => taps++),
      ShortcutTile(id: 'new-request', icon: Icons.add, label: 'New request', onTap: () {}),
    ])));
    final row = tester.getRect(find.byType(ShortcutRow));
    final tools = tester.getRect(find.byKey(const Key('shortcut-tools')));
    final notes = tester.getRect(find.byKey(const Key('shortcut-notes')));
    final request = tester.getRect(find.byKey(const Key('shortcut-new-request')));
    expect(notes.left - tools.right, moreOrLessEquals(4), reason: 'no gap where My agreements would be');
    expect(request.left - notes.right, moreOrLessEquals(4));
    expect([tools.width, notes.width, request.width], everyElement(moreOrLessEquals((row.width - 8) / 3)),
        reason: 'three shortcuts share the row equally');
    expect([tools.left, request.right], [moreOrLessEquals(row.left), moreOrLessEquals(row.right)]);
    await tester.tap(find.byKey(const Key('shortcut-notes')));
    expect(taps, 1);
    await tester.pumpWidget(wrap(const ShortcutRow(tiles: [null, null, null, null])));
    expect(find.byType(InkWell), findsNothing);
  });

  testWidgets('the sync badge: All sent, N not sent yet, or nothing at all', (tester) async {
    await tester.pumpWidget(still(SyncBadge(summary: syncSummary([0, 0, 0, 0]))));
    expect(find.text('All sent'), findsOneWidget);
    await tester.pumpWidget(still(SyncBadge(summary: syncSummary([1, 0, 0, 0]))));
    await tester.pumpAndSettle();
    expect(find.text('1 not sent yet'), findsOneWidget);
    await tester.pumpWidget(still(SyncBadge(summary: syncSummary([0, null, 0, 0]))));
    expect(find.text('All sent'), findsNothing);
    expect(find.textContaining('not sent yet'), findsNothing);
  });

  testWidgets('the waiting dot blinks when animations are allowed', (tester) async {
    await tester.pumpWidget(MaterialApp(home: Scaffold(body: Center(child: SyncBadge(summary: syncSummary([2, 0, 0, 0]))))));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 700));
    final fade = tester.widget<FadeTransition>(
        find.descendant(of: find.byKey(const Key('sync-not-sent')), matching: find.byType(FadeTransition)));
    expect(fade.opacity.value, lessThan(1));
  });
}
