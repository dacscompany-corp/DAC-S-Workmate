import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

abstract class SecretBox {
  Future<String?> read(String key);
  Future<void> write(String key, String value);
  Future<void> delete(String key);
}

/// Android keystore-backed storage. resetOnError is OFF: the library's
/// default wipes everything on the first error, and on these phones the
/// first error is usually a keystore that is busy just after boot.
class SecureBox implements SecretBox {
  static const _storage = FlutterSecureStorage(aOptions: AndroidOptions(resetOnError: false));

  @override
  Future<String?> read(String key) => _storage.read(key: key);
  @override
  Future<void> write(String key, String value) => _storage.write(key: key, value: value);
  @override
  Future<void> delete(String key) => _storage.delete(key: key);
}

/// supabase_flutter's session store: holds the REFRESH TOKEN, so losing it
/// is a silent sign-out. Same rules as the Attendance app's store:
/// retry a failed read before deciding anything; only a store unreadable
/// twice is treated as corrupt; a keystore that cannot write at all
/// degrades to app-private storage rather than locking the worker out.
class WorkMateSessionStorage extends LocalStorage {
  WorkMateSessionStorage({
    required this.secure,
    required this.plain,
    this.retryDelay = const Duration(milliseconds: 300),
  });

  final SecretBox secure;
  final SharedPreferences plain;

  /// A keystore busy just after boot needs a moment; injectable for tests.
  final Duration retryDelay;

  // Incremented by every sign-out so a slow persistSession that finishes
  // AFTER it can tell, and take its write back.
  int _signOutEpoch = 0;

  static const key = 'workmate_session';
  static const _plainFlag = 'workmate_session_plain';
  // Set before a sign-out delete; while set the session counts as gone even
  // if the keystore delete failed, so a previous worker never comes back.
  static const _clearedFlag = 'workmate_session_cleared';

  bool get _degraded => plain.getBool(_plainFlag) ?? false;

  @override
  Future<void> initialize() async {}

  Future<String?> _read() async {
    if (plain.getBool(_clearedFlag) ?? false) {
      try {
        await secure.delete(key);
        await plain.remove(_clearedFlag);
      } catch (_) {}
      return null;
    }
    if (_degraded) return plain.getString(key);
    try {
      return await secure.read(key);
    } catch (_) {
      await Future<void>.delayed(retryDelay);
      try {
        return await secure.read(key);
      } catch (_) {
        try {
          await secure.delete(key);
        } catch (_) {}
        return null;
      }
    }
  }

  @override
  Future<bool> hasAccessToken() async => (await _read()) != null;

  @override
  Future<String?> accessToken() => _read();

  @override
  Future<void> persistSession(String persistSessionString) async {
    final epoch = _signOutEpoch;
    await _write(persistSessionString, epoch);
    if (epoch != _signOutEpoch) {
      // A sign-out ran while this write was in flight: the session it just
      // wrote must not survive it. The cleared flag stays set.
      try {
        await secure.delete(key);
      } catch (_) {}
      try {
        await plain.remove(key);
        await plain.remove(_plainFlag);
        await plain.setBool(_clearedFlag, true);
      } catch (_) {}
    }
  }

  Future<void> _write(String value, int epoch) async {
    if (!_degraded) {
      for (var attempt = 0; attempt < 2; attempt++) {
        try {
          await secure.write(key, value);
          if (epoch == _signOutEpoch) await plain.remove(_clearedFlag);
          return;
        } catch (_) {}
      }
      await plain.setBool(_plainFlag, true);
    }
    await plain.setString(key, value);
    if (epoch == _signOutEpoch) await plain.remove(_clearedFlag);
  }

  @override
  Future<void> removePersistedSession() async {
    _signOutEpoch++;
    await plain.setBool(_clearedFlag, true);
    await plain.remove(key);
    await plain.remove(_plainFlag);
    try {
      await secure.delete(key);
      await plain.remove(_clearedFlag);
    } catch (_) {}
  }
}
