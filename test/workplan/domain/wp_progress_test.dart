import 'package:flutter_test/flutter_test.dart';
import 'package:workmate/workplan/domain/wp_op.dart';
import 'package:workmate/workplan/domain/wp_progress.dart';
import 'package:workmate/workplan/domain/wp_rules.dart';

import '../workplan_fakes.dart';

WpEntry entry(Map<String, dynamic> doc, {List<WpOp> pending = const []}) => WpEntry(task: task0(doc), pendingOps: pending);

WpOp waiting(WpOpKind kind) =>
    WpOp(opId: 'p-${kind.name}', workerId: 'u1', kind: kind, createdAt: DateTime.utc(2026, 11, 12), taskId: 't1');

void main() {
  test('the four steps, in order', () {
    expect(wpStepLabels, ['Read', 'Started', 'Reported done', 'Approved']);
  });

  test('a new task: nothing reached; read it first', () {
    final p = progressOf(entry(taskDoc()));
    expect([p.reached, p.current, p.next, p.tone], [
      [false, false, false, false],
      0,
      'Next: read the task',
      NextTone.danger,
    ]);
  });

  test('read, not started, responsible: start work', () {
    final p = progressOf(entry(taskDoc(ackVersion: 1)));
    expect([p.reached, p.current, p.next, p.tone], [
      [true, false, false, false],
      1,
      'Next: start work',
      NextTone.normal,
    ]);
  });

  test('in progress: report done', () {
    final p = progressOf(entry(taskDoc(ackVersion: 1, status: 'in_progress')));
    expect([p.reached, p.next], [
      [true, true, false, false],
      'Next: report done',
    ]);
  });

  test('reported done: the office checks it next', () {
    final p = progressOf(entry(taskDoc(ackVersion: 1, status: 'reported_done')));
    expect([p.reached, p.current, p.leaderChecked, p.next], [
      [true, true, true, false],
      3,
      false,
      'Reported · the office checks it next',
    ]);
  });

  test('checked by the leader: step 3 reached and a line — not a step of its own', () {
    final p = progressOf(entry(taskDoc(ackVersion: 1, status: 'leader_checked')));
    expect([p.reached, p.leaderChecked, p.next], [
      [true, true, true, false],
      true,
      'Reported · the office checks it next',
    ]);
  });

  test('approved by the office: all four, Completed, green', () {
    final p = progressOf(entry(taskDoc(ackVersion: 1, status: 'completed')));
    expect([p.reached, p.current, p.count, p.next, p.tone], [
      [true, true, true, true],
      null,
      4,
      'Completed',
      NextTone.green,
    ]);
  });

  test('changed after reading: step 1 empty again, the later steps keep their state', () {
    final p = progressOf(entry(taskDoc(version: 2, ackVersion: 1, status: 'in_progress')));
    expect([p.reached, p.current, p.next], [
      [false, true, false, false],
      0,
      'Next: read the task',
    ]);
  });

  test('sent back by the office: back to Started', () {
    final p = progressOf(entry(taskDoc(ackVersion: 1, status: 'in_progress', sentBack: true)));
    expect([p.reached, p.next], [
      [true, true, false, false],
      'Next: report done',
    ]);
  });

  test('blocked: waiting for the office', () {
    final p = progressOf(entry(taskDoc(ackVersion: 1, blocked: true)));
    expect([p.next, p.tone], ['Waiting for the office to clear a problem', NextTone.brown]);
  });

  test('a leader with reported work to check', () {
    final p = progressOf(entry(taskDoc(role: 'leader', status: 'reported_done', canCheck: true)));
    expect([p.next, p.tone], ['Next: check this work', NextTone.danger]);
  });

  test('a helper: the responsible person reports', () {
    final p = progressOf(entry(taskDoc(role: 'helper', ackVersion: 1, status: 'in_progress')));
    expect([p.next, p.tone], ['The responsible person reports this work', NextTone.normal]);
  });

  test('anything still on the phone comes first; a pending Start counts as started', () {
    final p = progressOf(entry(taskDoc(ackVersion: 1), pending: [waiting(WpOpKind.start)]));
    expect([p.reached[1], p.next, p.tone], [true, 'Saved on this phone · sends when there is signal', NextTone.brown]);
  });
}
