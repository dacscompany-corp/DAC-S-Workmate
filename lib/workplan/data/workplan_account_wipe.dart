import 'dart:async';

import 'package:flutter/foundation.dart';

import '../../app_controller.dart';
import 'workplan_api.dart';

/// Spec §11: account switching must not reveal another worker's tasks or
/// notes. Fed every app state: once a worker is let in, only their saved copy
/// is kept; signed out, none is. Startup and the Terms screens decide
/// nothing. Unsent actions are never touched — they wait for their worker.
class WorkPlanAccountWipe {
  WorkPlanAccountWipe(this.work);

  final WorkPlanApi work;
  String? _kept;

  void onAppState(AppState s) {
    final keep = switch (s) {
      Ready(:final worker) => worker.id,
      SignedOut() => '',
      _ => null,
    };
    if (keep == null || keep == _kept) return;
    _kept = keep;
    unawaited(work.keepOnly(keep).catchError((Object e) {
      debugPrint('My Work wipe failed: $e');
      if (_kept == keep) _kept = null; // try again on the next state
    }));
  }
}
