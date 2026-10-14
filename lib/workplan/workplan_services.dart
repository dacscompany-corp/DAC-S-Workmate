import 'package:flutter/foundation.dart';

import '../requests/data/requests_api.dart';
import '../requests/requests_services.dart' show TakePhoto, realTakePhoto;
import 'data/workplan_api.dart';

/// Everything the My Work screens need, built once in main.dart.
class WorkPlanServices {
  const WorkPlanServices({required this.api, this.takePhoto = realTakePhoto, this.changed, this.requests});

  final WorkPlanApi api;
  final TakePhoto takePhoto;

  /// Fires when the live app's background drain settled queued operations.
  final Listenable? changed;

  /// The worker's own requests, to link a materials problem to one (spec §8);
  /// null when Requests is unavailable.
  final RequestsApi? requests;
}
