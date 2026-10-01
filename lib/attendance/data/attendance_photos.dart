import 'package:supabase_flutter/supabase_flutter.dart';

import 'attendance_remote.dart';

/// Links to attendance photos in the PRIVATE `attendance` bucket. Each link
/// lasts an hour and is reused until shortly before it expires, so scrolling
/// History back and forth does not mint a link per frame.
class AttendancePhotos {
  AttendancePhotos(this._sign, {DateTime Function()? now}) : _now = now ?? DateTime.now;

  factory AttendancePhotos.supabase(SupabaseClient client) =>
      AttendancePhotos((path, seconds) => client.storage.from(photoBucket).createSignedUrl(path, seconds));

  static const lifetime = Duration(hours: 1);
  static const _renewBefore = Duration(minutes: 5);

  final Future<String> Function(String path, int expiresInSeconds) _sign;
  final DateTime Function() _now;
  final _cache = <String, (String, DateTime)>{};

  /// A link for [path], or null (no photo yet, or no signal right now).
  Future<String?> signedUrl(String? path) async {
    if (path == null || path.isEmpty) return null;
    final hit = _cache[path];
    if (hit != null && _now().isBefore(hit.$2.subtract(_renewBefore))) return hit.$1;
    try {
      final url = await _sign(path, lifetime.inSeconds);
      _cache[path] = (url, _now().add(lifetime));
      return url;
    } catch (_) {
      return null;
    }
  }
}
