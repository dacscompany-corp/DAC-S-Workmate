import 'dart:async';

/// "The server just said this build is too old." Fired by
/// [WorkMateHttpClient] on APP_UPDATE_REQUIRED (0077) so the update screen
/// appears the moment the office publishes, not at the next launch.
class UpdateNudges {
  final _events = StreamController<void>.broadcast();

  Stream<void> get events => _events.stream;

  void nudge() => _events.add(null);
}
