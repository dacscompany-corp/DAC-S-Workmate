import 'package:shared_preferences/shared_preferences.dart';

import '../domain/trusted_time.dart';
import 'device_bridge.dart';

/// Where the last server clock reading lives (plain prefs: nothing secret, and
/// a keystore hiccup must never cost the anchor).
class ClockAnchorStore {
  ClockAnchorStore(this._prefs, this._bridge);

  final SharedPreferences _prefs;
  final DeviceBridge _bridge;

  /// One value, one write: "serverMs|uptimeMs|bootCount". Three separate keys
  /// could be torn by a process kill and pair a new server time with an old uptime.
  static const _anchor = 'clock.anchor';

  /// Called for every server response; the newest reading wins.
  Future<void> recordServerDate(String header) async {
    final server = parseServerDate(header);
    if (server == null) return;
    final clock = await _bridge.clock();
    await _prefs.setString(_anchor, '${server.millisecondsSinceEpoch}|${clock.uptimeMillis}|${clock.bootCount ?? -1}');
  }

  /// The trusted time now, or null when it cannot be vouched for.
  Future<DateTime?> now() async {
    try {
      final parts = _prefs.getString(_anchor)?.split('|');
      if (parts == null || parts.length != 3) return null;
      final serverMs = int.tryParse(parts[0]);
      final uptime = int.tryParse(parts[1]);
      final boot = int.tryParse(parts[2]);
      if (serverMs == null || uptime == null || boot == null) return null;
      final anchor = ClockAnchor(
        serverTime: DateTime.fromMillisecondsSinceEpoch(serverMs, isUtc: true),
        uptimeMillis: uptime,
        bootCount: boot >= 0 ? boot : null,
      );
      final clock = await _bridge.clock();
      return trustedTime(anchor, uptimeNowMillis: clock.uptimeMillis, bootCountNow: clock.bootCount);
    } catch (_) {
      return null; // cannot vouch
    }
  }
}
