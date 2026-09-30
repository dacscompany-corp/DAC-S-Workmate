import 'dart:io' show HttpDate;

/// A time the worker cannot move by changing the phone's clock (0078).
///
/// Whenever the server answers, its clock (the HTTP Date header) is written
/// down next to the phone's UPTIME counter, which nothing in Settings can
/// change. At the shutter: trusted = serverTimeAtAnchor + (uptimeNow - uptimeAtAnchor).
/// Returns null — never a guess — with no anchor, after a reboot, or when the
/// anchor is older than [maxAnchorAge]. The server then falls back to the
/// phone's time only if it arrived within 3 minutes.
class ClockAnchor {
  const ClockAnchor({required this.serverTime, required this.uptimeMillis, this.bootCount});

  final DateTime serverTime;
  final int uptimeMillis;

  /// Settings.Global.BOOT_COUNT then, or null if the phone does not say.
  final int? bootCount;
}

const maxAnchorAge = Duration(days: 7);

DateTime? trustedTime(ClockAnchor? anchor, {required int uptimeNowMillis, required int? bootCountNow}) {
  if (anchor == null) return null;
  // Rebooted since the anchor: uptime restarted, the anchor is void.
  if (anchor.bootCount != null && bootCountNow != null && anchor.bootCount != bootCountNow) return null;
  final elapsed = uptimeNowMillis - anchor.uptimeMillis;
  // Uptime never runs backwards within one boot; if it has, it was a reboot.
  if (elapsed < 0) return null;
  if (elapsed > maxAnchorAge.inMilliseconds) return null;
  return anchor.serverTime.toUtc().add(Duration(milliseconds: elapsed));
}

/// The server clock from an HTTP Date header, or null when absent or unreadable.
DateTime? parseServerDate(String? header) {
  if (header == null || header.trim().isEmpty) return null;
  try {
    return HttpDate.parse(header.trim()).toUtc();
  } catch (_) {
    return null;
  }
}
