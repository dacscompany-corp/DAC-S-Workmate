import 'package:shared_preferences/shared_preferences.dart';

/// Remembers, per phone, that the worker has swiped a My Work card once, so
/// the hint stops showing (Phase 2 spec §4.5). Not per account: it teaches a
/// gesture, it holds no work data.
abstract interface class WpHintStore {
  bool get swipeSeen;
  Future<void> markSwipeSeen();
}

class PrefsWpHintStore implements WpHintStore {
  PrefsWpHintStore(this._prefs);

  static const key = 'wm.mywork.swipeHintSeen';
  final SharedPreferences _prefs;

  @override
  bool get swipeSeen => _prefs.getBool(key) ?? false;

  @override
  Future<void> markSwipeSeen() async {
    await _prefs.setBool(key, true);
  }
}

/// In memory: tests, or no settings file.
class MemoryWpHintStore implements WpHintStore {
  bool _seen = false;

  @override
  bool get swipeSeen => _seen;

  @override
  Future<void> markSwipeSeen() async => _seen = true;
}
