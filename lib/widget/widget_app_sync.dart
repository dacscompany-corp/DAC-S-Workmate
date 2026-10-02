import 'dart:async';

import '../app_controller.dart';

/// Sign-in and sign-out reach the widget. Sign-out matters most: site phones
/// are shared, and a widget still showing the last worker's day after they
/// signed out is exactly the leak the worker cache is careful to avoid.
class WidgetAppSync {
  WidgetAppSync(this._publish);

  final Future<void> Function() _publish;
  Type? _last;

  void onAppState(AppState state) {
    // Starting and the Terms screens are passing states: leave the widget alone.
    if (state is! Ready && state is! SignedOut) return;
    if (state.runtimeType == _last) return;
    _last = state.runtimeType;
    unawaited(_publish());
  }
}
