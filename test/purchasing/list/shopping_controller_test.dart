import 'package:flutter_test/flutter_test.dart';
import 'package:workmate/purchasing/data/purchasing_api.dart';
import 'package:workmate/purchasing/domain/pur_models.dart';
import 'package:workmate/purchasing/list/shopping_controller.dart';

import '../purchasing_api_fake.dart';
import '../purchasing_fakes.dart';

ShoppingLine line(String id, String project, List<PurPortion> portions, {bool urgent = false}) => ShoppingLine(
      lineId: id,
      requestId: 'r-$id',
      description: 'Item $id',
      unit: 'pc',
      projectId: project,
      projectName: project == 'f1' ? 'Barlin Residence' : 'Sulit Residence',
      workId: project,
      workName: 'Main Contract',
      urgent: urgent,
      portions: portions,
    );

void main() {
  late FakePurchasingApi api;
  late ShoppingController c;

  setUp(() async {
    api = FakePurchasingApi();
    api.shopping = ShoppingView(batches: [thisWeek, nextWeek], lines: [
      line('a', 'f1', [portion('pa1', buyer: 'u1', mine: true), portion('pa2', batch: 'b2')]),
      line('b', 'f2', [portion('pb1'), portion('pb2', buyer: 'u9'), portion('pb3', still: 0)]),
    ]);
    c = ShoppingController(api: api, now: () => wednesday);
    await c.refresh();
  });

  test('Mine, then Unassigned, then other buyers — this week only by default (Q4)', () {
    final s = c.sections;
    expect(s.mine.map((e) => e.portion.id), ['pa1']);
    expect(s.unassigned.map((e) => e.portion.id), ['pb1']);
    expect(s.others.map((e) => e.portion.id), ['pb2']);
  });

  test('nothing left to buy is not shown', () {
    c.setScope(BatchScope.all);
    expect([...c.sections.unassigned, ...c.sections.others].map((e) => e.portion.id), isNot(contains('pb3')));
  });

  test('all weeks shows next week\'s portions too', () {
    c.setScope(BatchScope.all);
    expect(c.sections.unassigned.map((e) => e.portion.id), ['pa2', 'pb1']);
  });

  test('the project filter keeps one project; its list comes from the lines, by name', () {
    expect(c.projects, [('f1', 'Barlin Residence'), ('f2', 'Sulit Residence')]);
    c.setProject('f2');
    expect(c.sections.mine, isEmpty);
    expect(c.sections.unassigned.map((e) => e.portion.id), ['pb1']);
  });

  test('claim all sends no quantity; claim part sends it (Q5)', () async {
    final e = c.sections.unassigned.single;
    await c.claim(e);
    await c.claim(e, quantity: 4);
    await c.claim(e, quantity: 10);
    expect(api.calls.where((x) => x.startsWith('claim')), ['claim:pb1:null', 'claim:pb1:4.0', 'claim:pb1:null']);
  });

  test('after an action the list is read again', () async {
    api.calls.clear();
    await c.release(c.sections.mine.single);
    expect(api.calls, ['release:pa1', 'shoppingList']);
  });

  test('a refusal is said in both languages and nothing else changes', () async {
    api.error = refusal('ASSIGNED_TO_OTHER');
    await c.claim(c.sections.unassigned.single);
    expect(c.notice!.english, 'Another buyer has that item now. Refresh the list.');
    expect(c.busy, isEmpty);
    c.dismissNotice();
    expect(c.notice, isNull);
  });

  test('only my portions can be picked; picked ones become lines, one per request line', () async {
    c.toggle(c.sections.unassigned.single);
    expect(c.selected, isEmpty);
    c.toggle(c.sections.mine.single);
    final lines = c.linesForSelected();
    expect(lines.single.requestLineId, 'a');
    expect(lines.single.picks.single.portionId, 'pa1');
    expect(lines.single.folderId, 'f1');
  });

  test('releasing a picked portion un-picks it', () async {
    c.toggle(c.sections.mine.single);
    await c.release(c.sections.mine.single);
    expect(c.selected, isEmpty);
  });
}
