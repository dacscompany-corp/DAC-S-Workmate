import 'package:flutter/foundation.dart';

import '../data/requests_api.dart';
import '../domain/request_draft.dart';
import '../domain/request_failure.dart';
import '../domain/request_models.dart';

/// One draft being written. Every change is saved on the phone at once, so
/// closing the app or losing signal never loses a typed item (spec §4E).
class ComposeController extends ChangeNotifier {
  ComposeController({required RequestsApi api, required RequestDraft draft})
      : _api = api,
        _draft = draft;

  final RequestsApi _api;
  RequestDraft _draft;
  RequestReferences? _refs;
  RequestFailure? _refsFailure;
  bool _loading = true;
  List<DraftIssue> _issues = const [];
  bool _sending = false;
  RequestFailure? _sendFailure;
  bool _disposed = false;

  RequestDraft get draft => _draft;
  RequestReferences? get refs => _refs;
  RequestFailure? get refsFailure => _refsFailure;
  bool get loading => _loading;

  /// Shown after a Send that was refused on the phone; cleared by any change.
  List<DraftIssue> get issues => _issues;
  bool get sending => _sending;
  RequestFailure? get sendFailure => _sendFailure;

  MyTeam? get team => _refs?.teams.where((t) => t.id == _draft.teamId).firstOrNull;

  /// Naming another member needs the leader of THIS team (spec §3).
  bool get iLead => team?.iLead ?? false;

  /// The chosen place is no longer offered by the server (completed, closed).
  /// Only claimed from a fresh list: a cached one may simply be old.
  bool get destinationClosed {
    final refs = _refs;
    final d = _draft.destination;
    return refs != null && !refs.fromCache && d != null && !refs.destinations.contains(d);
  }

  Future<void> load() async {
    _loading = true;
    _notify();
    try {
      final refs = await _api.references();
      _refs = refs;
      _refsFailure = null;
      if (!refs.fromCache) await _dropLostTeam(refs);
    } catch (e) {
      _refsFailure = RequestFailure.of(e);
    } finally {
      _loading = false;
      _notify();
    }
  }

  /// A team the worker is no longer in (missing from a FRESH list; a cached
  /// one may simply be old) would be refused NOT_IN_TEAM on send. It is
  /// cleared, with its members, so the screen shows what will be sent.
  Future<void> _dropLostTeam(RequestReferences refs) async {
    final id = _draft.teamId;
    if (id == null || refs.teams.any((t) => t.id == id)) return;
    try {
      await setTeam(null);
    } catch (_) {
      // Cleared on screen; the next change saves it again.
    }
  }

  Future<void> setDestination(Destination d) => _change(_draft.copyWith(destination: d));

  /// Members are kept only when the worker leads the new team: the server
  /// accepts a member only from that team's current leader.
  Future<void> setTeam(MyTeam? t) {
    // Only the current leader names members (spec §3): for any other team, none.
    final keep = {if (t != null && t.iLead) for (final m in t.members) m.id};
    return _change(_draft.copyWith(
      teamId: t?.id,
      teamName: t?.name,
      lines: [
        for (final l in _draft.lines) keep.contains(l.memberId) ? l : l.copyWith(memberId: null, memberName: null),
      ],
    ));
  }

  /// Adds the line, or replaces the one with the same id.
  Future<void> putLine(DraftLine line) {
    final i = _draft.lines.indexWhere((l) => l.id == line.id);
    final lines = [..._draft.lines];
    if (i < 0) {
      lines.add(line);
    } else {
      lines[i] = line;
    }
    return _change(_draft.copyWith(lines: lines));
  }

  Future<void> removeLine(String id) async {
    final line = _draft.lines.where((l) => l.id == id).firstOrNull;
    if (line == null) return;
    await _change(_draft.copyWith(lines: _draft.lines.where((l) => l.id != id).toList()));
    for (final p in line.photos) {
      await _api.discardPhoto(p);
    }
  }

  Future<void> setNote(String note) => _change(_draft.copyWith(note: note));

  Future<void> _change(RequestDraft next) async {
    _draft = next;
    _issues = const [];
    _sendFailure = null;
    _notify();
    await _api.saveDraft(next);
  }

  /// True once the draft is queued (the screen then closes). False when
  /// something must be fixed first — [issues] or [sendFailure] say what.
  Future<bool> send() async {
    final issues = draftIssues(_draft);
    if (issues.isNotEmpty) {
      _issues = issues;
      _notify();
      return false;
    }
    _sending = true;
    _notify();
    try {
      await _api.send(_draft);
      return true;
    } on DraftInvalid catch (e) {
      _issues = e.issues;
      return false;
    } catch (e) {
      _sendFailure = RequestFailure.of(e);
      return false;
    } finally {
      _sending = false;
      _notify();
    }
  }

  Future<void> discard() => _api.deleteDraft(_draft);

  void _notify() {
    if (!_disposed) notifyListeners();
  }

  @override
  void dispose() {
    _disposed = true;
    super.dispose();
  }
}
