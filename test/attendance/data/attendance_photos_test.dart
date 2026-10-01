import 'package:flutter_test/flutter_test.dart';
import 'package:workmate/attendance/data/attendance_photos.dart';

void main() {
  late DateTime now;
  late List<String> signed;
  late bool fail;
  late AttendancePhotos photos;

  setUp(() {
    now = DateTime.utc(2026, 9, 30, 1);
    signed = [];
    fail = false;
    photos = AttendancePhotos((path, seconds) async {
      if (fail) throw Exception('offline');
      signed.add('$path@$seconds');
      return 'https://example.invalid/$path?n=${signed.length}';
    }, now: () => now);
  });

  test('no path asks for nothing', () async {
    expect(await photos.signedUrl(null), isNull);
    expect(await photos.signedUrl(''), isNull);
    expect(signed, isEmpty);
  });

  test('a link lasts an hour and is reused inside it', () async {
    final first = await photos.signedUrl('w/2026-09-30/in-e.jpg');
    now = now.add(const Duration(minutes: 50));
    expect(await photos.signedUrl('w/2026-09-30/in-e.jpg'), first);
    expect(signed, ['w/2026-09-30/in-e.jpg@3600']);
  });

  test('a link about to expire is signed again', () async {
    await photos.signedUrl('p');
    now = now.add(const Duration(minutes: 56));
    await photos.signedUrl('p');
    expect(signed.length, 2);
  });

  test('a failed signing is no photo, and is not remembered', () async {
    fail = true;
    expect(await photos.signedUrl('p'), isNull);
    fail = false;
    expect(await photos.signedUrl('p'), isNotNull);
  });
}
