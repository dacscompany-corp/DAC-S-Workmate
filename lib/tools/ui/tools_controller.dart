import 'package:flutter/foundation.dart';

import '../data/tools_remote.dart';
import '../data/tools_saved_copy.dart';
import '../domain/tool_failure.dart';
import '../domain/tool_models.dart';

/// Whether tools are usable here, as the server last answered.
enum ToolsAccess {
  /// Not answered yet (no signal since the app opened).
  unknown,
  on,

  /// TOOLS_OFF: the main owner hasn't switched tools on (or switched them off).
  off,

  /// NOT_A_REQUESTER: not a worker or team leader of a company.
  notCrew,
}

/// The Tools screen's and the Home card's state (Stage 3b). Reads only;
/// writes go through ToolSubmitter. The server decides everything: tools on
/// or off, who leads a team now (NOT_LEADER), what they see. With no signal
/// the last good lists stay — or this account's saved copy, with its time.
class ToolsController extends ChangeNotifier {
  ToolsController({required this.remote, required this.userId, required this.isLeader, this.saved, DateTime Function()? now})
      : _now = now ?? DateTime.now;

  final ToolsRemote remote;
  final String userId;

  /// The Team Leader role: only then are the team lists asked for. The
  /// server still decides whether they lead a team now.
  final bool isLeader;
  final ToolsSavedCopy? saved;
  final DateTime Function() _now;

  ToolsAccess access = ToolsAccess.unknown;
  List<PhoneTool> mine = const [];
  List<PhoneTool> team = const [];
  List<LeaderRecord> records = const [];

  /// When the lists shown were read: now, or their saved copy's time.
  DateTime? mineAt;
  DateTime? teamAt;

  /// The lists shown are a saved copy (the last refresh couldn't reach the server).
  bool mineSaved = false;
  bool teamSaved = false;

  /// A Team Leader who leads a team now (the server answered their team).
  bool leading = false;

  /// The server said NOT_LEADER: the role, but no team led now.
  bool notLeading = false;
  bool loading = false;

  /// Why the last refresh failed (no signal, mostly); null after a good one.
  ToolFailure? failure;

  bool _disposed = false;
  int _generation = 0;

  bool get loaded => mineAt != null;

  /// The Home card shows once the server let them in, or a saved copy exists.
  bool get showCard => access == ToolsAccess.on || (access == ToolsAccess.unknown && loaded);

  int get openProblems => mine.fold(0, (n, t) => n + t.myOpenProblems.length);

  Future<void> refresh() async {
    final gen = ++_generation;
    loading = true;
    _notify();
    try {
      await _readMine(gen);
      if (gen == _generation && isLeader && access != ToolsAccess.off && access != ToolsAccess.notCrew) await _readTeam(gen);
    } finally {
      if (gen == _generation) {
        loading = false;
        _notify();
      }
    }
  }

  bool _stale(int gen) => gen != _generation || _disposed;

  Future<void> _readMine(int gen) async {
    try {
      final m = await remote.myTools();
      if (_stale(gen)) return;
      final at = _now();
      mine = m;
      mineAt = at;
      mineSaved = false;
      access = ToolsAccess.on;
      failure = null;
      await _save(ToolsPart.mine, [for (final t in m) t.raw], at);
    } catch (e) {
      if (_stale(gen)) return;
      final f = ToolFailure.of(e);
      if (f == ToolFailure.toolsOff || f == ToolFailure.notCrew) {
        access = f == ToolFailure.toolsOff ? ToolsAccess.off : ToolsAccess.notCrew;
        _clear();
        failure = null;
        await _drop(ToolsPart.values);
        return;
      }
      failure = f;
      if (!loaded) _fromSaved(ToolsPart.mine);
    }
  }

  Future<void> _readTeam(int gen) async {
    try {
      final t = await remote.teamTools();
      final r = await remote.myRecords();
      if (_stale(gen)) return;
      final at = _now();
      team = t;
      records = r;
      teamAt = at;
      teamSaved = false;
      leading = true;
      notLeading = false;
      await _save(ToolsPart.team, [for (final x in t) x.raw], at);
      await _save(ToolsPart.records, [for (final x in r) x.raw], at);
    } catch (e) {
      if (_stale(gen)) return;
      final f = ToolFailure.of(e);
      if (f == ToolFailure.notLeader || f == ToolFailure.toolsOff || f == ToolFailure.notCrew) {
        leading = false;
        notLeading = f == ToolFailure.notLeader;
        team = const [];
        records = const [];
        teamAt = null;
        await _drop(const [ToolsPart.team, ToolsPart.records]);
        return;
      }
      failure ??= f;
      if (teamAt == null) _fromSaved(ToolsPart.team);
    }
  }

  void _fromSaved(ToolsPart part) {
    final s = saved;
    if (s == null) return;
    if (part == ToolsPart.mine) {
      final copy = s.load(userId, ToolsPart.mine);
      if (copy == null) return;
      mine = copy.rows.map(PhoneTool.fromJson).toList();
      mineAt = copy.at;
      mineSaved = true;
    } else {
      final t = s.load(userId, ToolsPart.team);
      if (t == null) return;
      team = t.rows.map(PhoneTool.fromJson).toList();
      records = (s.load(userId, ToolsPart.records)?.rows ?? const []).map(LeaderRecord.fromJson).toList();
      teamAt = t.at;
      teamSaved = true;
      leading = true;
    }
  }

  void _clear() {
    mine = const [];
    team = const [];
    records = const [];
    mineAt = null;
    teamAt = null;
    leading = false;
  }

  Future<void> _save(ToolsPart part, List<Map<String, dynamic>> rows, DateTime at) async {
    try {
      await saved?.save(userId, part, rows, at);
    } catch (e) {
      debugPrint('Tools saved copy not kept: $e');
    }
  }

  Future<void> _drop(List<ToolsPart> parts) async {
    try {
      for (final p in parts) {
        await saved?.drop(userId, p);
      }
    } catch (e) {
      debugPrint('Tools saved copy not dropped: $e');
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
