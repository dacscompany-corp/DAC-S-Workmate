import 'dart:math';

import 'package:flutter_test/flutter_test.dart';
import 'package:workmate/attendance/domain/event_id.dart';

void main() {
  final v4 = RegExp(r'^[0-9a-f]{8}-[0-9a-f]{4}-4[0-9a-f]{3}-[89ab][0-9a-f]{3}-[0-9a-f]{12}$');

  test('an event id is a version 4 UUID the server accepts', () {
    for (var i = 0; i < 200; i++) {
      expect(newEventId(), matches(v4));
    }
  });

  test('ids do not repeat', () {
    expect({for (var i = 0; i < 1000; i++) newEventId()}.length, 1000);
  });

  test('a seeded generator is repeatable (for tests)', () {
    expect(newEventId(Random(7)), newEventId(Random(7)));
  });
}
