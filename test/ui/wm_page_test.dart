import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:workmate/ui/theme.dart';
import 'package:workmate/ui/wm_page.dart';
import 'package:workmate/ui/wm_sheet.dart';

import '../attendance/fakes.dart' show useTallPhone;

void main() {
  Future<void> open(WidgetTester tester, {Widget? action, Widget? footer, bool guard = false}) async {
    useTallPhone(tester);
    await tester.pumpWidget(MaterialApp(
      theme: workMateTheme(),
      home: Scaffold(
        body: Builder(
          builder: (context) => TextButton(
            onPressed: () => Navigator.of(context).push(MaterialPageRoute<void>(
              builder: (_) => PopScope(
                canPop: !guard,
                child: WmPage(title: 'New request', action: action, footer: footer, children: [for (var i = 0; i < 120; i++) Text('Row $i')]),
              ),
            )),
            child: const Text('open'),
          ),
        ),
      ),
    ));
    await tester.tap(find.text('open'));
    await tester.pumpAndSettle();
  }

  testWidgets('the title is a heading for TalkBack', (tester) async {
    final handle = tester.ensureSemantics();
    await open(tester);
    expect(tester.getSemantics(find.text('New request')), containsSemantics(isHeader: true));
    handle.dispose();
  });

  testWidgets('the title, the round back button (tooltip Back) and an action', (tester) async {
    var acted = 0;
    await open(tester, action: WmRoundButton(key: const Key('act'), icon: Icons.delete_outline, label: 'Delete draft', onTap: () => acted++));
    expect(find.text('New request'), findsOneWidget);
    expect(tester.widget<Text>(find.text('New request')).style!.fontSize, 24);
    expect(find.byKey(const Key('wm-page-back')), findsOneWidget);
    expect(find.byTooltip('Back'), findsOneWidget);
    await tester.tap(find.byKey(const Key('act')));
    expect(acted, 1);
    await tester.pageBack();
    await tester.pumpAndSettle();
    expect(find.text('New request'), findsNothing, reason: 'back closes the page');
  });

  testWidgets('back respects a PopScope that says no', (tester) async {
    await open(tester, guard: true);
    await tester.tap(find.byKey(const Key('wm-page-back')));
    await tester.pumpAndSettle();
    expect(find.text('New request'), findsOneWidget);
  });

  testWidgets('the footer stays pinned at the bottom while the body scrolls', (tester) async {
    await open(tester, footer: const SizedBox(key: Key('foot'), height: 56));
    final screen = tester.view.physicalSize / tester.view.devicePixelRatio;
    final before = tester.getBottomLeft(find.byKey(const Key('foot'))).dy;
    expect(before, lessThanOrEqualTo(screen.height));
    expect(before, greaterThan(screen.height - 100));
    await tester.drag(find.text('Row 5'), const Offset(0, -400));
    await tester.pumpAndSettle();
    expect(tester.getBottomLeft(find.byKey(const Key('foot'))).dy, before);
    expect(find.text('Row 0'), findsNothing, reason: 'the body scrolled');
  });

  testWidgets('a tall footer scrolls in its share; the fields keep room above the keyboard', (tester) async {
    tester.view.physicalSize = const Size(320, 568);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(MaterialApp(
        home: MediaQuery(
            data: const MediaQueryData(size: Size(320, 568), viewInsets: EdgeInsets.only(bottom: 260)),
            child: WmPage(
                title: 'Return a tool',
                footer: Container(key: const Key('tall'), height: 400, color: Colors.red),
                children: const [SizedBox(key: Key('field'), height: 40)]))));
    expect(tester.takeException(), isNull);
    final footer = tester.getSize(find.ancestor(of: find.byKey(const Key('tall')), matching: find.byType(SingleChildScrollView)).first);
    expect(footer.height, lessThanOrEqualTo((568 - 260) * .45 + .5));
  });
}
