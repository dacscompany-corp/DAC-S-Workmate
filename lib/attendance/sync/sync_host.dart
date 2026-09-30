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

  void register() {
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

  /// Concurrent requests share ONE drain: never two at once in this isolate.
  Future<bool> _run() {
    return _inFlight ??= () async {
      try {
        return await _drain();
      } catch (_) {
        return false;
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
