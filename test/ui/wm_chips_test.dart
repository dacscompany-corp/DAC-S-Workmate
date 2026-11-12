import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:workmate/ui/theme.dart';
import 'package:workmate/ui/wm_chips.dart';

void main() {
  Widget page(Widget child) => MaterialApp(
        theme: workMateTheme(),
        home: Scaffold(body: ListView(padding: const EdgeInsets.symmetric(horizontal: 20), children: [child])),
      );

  Color materialColor(WidgetTester tester, String key) =>
      tester.widget<Material>(find.descendant(of: find.byKey(Key(key)), matching: find.byType(Material)).first).color!;

  testWidgets('a count chip shows its label and count; the selected one is dark', (tester) async {
    var taps = 0;
    await tester.pumpWidget(page(Row(children: [
      WmCountChip(key: const Key('a'), label: 'Today', count: 3, selected: true, onTap: () => taps++),
      WmCountChip(key: const Key('b'), label: 'Done', count: 0, selected: false, onTap: () {}),
    ])));
    expect(find.descendant(of: find.byKey(const Key('a')), matching: find.text('3')), findsOneWidget);
    expect(find.descendant(of: find.byKey(const Key('b')), matching: find.text('Done')), findsOneWidget);
    expect(materialColor(tester, 'a'), WmColors.text);
    expect(materialColor(tester, 'b'), Colors.white);
    await tester.tap(find.byKey(const Key('a')));
    expect(taps, 1);
    final handle = tester.ensureSemantics();
    expect(tester.getSemantics(find.byKey(const Key('a'))), containsSemantics(isSelected: true));
    expect(tester.getSemantics(find.byKey(const Key('b'))), containsSemantics(isSelected: false));
    handle.dispose();
  });

  testWidgets('a pill button taps; a busy one shows a spinner and ignores taps', (tester) async {
    var taps = 0;
    await tester.pumpWidget(page(WmPillButton(key: const Key('p'), icon: Icons.history, label: 'Find previous item', onTap: () => taps++)));
    await tester.tap(find.byKey(const Key('p')));
    expect(taps, 1);
    await tester.pumpWidget(page(WmPillButton(key: const Key('p'), icon: Icons.history, label: 'Find previous item', onTap: () => taps++, busy: true)));
    await tester.pump();
    expect(find.byType(CircularProgressIndicator), findsOneWidget);
    expect(find.byIcon(Icons.history), findsNothing);
    // A busy pill absorbs the tap (AbsorbPointer adds no hit entry); taps stays 1.
    await tester.tap(find.byKey(const Key('p')), warnIfMissed: false);
    expect(taps, 1);
  });

  testWidgets('a pill with a long label wraps inside a narrow box instead of overflowing', (tester) async {
    await tester.pumpWidget(page(const SizedBox(
      width: 160,
      child: WmPillButton(key: Key('long'), icon: Icons.edit_note, label: 'Not in the list? Describe it with a very long label', onTap: null),
    )));
    expect(tester.takeException(), isNull);
    expect(tester.getSize(find.byKey(const Key('long'))).height, greaterThan(40));
  });

  testWidgets('the chip row runs to the screen edges; its first chip lines up with the page padding', (tester) async {
    await tester.pumpWidget(page(WmChipRow(children: [
      for (var i = 0; i < 6; i++) WmCountChip(key: Key('c$i'), label: 'Chip $i', count: i, selected: i == 0, onTap: () {}),
    ])));
    expect(tester.getTopLeft(find.byKey(const Key('c0'))).dx, 20);
    expect(tester.getSize(find.byType(SingleChildScrollView)).width, tester.view.physicalSize.width / tester.view.devicePixelRatio);
    expect(tester.getTopLeft(find.byKey(const Key('c1'))).dx - tester.getTopRight(find.byKey(const Key('c0'))).dx, 8);
  });

  testWidgets('a choice chip: label only; the selected one is dark and says so to TalkBack', (tester) async {
    var taps = 0;
    await tester.pumpWidget(page(Row(children: [
      WmChoiceChip(key: const Key('x'), label: 'Just me', selected: true, onTap: () => taps++),
      WmChoiceChip(key: const Key('y'), label: 'Team A', selected: false, onTap: () {}),
    ])));
    expect(materialColor(tester, 'x'), WmColors.text);
    expect(materialColor(tester, 'y'), Colors.white);
    expect(find.text('Just me'), findsOneWidget);
    await tester.tap(find.byKey(const Key('x')));
    expect(taps, 1);
    final handle = tester.ensureSemantics();
    expect(tester.getSemantics(find.byKey(const Key('x'))), containsSemantics(isSelected: true));
    expect(tester.getSemantics(find.byKey(const Key('y'))), containsSemantics(isSelected: false));
    handle.dispose();
  });
}
