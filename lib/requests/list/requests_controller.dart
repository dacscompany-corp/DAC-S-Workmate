import 'package:flutter/foundation.dart';

import '../data/requests_api.dart';
import '../domain/request_draft.dart';
import '../domain/request_failure.dart';
import '../domain/request_op.dart';
import '../domain/request_status.dart';
import '../home/request_updates.dart';

enum RequestFilter { all, drafts, pending, attention }

/// The Requests tab and Home's request card share this one controller, so
/// both always tell the same story.
class RequestsController extends ChangeNotifier {
  RequestsController({required RequestsApi api, DateTime Function()? now})
      : _api = api,
        now = now ?? DateTime.now;

  final RequestsApi _api;
  final DateTime Function() now;

  bool _loading = true;
  bool _disposed = false;
  RequestsView? _view;
  List<RequestDraft> _drafts = const [];
  RequestFailure? _failure;
  RequestFilter _filter = RequestFilter.all;
  Future<void>? _inFlight;
  bool _again = false;

  bool get loading => _loading;
  RequestsView? get view => _view;
  RequestFilter get filter => _filter;

  /// Why the server could not be read; the list may still show the phone's copy.
  RequestFailure? get failure => _failure;

  /// Drafts first (newest first), then everything else newest first.
  List<RequestEntry> get all => [
        for (final d in _drafts) RequestEntry(state: SyncState.draft, draft: d),
        ...?_view?.entries,
      ];

  List<RequestEntry> get rows => all.where((e) => switch (_filter) {
        RequestFilter.all => true,
        RequestFilter.drafts => e.state == SyncState.draft,
        RequestFilter.pending => e.state == SyncState.pending,
        RequestFilter.attention => e.state == SyncState.failed || e.state == SyncState.needsResolution,
      }).toList();

  RequestUpdates get updates => summarizeRequests(all, now());

  RequestEntry? entry(String key) => all.where((e) => e.key == key).firstOrNull;

  void setFilter(RequestFilter f) {
    if (f == _filter) return;
    _filter = f;
    _notify();
  }

  /// Concurrent calls share one read — and a call made DURING a read runs it
  /// once more afterwards, so a change the user just made is never shown
  /// from a read that started before it.
  Future<void> refresh() {
    final running = _inFlight;
    if (running != null) {
      _again = true;
      return running;
    }
    return _inFlight = _loop().whenComplete(() => _inFlight = null);
  }

  Future<void> _loop() async {
    do {
      _again = false;
      await _load();
    } while (_again);
  }

  Future<void> _load() async {
    try {
      final drafts = await _api.drafts();
      final view = await _api.myRequests();
      _drafts = drafts;
      _view = view;
      _failure = view.error == null ? null : RequestFailure.of(view.error!);
    } catch (e) {
      _failure = RequestFailure.of(e);
    } finally {
      _loading = false;
      _notify();
    }
  }

  Future<void> dismissFailed(RequestOp op) async {
    await _api.dismissFailed(op);
    await refresh();
  }

  /// False when the phone refused (see [RequestsApi.returnToDrafts]).
  Future<bool> returnToDrafts(String draftId) async {
    final back = await _api.returnToDrafts(draftId);
    await refresh();
    return back;
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
