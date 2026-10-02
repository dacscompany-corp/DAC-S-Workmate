import 'package:flutter/foundation.dart';

/// "The live app's drain just sent (or settled) queued rows." Home re-reads
/// today on it, so "Not sent yet" turns into "Saved" without a pull.
class QueueSettled extends ChangeNotifier {
  void fire() => notifyListeners();
}
