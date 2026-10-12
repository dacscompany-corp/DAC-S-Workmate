import 'dart:async';

import 'package:flutter/foundation.dart';

import '../../app_controller.dart';
import 'history_api.dart';

/// Spec 1b §4.4: the offline copy is wiped on sign-out or account switch.
/// Fed every app state: once a worker is let in, only their copy is kept;
/// signed out, nothing is. Startup and the Terms screens decide nothing.
/// Keeping "only this worker" (not forgetting "the last one") also cleans a
/// switch that happened while the app was closed.
class HistoryAccountWipe {
  HistoryAccountWipe(this.history);

  final HistoryApi history;
  String? _kept;

  void onAppState(AppState s) {
    final keep = switch (s) {
      Ready(:final worker) => worker.id,
      SignedOut() => '',
      _ => null,
    };
    if (keep == null || keep == _kept) return;
    _kept = keep;
    unawaited(history.keepOnly(keep).catchError((Object e) {
      debugPrint('History wipe failed: $e');
      if (_kept == keep) _kept = null; // try again on the next state
    }));
  }
}
