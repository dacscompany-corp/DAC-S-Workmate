import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:workmate/ui/theme.dart';
import 'package:workmate/ui/wm_nav_bar.dart';

void main() {
  testWidgets('a count shows in a red bubble with a white ring; none at 0', (tester) async {
    await tester.pumpWidget(MaterialApp(
      theme: workMateTheme(),
      home: const Scaffold(
        body: Center(
          child: Column(mainAxisSize: MainAxisSize.min, children: [
            RingBadge(key: Key('a'), count: 3, child: Icon(Icons.assignment)),
            SizedBox(height: 24),
            RingBadge(key: Key('b'), count: 0, child: Icon(Icons.inventory_2)),
          ]),
        ),
      ),
    ));
    expect(find.descendant(of: find.byKey(const Key('a')), matching: find.text('3')), findsOneWidget);
    expect(find.descendant(of: find.byKey(const Key('b')), matching: find.byType(Text)), findsNothing);
    final bubble = tester.widget<Container>(find.byKey(const Key('ring-badge-bubble')));
    final d = bubble.decoration! as BoxDecoration;
    final ring = (d.border! as Border).top;
    expect([d.color, ring.color, ring.width], [WmColors.danger, Colors.white, 2.0]);
  });

  test('the bar theme: white, a light-green pill, green selected labels, grey others', () {
    final t = workMateTheme().navigationBarTheme;
    expect([t.backgroundColor, t.indicatorColor], [Colors.white, WmColors.greenBorder]);
    expect(t.labelTextStyle!.resolve({WidgetState.selected})!.color, WmColors.green);
    expect(t.labelTextStyle!.resolve(<WidgetState>{})!.color, WmColors.textMuted);
  });

  testWidgets('the bar has a line on top and reports the tab tapped', (tester) async {
    var picked = -1;
    await tester.pumpWidget(MaterialApp(
      theme: workMateTheme(),
      home: Scaffold(
        bottomNavigationBar: WmNavBar(
          selectedIndex: 0,
          onDestinationSelected: (i) => picked = i,
          destinations: const [
            NavigationDestination(icon: Icon(Icons.home), label: 'Home'),
            NavigationDestination(icon: Icon(Icons.history), label: 'History'),
          ],
        ),
      ),
    ));
    expect(find.byType(NavigationBar), findsOneWidget);
    final box = tester.widget<DecoratedBox>(find.byKey(const Key('wm-nav-bar')));
    expect(((box.decoration as BoxDecoration).border! as Border).top.color, WmColors.border);
    await tester.tap(find.text('History'));
    expect(picked, 1);
  });

  test('pop-up messages float, dark and rounded', () {
    final s = workMateTheme().snackBarTheme;
    expect([s.behavior, s.backgroundColor], [SnackBarBehavior.floating, WmColors.text]);
  });
}
