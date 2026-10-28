import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';

import '../requests/camera/request_camera_screen.dart';
import '../stock/data/stock_pending_store.dart';
import '../stock/data/stock_remote.dart';
import 'data/purchasing_api.dart';

/// Opens the camera or the gallery; the chosen file's path, or null.
typedef PickReceipt = Future<String?> Function(BuildContext context);

Future<String?> realTakeReceipt(BuildContext context) => Navigator.of(context).push<String>(
      MaterialPageRoute(builder: (_) => const RequestCameraScreen(title: 'Photo of the receipt'), fullscreenDialog: true),
    );

/// Q8: a photo already on the phone (a receipt sent by chat, a screenshot).
/// image_picker hands back a COPY in the app's cache, which the repository
/// then files and deletes.
Future<String?> realPickReceipt(BuildContext context) async =>
    (await ImagePicker().pickImage(source: ImageSource.gallery, requestFullMetadata: false))?.path;

/// Everything the buying screens need, built once in main.dart.
class PurchasingServices {
  const PurchasingServices({
    required this.api,
    this.changed,
    this.takePhoto = realTakeReceipt,
    this.pickPhoto = realPickReceipt,
    this.stock,
    this.stockStore,
  });

  final PurchasingApi api;

  /// Fires when the live app's background drain settled queued purchases.
  final Listenable? changed;

  final PickReceipt takePhoto;
  final PickReceipt pickPhoto;

  /// 2B-b: the stock server; null leaves the phone as it was before stock.
  final StockRemote? stock;

  /// Where stock records wait on the phone until the server settles them
  /// (R101, R104): the phone's settings file. Stock is offered only with both.
  final StockPendingStore? stockStore;
}
