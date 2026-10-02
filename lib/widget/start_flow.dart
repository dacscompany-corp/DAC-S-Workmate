import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';

import '../app_controller.dart';
import '../attendance/domain/work_date.dart';

/// Exact names only ("IN" / "OUT", TimeDirection.wire). Anything else is no
/// request, never a guess.
TimeDirection? startFlowFromExtra(String? raw) => switch (raw) {
      'IN' => TimeDirection.timeIn,
      'OUT' => TimeDirection.timeOut,
      _ => null,
    };

/// What to do with a Time In / Time Out asked for from the home screen.
enum StartFlowDecision {
  open,

  /// Home already shows the true state; the widget was behind.
  stayOnHome,

  /// Not now, and not later either: forget it.
  drop,

  /// Not enough known yet to decide.
  wait,
}

/// What Home knows: still loading, and the one action its big button offers.
typedef HomeGlance = ({bool loading, TimeDirection? nextAction});

/// A widget tap, resolved against what the app knows NOW. The flow opens only
/// when Home's nextAction (the same decision Home's big button makes) agrees;
/// otherwise the worker lands on Home, which already shows the right thing,
/// instead of taking a photo the server will refuse. [home] is null wherever
/// Home has not been read yet.
StartFlowDecision resolveStartFlow(TimeDirection request, AppState appState, {required bool flowOpen, HomeGlance? home}) {
  if (appState is Starting) return StartFlowDecision.wait;
  // Login, Terms or the offline gate. Dropped rather than held: after signing
  // in the worker should arrive on Home, not in a camera.
  if (appState is! Ready) return StartFlowDecision.drop;
  // The capture in progress is the worker's: a tap must not throw away a photo.
  if (flowOpen) return StartFlowDecision.drop;
  if (home == null || home.loading) return StartFlowDecision.wait;
  return home.nextAction == request ? StartFlowDecision.open : StartFlowDecision.stayOnHome;
}

/// The one pending widget tap, between the app (which receives it) and Home
/// (which decides it).
class StartFlowInbox extends ChangeNotifier {
  TimeDirection? _pending;
  TimeDirection? get pending => _pending;

  void put(TimeDirection direction) {
    _pending = direction;
    notifyListeners();
  }

  void clear() {
    if (_pending == null) return;
    _pending = null;
    notifyListeners();
  }
}

/// The tap MainActivity received, taken once.
abstract interface class LaunchRequests {
  Future<TimeDirection?> take();
}

class ChannelLaunchRequests implements LaunchRequests {
  const ChannelLaunchRequests();

  static const _channel = MethodChannel('com.dacs.workmate/launch');

  @override
  Future<TimeDirection?> take() async {
    try {
      return startFlowFromExtra(await _channel.invokeMethod<String>('takeStartFlow'));
    } catch (e) {
      debugPrint('No widget request: $e');
      return null;
    }
  }
}
