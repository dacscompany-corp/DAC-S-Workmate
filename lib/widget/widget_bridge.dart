import 'package:flutter/services.dart';

import 'widget_snapshot.dart';

/// Hands a snapshot to the native widget.
abstract interface class WidgetBridge {
  Future<void> push(WidgetSnapshot snapshot);
}

/// The packages/workmate_widget_bridge plugin. A PLUGIN, not a MainActivity
/// channel: WorkManager's background engine has plugins but no activity, and a
/// background send must update the widget too.
class ChannelWidgetBridge implements WidgetBridge {
  const ChannelWidgetBridge();

  static const _channel = MethodChannel('com.dacs.workmate/widget');

  @override
  Future<void> push(WidgetSnapshot snapshot) => _channel.invokeMethod<void>('push', snapshot.toMap());
}
