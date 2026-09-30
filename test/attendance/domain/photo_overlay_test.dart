import 'package:flutter_test/flutter_test.dart';
import 'package:workmate/attendance/domain/photo_overlay.dart';

void main() {
  const long = 'A Very Long Construction Project Name That Will Not Fit On One Line';

  test('the overlay carries project, date and time', () {
    expect(
      photoOverlayCaption('ABC Building Project', DateTime.parse('2026-08-18T23:45:00Z')),
      'ABC Building Project · 19 Aug 2026 · 7:45 AM',
    );
  });

  test('the time is Manila, not the device zone', () {
    expect(photoOverlayCaption('Site', DateTime.parse('2026-08-18T23:45:00Z')), contains('19 Aug 2026'));
  });

  test('an evening capture reads as PM', () {
    expect(photoOverlayCaption('Site', DateTime.parse('2026-08-19T09:30:00Z')), contains('5:30 PM'));
  });

  test('noon and midnight read as 12, not 0', () {
    expect(photoOverlayStamp(DateTime.parse('2026-08-19T04:05:00Z')), '19 Aug 2026 · 12:05 PM');
    expect(photoOverlayStamp(DateTime.parse('2026-08-19T16:05:00Z')), '20 Aug 2026 · 12:05 AM');
  });

  test('a long project name is truncated rather than overflowing the photo', () {
    final caption = photoOverlayCaption(long, DateTime.parse('2026-08-19T09:30:00Z'));
    expect(caption, startsWith('A Very Long Construction Project'));
    expect(caption, contains('…'));
    expect(caption, contains('5:30 PM'));
  });

  test('the split lines rejoin into exactly the burned-in caption', () {
    final at = DateTime.parse('2026-08-19T09:30:00Z');
    final (name, stamp) = photoOverlayCaptionLines('ABC Building Project', at);
    expect('$name · $stamp', photoOverlayCaption('ABC Building Project', at));
  });

  test('only the name line is ever truncated', () {
    final (name, stamp) = photoOverlayCaptionLines(long, DateTime.parse('2026-08-19T09:30:00Z'));
    expect(name, endsWith('…'));
    expect(stamp, '19 Aug 2026 · 5:30 PM');
  });
}
