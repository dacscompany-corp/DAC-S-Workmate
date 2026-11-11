import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:workmate/ui/theme.dart';
import 'package:workmate/ui/wm_sheet.dart';

import '../attendance/fakes.dart' show useTallPhone;

void main() {
  late int sends;

  Widget host({Widget? footer}) => MaterialApp(
        theme: workMateTheme(),
        home: Scaffold(
          body: Builder(
            builder: (context) => Center(
              child: TextButton(
                onPressed: () => showWmSheet<void>(
                  context,
                  builder: (_) => WmSheetFrame(title: 'Sheet', subtitle: 'Tagalog line', footer: footer, children: const [Text('Body')]),
                ),
                child: const Text('open'),
              ),
            ),
          ),
        ),
      );

  Future<void> open(WidgetTester tester, {Widget? footer}) async {
    useTallPhone(tester);
    sends = 0;
    await tester.pumpWidget(host(footer: footer));
    await tester.tap(find.text('open'));
    await tester.pumpAndSettle();
    expect(find.text('Body'), findsOneWidget);
  }

  final handle = find.byKey(const Key('wm-sheet-handle'));

  testWidgets('title and Tagalog subtitle', (tester) async {
    await open(tester);
    expect(find.text('Sheet'), findsOneWidget);
    expect(find.text('Tagalog line'), findsOneWidget);
  });

  testWidgets('a short, slow drag springs back', (tester) async {
    await open(tester);
    await tester.timedDrag(handle, const Offset(0, 60), const Duration(milliseconds: 800));
    await tester.pumpAndSettle();
    expect(find.text('Body'), findsOneWidget);
  });

  testWidgets('dragged down past 110 px, it closes', (tester) async {
    await open(tester);
    await tester.timedDrag(handle, const Offset(0, 160), const Duration(milliseconds: 800));
    await tester.pumpAndSettle();
    expect(find.text('Body'), findsNothing);
  });

  testWidgets('a quick flick down closes it', (tester) async {
    await open(tester);
    await tester.fling(handle, const Offset(0, 80), 1500);
    await tester.pumpAndSettle();
    expect(find.text('Body'), findsNothing);
  });

  testWidgets('the × closes it', (tester) async {
    await open(tester);
    await tester.tap(find.byKey(const Key('wm-sheet-close')));
    await tester.pumpAndSettle();
    expect(find.text('Body'), findsNothing);
  });

  testWidgets('Android Back closes it', (tester) async {
    await open(tester);
    await tester.binding.handlePopRoute();
    await tester.pumpAndSettle();
    expect(find.text('Body'), findsNothing);
  });

  testWidgets('a tap outside closes it', (tester) async {
    await open(tester);
    await tester.tapAt(const Offset(20, 20));
    await tester.pumpAndSettle();
    expect(find.text('Body'), findsNothing);
  });

  testWidgets('the footer button, with its Tagalog line, does its job', (tester) async {
    await open(tester, footer: WmSheetButton(label: 'SEND', icon: Icons.send, tagalog: 'Ipadala', onPressed: () => sends++));
    expect(find.text('Ipadala'), findsOneWidget);
    await tester.tap(find.text('SEND'));
    expect(sends, 1);
  });

  testWidgets('a footer button with no action does nothing', (tester) async {
    await open(tester, footer: const WmSheetButton(label: 'SEND', icon: Icons.send, onPressed: null));
    expect(tester.widget<FilledButton>(find.byType(FilledButton)).onPressed, isNull);
  });

  testWidgets('a drag that is cancelled springs back', (tester) async {
    await open(tester);
    final before = tester.getTopLeft(handle);
    final g = await tester.startGesture(tester.getCenter(handle));
    for (var i = 0; i < 4; i++) {
      await g.moveBy(const Offset(0, 20));
      await tester.pump();
    }
    await g.cancel();
    await tester.pumpAndSettle();
    expect(find.text('Body'), findsOneWidget);
    expect(tester.getTopLeft(handle), before);
  });

  testWidgets('a close the sheet refuses (PopScope) springs back', (tester) async {
    useTallPhone(tester);
    await tester.pumpWidget(MaterialApp(
      theme: workMateTheme(),
      home: Scaffold(
        body: Builder(
          builder: (context) => Center(
            child: TextButton(
              onPressed: () => showWmSheet<void>(
                context,
                builder: (_) => const PopScope(
                  canPop: false,
                  child: WmSheetFrame(title: 'Sheet', children: [Text('Body')]),
                ),
              ),
              child: const Text('open'),
            ),
          ),
        ),
      ),
    ));
    await tester.tap(find.text('open'));
    await tester.pumpAndSettle();
    final before = tester.getTopLeft(handle);
    await tester.timedDrag(handle, const Offset(0, 160), const Duration(milliseconds: 800));
    await tester.pumpAndSettle();
    expect(find.text('Body'), findsOneWidget);
    expect(tester.getTopLeft(handle), before);
  });
}
