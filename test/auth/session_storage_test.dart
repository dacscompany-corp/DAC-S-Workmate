import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:workmate/auth/session_storage.dart';

/// A keystore that fails its first [failures] calls, like cheap phones do
/// right after boot.
class FlakyBox implements SecretBox {
  FlakyBox({this.failures = 0});
  int failures;
  final data = <String, String>{};
  void _maybeFail() {
    if (failures > 0) {
      failures--;
      throw Exception('keystore busy');
    }
  }

  @override
  Future<String?> read(String key) async { _maybeFail(); return data[key]; }
  /// When set, write() waits for it before storing.
  Future<void>? writeGate;
  @override
  Future<void> write(String key, String value) async {
    _maybeFail();
    await writeGate;
    data[key] = value;
  }
  @override
  Future<void> delete(String key) async { _maybeFail(); data.remove(key); }
}

void main() {
  setUp(() => SharedPreferences.setMockInitialValues({}));

  test('persists and restores the session', () async {
    final box = FlakyBox();
    final s = WorkMateSessionStorage(secure: box, plain: await SharedPreferences.getInstance(), retryDelay: Duration.zero);
    await s.persistSession('{"s":1}');
    expect(await s.hasAccessToken(), isTrue);
    expect(await s.accessToken(), '{"s":1}');
  });

  test('one keystore hiccup does NOT sign the worker out', () async {
    final box = FlakyBox()..data[WorkMateSessionStorage.key] = '{"s":1}';
    box.failures = 1;
    final s = WorkMateSessionStorage(secure: box, plain: await SharedPreferences.getInstance(), retryDelay: Duration.zero);
    expect(await s.accessToken(), '{"s":1}');
    expect(box.data.containsKey(WorkMateSessionStorage.key), isTrue);
  });

  test('a store unreadable twice is treated as corrupt: session gone, no crash', () async {
    final box = FlakyBox()..data[WorkMateSessionStorage.key] = '{"s":1}';
    box.failures = 2;
    final s = WorkMateSessionStorage(secure: box, plain: await SharedPreferences.getInstance(), retryDelay: Duration.zero);
    expect(await s.accessToken(), isNull);
  });

  test('a keystore that cannot write degrades to app-private storage instead of losing sign-in', () async {
    final box = FlakyBox(failures: 99);
    final prefs = await SharedPreferences.getInstance();
    final s = WorkMateSessionStorage(secure: box, plain: prefs, retryDelay: Duration.zero);
    await s.persistSession('{"s":2}');
    expect(await s.accessToken(), '{"s":2}');
  });

  test('remove clears both stores', () async {
    final box = FlakyBox()..data[WorkMateSessionStorage.key] = '{"s":1}';
    final s = WorkMateSessionStorage(secure: box, plain: await SharedPreferences.getInstance(), retryDelay: Duration.zero);
    expect(await s.hasAccessToken(), isTrue);
    await s.removePersistedSession();
    expect(box.data.containsKey(WorkMateSessionStorage.key), isFalse);
    expect(await s.hasAccessToken(), isFalse);
  });

  test('remove also clears an app-private (degraded) session', () async {
    final box = FlakyBox(failures: 99);
    final s = WorkMateSessionStorage(secure: box, plain: await SharedPreferences.getInstance(), retryDelay: Duration.zero);
    await s.persistSession('{"s":2}');
    box.failures = 0;
    await s.removePersistedSession();
    expect(await s.hasAccessToken(), isFalse);
  });

  test('a persist that finishes after a sign-out cannot make the session readable', () async {
    final box = FlakyBox();
    final prefs = await SharedPreferences.getInstance();
    final s = WorkMateSessionStorage(secure: box, plain: prefs, retryDelay: Duration.zero);
    final gate = Completer<void>();
    box.writeGate = gate.future;
    final persisting = s.persistSession('{"late":1}');
    await Future<void>.delayed(Duration.zero);
    await s.removePersistedSession();
    gate.complete();
    await persisting;
    expect(box.data.containsKey(WorkMateSessionStorage.key), isFalse);
    expect(await s.hasAccessToken(), isFalse);
    final relaunched = WorkMateSessionStorage(secure: box, plain: prefs, retryDelay: Duration.zero);
    expect(await relaunched.accessToken(), isNull);
  });

  test('a failed keystore delete at sign-out cannot bring the previous worker back', () async {
    final box = FlakyBox()..data[WorkMateSessionStorage.key] = '{"s":1}';
    final prefs = await SharedPreferences.getInstance();
    final s = WorkMateSessionStorage(secure: box, plain: prefs, retryDelay: Duration.zero);
    box.failures = 1; // the delete during remove throws
    await s.removePersistedSession();
    expect(box.data.containsKey(WorkMateSessionStorage.key), isTrue); // still in the keystore
    expect(await s.hasAccessToken(), isFalse);
    expect(await s.accessToken(), isNull);
    final relaunched = WorkMateSessionStorage(secure: box, plain: prefs, retryDelay: Duration.zero);
    expect(await relaunched.accessToken(), isNull);

    await relaunched.persistSession('{"s":3}');
    expect(await relaunched.accessToken(), '{"s":3}');
  });
}
