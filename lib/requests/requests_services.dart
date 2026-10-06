import 'package:flutter/material.dart';

import 'camera/request_camera_screen.dart';
import 'data/requests_api.dart';

/// Opens the camera; the raw capture's path, or null when the worker backed out.
typedef TakePhoto = Future<String?> Function(BuildContext context);

Future<String?> realTakePhoto(BuildContext context) => Navigator.of(context).push<String>(
      MaterialPageRoute(builder: (_) => const RequestCameraScreen(), fullscreenDialog: true),
    );

/// Everything the Requests screens need, built once in main.dart.
class RequestsServices {
  const RequestsServices({required this.api, this.takePhoto = realTakePhoto, this.changed});

  final RequestsApi api;
  final TakePhoto takePhoto;

  /// Fires when the live app's background drain settled queued operations.
  final Listenable? changed;
}
