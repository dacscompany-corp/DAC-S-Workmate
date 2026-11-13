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

  testWidgets('the count bubble is a small 22-px pill, not the chip\'s full height (1021 phone check)', (tester) async {
    await tester.pumpWidget(page(Row(children: [
      WmCountChip(key: const Key('a'), label: 'All', count: 2, selected: true, onTap: () {}),
    ])));
    final bubble = find.ancestor(of: find.text('2'), matching: find.byType(DecoratedBox)).first;
    expect(tester.getSize(bubble).height, 22);
    expect(tester.getSize(find.byKey(const Key('a'))).height, 38, reason: 'the chip itself is unchanged');
    expect(tester.getCenter(bubble).dy, tester.getCenter(find.byKey(const Key('a'))).dy, reason: 'centred in the chip');
  });

  testWidgets('a choice chip hugs its label in a row of chips, and fills its share where it is meant to', (tester) async {
    await tester.pumpWidget(page(Column(children: [
      Wrap(spacing: 8, children: [
        WmChoiceChip(key: const Key('w1'), label: 'Just me', selected: true, onTap: () {}),
        WmChoiceChip(key: const Key('w2'), label: 'Team A', selected: false, onTap: () {}),
      ]),
      Row(children: [
        Expanded(child: WmChoiceChip(key: const Key('e1'), label: 'Material', selected: true, onTap: () {})),
        const SizedBox(width: 8),
        Expanded(child: WmChoiceChip(key: const Key('e2'), label: 'Tool', selected: false, onTap: () {})),
      ]),
    ])));
    final label = tester.getSize(find.text('Just me')).width;
    expect(tester.getSize(find.byKey(const Key('w1'))).width, label + 32, reason: 'label + 16 px each side, not the full width');
    expect(tester.getTopLeft(find.byKey(const Key('w2'))).dy, tester.getTopLeft(find.byKey(const Key('w1'))).dy, reason: 'side by side');
    expect(tester.getSize(find.byKey(const Key('e1'))).width, tester.getSize(find.byKey(const Key('e2'))).width, reason: 'equal shares');
    expect(tester.getCenter(find.text('Tool')).dx, tester.getCenter(find.byKey(const Key('e2'))).dx, reason: 'label centred');
  });

  testWidgets('a segmented switch: equal segments, the chosen one white and selected, a tap reports its value', (tester) async {
    final taps = <String>[];
    await tester.pumpWidget(page(WmSegmented<String>(
      segments: const [('a', 'Mine (2)', Key('seg-a')), ('b', 'Team', Key('seg-b')), ('c', 'My records', Key('seg-c'))],
      selected: 'b',
      onChanged: taps.add,
    )));
    final widths = [for (final k in ['seg-a', 'seg-b', 'seg-c']) tester.getSize(find.byKey(Key(k))).width];
    expect(widths[0], closeTo(widths[1], 0.01));
    expect(widths[1], closeTo(widths[2], 0.01));
    expect(materialColor(tester, 'seg-b'), Colors.white);
    expect(materialColor(tester, 'seg-a'), Colors.transparent);
    final handle = tester.ensureSemantics();
    expect(tester.getSemantics(find.byKey(const Key('seg-b'))), containsSemantics(isSelected: true));
    expect(tester.getSemantics(find.byKey(const Key('seg-a'))), containsSemantics(isSelected: false));
    handle.dispose();
    await tester.tap(find.byKey(const Key('seg-c')));
    expect(taps, ['c']);
  });

  testWidgets('WmSegmented: a long label shrinks to fit, its count never cut off', (tester) async {
    tester.view.physicalSize = const Size(320, 568);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(MaterialApp(
        home: MediaQuery(
            data: const MediaQueryData(size: Size(320, 568), textScaler: TextScaler.linear(1.3)),
            child: Scaffold(
                body: Padding(
                    padding: const EdgeInsets.all(20),
                    child: WmSegmented<int>(
                        segments: const [(0, 'Stock', null), (1, 'To receive (12)', Key('seg')), (2, 'Recent', null)],
                        selected: 0,
                        onChanged: (_) {}))))));
    expect(tester.takeException(), isNull);
    final text = tester.widget<Text>(find.text('To receive (12)'));
    expect(text.overflow, isNot(TextOverflow.ellipsis));
    final label = tester.getRect(find.text('To receive (12)'));
    final segment = tester.getRect(find.byKey(const Key('seg')));
    expect(label.left, greaterThanOrEqualTo(segment.left));
    expect(label.right, lessThanOrEqualTo(segment.right), reason: 'the whole label is inside its segment');
  });
}
