import 'package:flutter_test/flutter_test.dart';
import 'package:workmate/home/sync_summary.dart';

void main() {
  test('every source read and nothing waiting: All sent', () {
    final s = syncSummary([0, 0, 0, 0]);
    expect([s.hidden, s.allSent, s.waiting], [false, true, 0]);
  });

  test('the four sources add up', () {
    final s = syncSummary([1, 2, 3, 4]);
    expect([s.hidden, s.allSent, s.waiting], [false, false, 10]);
  });

  test('any source not read yet: hidden — never an early All sent', () {
    final s = syncSummary([0, null, 0, 0]);
    expect([s.hidden, s.allSent], [true, false]);
  });

  test('tool records not confirmed: unresolved + unreadable + one for a store needing recovery', () {
    expect(toolsNotConfirmed(2, 1, true), 4);
    expect(toolsNotConfirmed(0, 0, false), 0);
  });
}
