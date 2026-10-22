import 'dart:async';

import 'package:flutter/foundation.dart';

import '../../app_controller.dart';
import 'purchasing_api.dart';

/// Site phones are shared, and prices are for buyers only. Fed every app
/// state: once a buyer is let in, only their saved copy is kept; signed out,
/// or with buying turned off (R2), none is. Startup and the gates decide
/// nothing. Unsent purchases are never touched — they wait for their buyer.
class PurchasingAccountWipe {
  PurchasingAccountWipe(this.api);

  final PurchasingApi api;
  String? _kept;

  void onAppState(AppState s) {
    final keep = switch (s) {
      BuyerReady(:final worker) => worker.id,
      SignedOut() || BuyingOff() || Ready() => '',
      _ => null,
    };
    if (keep == null || keep == _kept) return;
    _kept = keep;
    unawaited(api.keepOnly(keep).catchError((Object e) {
      debugPrint('Buying wipe failed: $e');
      if (_kept == keep) _kept = null; // try again on the next state
    }));
  }
}
