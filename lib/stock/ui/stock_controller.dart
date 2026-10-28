import 'package:flutter/foundation.dart';

import '../data/stock_remote.dart';
import '../domain/stock_failure.dart';
import '../domain/stock_models.dart';

/// The Stock tab's state (Q26): online only. Whether stock is usable here at
/// all is the server's `stk_status` — asked on every refresh, so the tab
/// appears the moment the main owner switches stock on and goes when it is
/// off. With no signal the last answer stays and the screen says so.
class StockController extends ChangeNotifier {
  StockController({required this.remote});

  final StockRemote remote;

  StockStatus status = StockStatus.off;
  StockOverview overview = const StockOverview();
  bool loading = false;

  /// The overview was read at least once.
  bool loaded = false;

  /// Why the last refresh failed (no signal, mostly); null after a good one.
  StockFailure? failure;

  bool _disposed = false;
  int _generation = 0;

  bool get enabled => status.enabled;

  Future<void> refresh() async {
    final gen = ++_generation;
    loading = true;
    _notify();
    try {
      final s = await remote.status();
      final ov = s.enabled ? await remote.overview() : const StockOverview();
      // Only the latest refresh shows: an older one answering last changes nothing.
      if (gen != _generation || _disposed) return;
      status = s;
      overview = ov;
      loaded = s.enabled;
      failure = null;
    } catch (e) {
      if (gen != _generation || _disposed) return;
      failure = StockFailure.of(e);
    } finally {
      if (gen == _generation) {
        loading = false;
        _notify();
      }
    }
  }

  void _notify() {
    if (!_disposed) notifyListeners();
  }

  @override
  void dispose() {
    _disposed = true;
    super.dispose();
  }
}
