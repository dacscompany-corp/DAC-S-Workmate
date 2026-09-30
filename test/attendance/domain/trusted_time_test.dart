import 'package:flutter_test/flutter_test.dart';
import 'package:workmate/attendance/domain/trusted_time.dart';

void main() {
  final server = DateTime.parse('2026-09-28T23:30:00Z'); // 07:30 Manila
  final anchor = ClockAnchor(serverTime: server, uptimeMillis: 1000000, bootCount: 12);

  test('trusted time follows uptime, not the wall clock', () {
    expect(
      trustedTime(anchor, uptimeNowMillis: 1000000 + 40 * 60000, bootCountNow: 12),
      server.add(const Duration(minutes: 40)),
    );
  });

  test('no anchor yet means no trusted time', () {
    expect(trustedTime(null, uptimeNowMillis: 5000, bootCountNow: 12), isNull);
  });

  test('a reboot since the anchor voids it', () {
    expect(trustedTime(anchor, uptimeNowMillis: 2000000, bootCountNow: 13), isNull);
  });

  test('uptime running backwards is a reboot the boot count did not reveal', () {
    final noBoot = ClockAnchor(serverTime: server, uptimeMillis: 1000000, bootCount: null);
    expect(trustedTime(noBoot, uptimeNowMillis: 500, bootCountNow: null), isNull);
  });

  test('an anchor older than a week is not paid on', () {
    final tooOld = 1000000 + maxAnchorAge.inMilliseconds + 1;
    expect(trustedTime(anchor, uptimeNowMillis: tooOld, bootCountNow: 12), isNull);
  });

  test('an unknown boot count falls back to the uptime check alone', () {
    final noBoot = ClockAnchor(serverTime: server, uptimeMillis: 1000000, bootCount: null);
    expect(
      trustedTime(noBoot, uptimeNowMillis: 1060000, bootCountNow: null),
      server.add(const Duration(seconds: 60)),
    );
  });

  test("the HTTP Date header parses to the server's instant", () {
    expect(parseServerDate('Sun, 27 Sep 2026 17:12:43 GMT'), DateTime.parse('2026-09-27T17:12:43Z'));
  });

  test('a missing or garbled Date header is no anchor, never a crash', () {
    expect(parseServerDate(null), isNull);
    expect(parseServerDate(''), isNull);
    expect(parseServerDate('yesterday-ish'), isNull);
  });
}
