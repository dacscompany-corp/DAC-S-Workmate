import 'dart:async';
import 'dart:isolate';
import 'dart:ui';

/// The port name under which the live app's engine offers to drain the queue.
const syncPortName = 'workmate.attendance.sync';

/// Lives in the app's main isolate. WorkManager starts a NEW Flutter engine for
/// every task, so a background task that built its own Supabase client would be
/// a SECOND token refresher over the same stored session: it rotates the refresh
/// token into shared storage while the live app still holds the old one in
/// memory, the app's next refresh fails (refresh_token_already_used) and the
/// worker is signed out. So when the app is alive the background task hands its
/// work to this host instead: one token refresher per process.
class AttendanceSyncHost {
  AttendanceSyncHost({required Future<bool> Function() drain}) : _drain = drain;

  final Future<bool> Function() _drain;
  ReceivePort? _port;
  Future<bool>? _inFlight;
  bool _again = false;

  void register() {
    final current = _port;
    // Already registered and still mapped: re-registering would drop a request in flight.
    if (current != null && IsolateNameServer.lookupPortByName(syncPortName) == current.sendPort) return;
    dispose();
    final port = ReceivePort();
    _port = port;
    IsolateNameServer.removePortNameMapping(syncPortName);
    IsolateNameServer.registerPortWithName(port.sendPort, syncPortName);
    port.listen((message) {
      if (message is! SendPort) return;
      message.send('ack');
      _run().then(message.send);
    });
  }

  /// A drain right now, from this isolate (a request was just queued): it
  /// shares the one in flight, if any.
  Future<bool> drainNow() => _run();

  /// Concurrent requests share ONE drain: never two at once in this isolate.
  /// A call that arrives DURING a drain may be about a row queued after that
  /// drain read its queue (a Time In while requests upload), so the drain
  /// runs once more afterwards and every caller gets the LAST run's result.
  /// It converges: only outside callers ask for a re-run (the drain's own
  /// notices refresh screens without sending), so it stops when they stop.
  Future<bool> _run() {
    final running = _inFlight;
    if (running != null) {
      _again = true;
      return running;
    }
    return _inFlight = () async {
      try {
        var result = false;
        do {
          _again = false;
          try {
            result = await _drain();
          } catch (_) {
            result = false;
          }
        } while (_again);
        return result;
      } finally {
        _inFlight = null;
      }
    }();
  }

  void dispose() {
    final port = _port;
    if (port == null) return;
    IsolateNameServer.removePortNameMapping(syncPortName);
    port.close();
    _port = null;
  }
}

/// Asks the live app (if any) to drain the queue. Null = no live app answered,
/// so the caller must do the work itself; otherwise the drain's result (false =
/// retry). A mapping whose isolate is gone never acks: it is removed.
Future<bool?> delegateToLiveApp({
  Duration ackTimeout = const Duration(seconds: 3),
  Duration resultTimeout = const Duration(minutes: 9),
}) async {
  final host = IsolateNameServer.lookupPortByName(syncPortName);
  if (host == null) return null;
  final reply = ReceivePort();
  try {
    final events = StreamIterator<dynamic>(reply);
    host.send(reply.sendPort);
    final acked = await events.moveNext().timeout(ackTimeout, onTimeout: () => false);
    if (!acked || events.current != 'ack') {
      IsolateNameServer.removePortNameMapping(syncPortName);
      return null;
    }
    final gotResult = await events.moveNext().timeout(resultTimeout, onTimeout: () => false);
    if (!gotResult) return false;
    final result = events.current;
    return result is bool ? result : false;
  } finally {
    reply.close();
  }
}
