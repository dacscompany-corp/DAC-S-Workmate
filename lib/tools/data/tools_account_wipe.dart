import 'dart:async';

import 'package:flutter/foundation.dart';

import '../../app_controller.dart';
import 'tools_saved_copy.dart';

/// Account switching must not reveal another worker's tools (as My Work,
/// spec §11). Fed every app state: once a worker is let in, only their saved
/// copy is kept; signed out, none is. Startup and the Terms screens decide
/// nothing. Unresolved tool records are never touched — they wait for their
/// own account.
class ToolsAccountWipe {
  ToolsAccountWipe(this.saved);

  final ToolsSavedCopy saved;
  String? _kept;

  void onAppState(AppState s) {
    final keep = switch (s) {
      Ready(:final worker) => worker.id,
      SignedOut() => '',
      _ => null,
    };
    if (keep == null || keep == _kept) return;
    _kept = keep;
    unawaited(saved.keepOnly(keep).catchError((Object e) {
      debugPrint('Tools wipe failed: $e');
      if (_kept == keep) _kept = null; // try again on the next state
    }));
  }
}
