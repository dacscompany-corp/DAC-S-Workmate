/// What the home-screen widget is told about today. Deliberately says nothing
/// about WHO -- no name, no project: a site phone lies on a table in front of
/// everyone, and the widget is readable without unlocking it.
///
/// The native side (TimeWidgetProvider, WidgetRules.kt) turns this into the
/// card, and decides "is this still today?" itself at every redraw, so a
/// snapshot from yesterday rolls over at Manila midnight with no app running.
class WidgetSnapshot {
  const WidgetSnapshot({
    required this.signedIn,
    this.workDate,
    this.status,
    this.timeInAt,
    this.timeOutAt,
    this.notSentYet = false,
    this.readFailed = false,
  });

  const WidgetSnapshot.signedOut() : this(signedIn: false);

  final bool signedIn;

  /// The day the snapshot describes (ISO, Manila).
  final String? workDate;

  /// The record's status name ('working', 'complete', 'abandoned', 'unknown'); null = no record that day.
  final String? status;
  final DateTime? timeInAt;
  final DateTime? timeOutAt;

  /// This worker still has a submission queued on the phone.
  final bool notSentYet;

  /// The phone's own copy could not be read: the widget says so and guesses nothing.
  final bool readFailed;

  Map<String, Object?> toMap() => {
        'signedIn': signedIn,
        'workDate': workDate,
        'status': status,
        'timeInAt': timeInAt?.millisecondsSinceEpoch,
        'timeOutAt': timeOutAt?.millisecondsSinceEpoch,
        'notSentYet': notSentYet,
        'readFailed': readFailed,
      };
}
