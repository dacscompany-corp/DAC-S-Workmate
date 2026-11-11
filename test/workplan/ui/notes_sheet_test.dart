import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:workmate/ui/theme.dart';
import 'package:workmate/workplan/ui/my_work_controller.dart';
import 'package:workmate/workplan/ui/notes_sheet.dart';

import '../../attendance/fakes.dart' show useTallPhone;
import '../workplan_fakes.dart';

void main() {
  testWidgets('Meeting notes open as a sheet and close with a swipe down', (tester) async {
    useTallPhone(tester);
    final c = MyWorkController(api: FakeWorkPlanApi());
    await c.refresh();
    await tester.pumpWidget(MaterialApp(
      theme: workMateTheme(),
      home: Scaffold(
        body: Builder(builder: (context) => TextButton(onPressed: () => showNotesSheet(context, c), child: const Text('open'))),
      ),
    ));
    await tester.tap(find.text('open'));
    await tester.pumpAndSettle();
    expect(find.text('Meeting notes'), findsOneWidget);
    expect(find.text('Skim coat first, then cabinets.'), findsOneWidget);
    await tester.timedDrag(find.byKey(const Key('wm-sheet-handle')), const Offset(0, 160), const Duration(milliseconds: 800));
    await tester.pumpAndSettle();
    expect(find.text('Skim coat first, then cabinets.'), findsNothing);
  });
}
