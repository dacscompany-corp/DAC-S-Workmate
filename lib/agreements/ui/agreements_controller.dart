import 'package:flutter/foundation.dart';

import '../data/agreements_remote.dart';
import '../domain/my_agreement.dart';

/// The My agreements card's and screen's state (Linked Labor). ONLINE ONLY
/// (Q2): the amounts live in this object's memory for one account, and are
/// CLEARED — never kept as a "last known" balance — when:
///   · a fresh read STARTS: nothing old is shown while checking;
///   · a refresh fails (no signal): the screen says it needs signal;
///   · the server refuses (account switched off, not a worker);
///   · the server's list no longer has an agreement (unlinked or reassigned);
///   · the account changes or the person logs out (Home disposes this).
/// Nothing is written to SQLite, preferences or a file.
class AgreementsController extends ChangeNotifier {
  AgreementsController({required this.remote, required this.userId, DateTime Function()? now}) : _now = now ?? DateTime.now;

  final AgreementsRemote remote;

  /// The one account these amounts belong to.
  final String userId;
  final DateTime Function() _now;

  List<MyAgreement> agreements = const [];

  /// When [agreements] were read from the server, in this session; null when none are shown.
  DateTime? fetchedAt;

  /// Why the last refresh failed; null after a good one.
  AgreementsFailure? failure;
  bool loading = false;

  bool _disposed = false;
  int _generation = 0;

  /// Home shows the card only once this session's read found an agreement.
  bool get showCard => agreements.isNotEmpty;
  bool get loaded => fetchedAt != null;

  MyAgreement? byId(String id) {
    for (final a in agreements) {
      if (a.id == id) return a;
    }
    return null;
  }

  Future<void> refresh() async {
    if (_disposed) return;
    final gen = ++_generation;
    // An old figure never stays on screen while the server is asked again —
    // opening the screen, coming back to the app, pulling to refresh — nor
    // after, if the asking fails. The screens show "Checking…" meanwhile.
    _forget();
    failure = null;
    loading = true;
    _notify();
    try {
      final list = await remote.mine(userId: userId);
      if (_stale(gen)) return;
      agreements = List.unmodifiable(list);
      fetchedAt = _now();
      failure = null;
    } catch (e) {
      if (_stale(gen)) return;
      _forget();
      failure = AgreementsFailure.of(e);
    } finally {
      if (gen == _generation && !_disposed) {
        loading = false;
        _notify();
      }
    }
  }

  /// Drops every amount shown, now.
  void clear() {
    _generation++;
    _forget();
    failure = null;
    loading = false;
    _notify();
  }

  void _forget() {
    agreements = const [];
    fetchedAt = null;
  }

  bool _stale(int gen) => gen != _generation || _disposed;

  void _notify() {
    if (!_disposed) notifyListeners();
  }

  @override
  void dispose() {
    _disposed = true;
    _generation++;
    _forget();
    super.dispose();
  }
}
