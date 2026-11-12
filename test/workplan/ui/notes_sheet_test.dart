import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:workmate/ui/theme.dart';
import 'package:workmate/workplan/data/workplan_api.dart';
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

  Future<void> openNotes(WidgetTester tester, MyWorkController c) async {
    useTallPhone(tester);
    await tester.pumpWidget(MaterialApp(
      theme: workMateTheme(),
      home: Scaffold(
        body: Builder(builder: (context) => TextButton(onPressed: () => showNotesSheet(context, c), child: const Text('open'))),
      ),
    ));
    await tester.tap(find.text('open'));
    await tester.pumpAndSettle();
  }

  testWidgets('no signal and nothing saved: it says so, not "no notes"', (tester) async {
    final api = FakeWorkPlanApi()..view = const WorkPlanView(error: SocketException('no signal'));
    final c = MyWorkController(api: api);
    await c.refresh();
    await openNotes(tester, c);
    expect(find.text('No signal right now. Open this again when there is signal.'), findsOneWidget);
    expect(find.text('No meeting notes for you yet.'), findsNothing);
  });

  testWidgets('no signal with a saved copy: the saved notes, and when they were saved', (tester) async {
    final api = FakeWorkPlanApi()
      ..view = WorkPlanView(notes: FakeWorkPlanApi().view.notes, error: const SocketException('no signal'), fetchedAt: DateTime.utc(2026, 11, 11, 1));
    final c = MyWorkController(api: api);
    await c.refresh();
    await openNotes(tester, c);
    expect(find.textContaining('No signal: showing what this phone saved on'), findsOneWidget);
    expect(find.text('Skim coat first, then cabinets.'), findsOneWidget);
  });
}
