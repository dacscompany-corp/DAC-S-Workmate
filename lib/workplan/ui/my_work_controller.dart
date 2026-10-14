import 'package:flutter/foundation.dart';

import '../../attendance/domain/work_date.dart';
import '../data/workplan_api.dart';
import '../domain/wp_failure.dart';
import '../domain/wp_op.dart';
import '../domain/wp_rules.dart';
import '../domain/wp_task.dart';

/// The My Work tab, its task screens and Home's card share this one
/// controller, so all of them always tell the same story.
class MyWorkController extends ChangeNotifier {
  MyWorkController({required WorkPlanApi api, DateTime Function()? now})
      : _api = api,
        now = now ?? DateTime.now;

  final WorkPlanApi _api;
  final DateTime Function() now;

  bool _loading = true;
  bool _disposed = false;
  WorkPlanView _view = const WorkPlanView();
  WpFailure? _failure;
  Future<void>? _inFlight;
  bool _again = false;

  WorkPlanApi get api => _api;
  bool get loading => _loading;
  WorkPlanView get view => _view;

  /// Why the server could not be read; the list may still show the phone's copy.
  WpFailure? get failure => _failure;

  /// Manila's calendar date: "today" on a site is never the phone's UTC day.
  String get today => WorkDate.of(now()).iso;

  /// The tasks of one section, the most pressing first: to read / to check,
  /// then by planned start (undated last), then title.
  List<WpEntry> group(WpGroup g) {
    final rows = _view.entries.where((e) => groupOf(e, today) == g).toList();
    int rank(WpEntry e) => (e.toRead || e.toCheck) ? 0 : 1;
    rows.sort((a, b) {
      final r = rank(a).compareTo(rank(b));
      if (r != 0) return r;
      final sa = a.task.plannedStart ?? '9999', sb = b.task.plannedStart ?? '9999';
      final s = sa.compareTo(sb);
      return s != 0 ? s : a.task.title.compareTo(b.task.title);
    });
    return rows;
  }

  WpEntry? entry(String taskId) => _view.entry(taskId);

  WpUpdates get updates => summarizeWork(
        _view.entries,
        notes: _view.notes.length,
        otherPending: visiblePending(_view.otherPending).length + _view.pendingProposals.length,
        otherFailed: visibleFailures(_view.otherFailed).length,
      );

  /// Concurrent calls share one read — and a call made DURING a read runs it
  /// once more afterwards, so an action just taken is never shown from a
  /// read that started before it.
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
    } while (_again && !_disposed);
  }

  Future<void> _load() async {
    try {
      final view = await _api.load();
      _view = view;
      _failure = view.error == null ? null : WpFailure.of(view.error!);
    } catch (e) {
      _failure = WpFailure.of(e);
    } finally {
      _loading = false;
      _notify();
    }
  }

  /// Runs an action (queued on the phone first) and re-reads.
  Future<void> act(Future<void> Function(WorkPlanApi api) action) async {
    await action(_api);
    await refresh();
  }

  Future<void> acknowledge(WpTask t) => act((a) => a.acknowledge(t));
  Future<void> startWork(WpTask t) => act((a) => a.startWork(t));
  Future<void> dismissFailed(WpOp op) => act((a) => a.dismissFailed(op));

  void _notify() {
    if (!_disposed) notifyListeners();
  }

  @override
  void dispose() {
    _disposed = true;
    super.dispose();
  }
}
