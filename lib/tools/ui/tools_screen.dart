import 'package:flutter/material.dart';

import '../../attendance/ui/formats.dart' show clockTime;
import '../../purchasing/ui/purchasing_copy.dart' show BilingualText, bilingualButton;
import '../../ui/failure_notice.dart';
import '../../ui/theme.dart';
import '../../ui/wm_chips.dart';
import '../../ui/wm_sheet.dart';
import '../data/tool_submitter.dart';
import '../domain/tool_failure.dart';
import '../domain/tool_models.dart';
import 'tool_forms.dart';
import 'tool_widgets.dart';
import 'tools_controller.dart';
import 'tools_copy.dart';

enum ToolsPartView { mine, team, records }

/// Opens the Tools sheet (Home's My tools shortcut). It reads again as it
/// opens: a sheet has no pull-down.
Future<void> showToolsSheet(BuildContext context, ToolsController controller, ToolSubmitter submitter) {
  controller.refresh();
  return showWmSheet<void>(context, builder: (_) => ToolsSheet(controller: controller, submitter: submitter));
}

/// The Tools sheet (Stage 3b, a sheet since Phase 5): Mine for everyone; Team
/// and My records for a team leader. A tool card opens in place with the
/// actions allowed and its history. Never a peso. A record whose answer was
/// lost waits at the top, and no new one starts until it is resolved (Q22).
class ToolsSheet extends StatefulWidget {
  const ToolsSheet({super.key, required this.controller, required this.submitter});

  final ToolsController controller;
  final ToolSubmitter submitter;

  @override
  State<ToolsSheet> createState() => _ToolsSheetState();
}

class _ToolsSheetState extends State<ToolsSheet> {
  ToolsPartView _part = ToolsPartView.mine;

  /// The card that is open (one at a time), which list it came from, and the
  /// fresh read of it (its history).
  String? _openId;
  bool _openMine = true;
  PhoneTool? _full;
  ToolFailure? _historyFailure;
  int _loadSeq = 0;

  /// "Recorded." / a refusal, pinned at the foot of the sheet where it stays
  /// in view whatever the list is scrolled to: a SnackBar would sit in the
  /// Scaffold behind the sheet, under its dimmed barrier.
  Key? _noteKey;
  String? _noteText;

  ToolsController get _c => widget.controller;
  ToolSubmitter get _s => widget.submitter;

  @override
  void initState() {
    super.initState();
    // After this frame: Home's inbox and badge listen to the submitter, and
    // checkAll notifies before its first await.
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted && _s.blocked) _s.checkAll();
    });
  }

  Future<void> _after(Future<bool?> recorded) async {
    if (await recorded == true) await _recorded();
  }

  Future<void> _recorded() async {
    await _c.refresh();
    if (!mounted) return;
    setState(() {
      _noteKey = const Key('tool-recorded');
      _noteText = 'Recorded. · Naitala na.';
      // The open card starts again from the fresh list: what was read before
      // the record (holder, condition, history) is not shown after it.
      _full = null;
      _historyFailure = null;
    });
    final id = _openId;
    final open = id == null ? null : [..._c.mine, ..._c.team].where((t) => t.id == id).firstOrNull;
    if (open == null) {
      setState(() => _openId = null);
    } else {
      _load(open, _openMine);
    }
  }

  void _refused(ToolFailure f) {
    final copy = toolFailureCopy(f);
    setState(() {
      _noteKey = const Key('tool-refused');
      _noteText = '${copy.english}\n${copy.tagalog}';
    });
  }

  Future<bool?> _push(Widget screen) => Navigator.of(context).push<bool>(MaterialPageRoute(builder: (_) => screen));

  /// A new form starts with no note of the last one left on the sheet.
  void _act(Widget form) {
    setState(() => _noteText = null);
    _after(_push(form));
  }

  void _issue() => _act(IssueToolScreen(remote: _c.remote, submitter: _s));

  void _undo(LeaderRecord r) => _act(UndoRecordScreen(record: r, submitter: _s));

  void _toggle(PhoneTool t, {required bool mine}) {
    if (_openId == t.id) {
      setState(() => _openId = null);
      return;
    }
    setState(() {
      _openId = t.id;
      _openMine = mine;
      _full = null;
      _historyFailure = null;
      _noteText = null;
    });
    _load(t, mine);
  }

  Future<void> _load(PhoneTool t, bool mine) async {
    final seq = ++_loadSeq;
    setState(() => _historyFailure = null);
    try {
      final full = mine ? await _c.remote.myTool(t.id) : await _c.remote.teamTool(t.id);
      if (mounted && seq == _loadSeq && _openId == t.id) setState(() => _full = full);
    } catch (e) {
      if (mounted && seq == _loadSeq && _openId == t.id) setState(() => _historyFailure = ToolFailure.of(e));
    }
  }

  @override
  Widget build(BuildContext context) => ListenableBuilder(
        listenable: Listenable.merge([_c, _s]),
        builder: (context, _) {
          final can = !_s.blocked;
          final failure = _c.failure;
          final noteText = _noteText;
          return WmSheetFrame(
            key: const Key('tools-sheet'),
            title: _c.isLeader ? 'Tools' : myToolsTitle.english,
            subtitle: _c.isLeader ? null : myToolsTitle.tagalog,
            tall: true,
            footer: noteText == null
                ? null
                : Text(noteText,
                    key: _noteKey,
                    style: TextStyle(
                        fontSize: 13.5, fontWeight: FontWeight.w700, color: _noteKey == const Key('tool-refused') ? WmColors.danger : WmColors.green)),
            children: [
              if (_c.isLeader)
                WmSegmented<ToolsPartView>(
                  key: const Key('tools-parts'),
                  selected: _part,
                  onChanged: (v) => setState(() {
                    _part = v;
                    _openId = null;
                    _noteText = null;
                  }),
                  segments: [
                    (ToolsPartView.mine, 'Mine (${_c.mine.length})', const Key('tools-part-mine')),
                    (ToolsPartView.team, 'Team (${_c.team.length})', const Key('tools-part-team')),
                    (ToolsPartView.records, 'My records', const Key('tools-part-records')),
                  ],
                ),
              if (failure != null) ...[
                const SizedBox(height: 10),
                FailureNotice(
                  key: const Key('tools-signal'),
                  english: failure == ToolFailure.noConnection ? toolsNeedSignal.english : toolFailureCopy(failure).english,
                  tagalog: failure == ToolFailure.noConnection ? toolsNeedSignal.tagalog : toolFailureCopy(failure).tagalog,
                  actions: [noticeAction('Try again · Subukan ulit', _c.refresh)],
                ),
              ],
              if (_c.mineSaved && _c.mineAt != null)
                Padding(
                  padding: const EdgeInsets.only(top: 8),
                  child: Text('Saved copy from ${clockTime(_c.mineAt!)}',
                      key: const Key('tools-saved-copy'), style: const TextStyle(fontSize: 13, color: WmColors.textMuted)),
                ),
              for (final u in _s.unresolved)
                Padding(
                  padding: const EdgeInsets.only(top: 10),
                  child: ToolUnresolvedBox(submitter: _s, opId: u.opId, onRecorded: _recorded, onSettledNotRecorded: _refused),
                ),
              for (final u in _s.unreadable)
                Padding(
                  padding: const EdgeInsets.only(top: 10),
                  child: ToolUnreadableBox(submitter: _s, opId: u.opId!, onRecorded: _recorded, onSettledNotRecorded: _refused),
                ),
              if (_s.recoveryNeeded)
                Padding(
                  padding: const EdgeInsets.only(top: 10),
                  child: FailureNotice(key: const Key('tools-recovery'), english: recoveryLabel.english, tagalog: recoveryLabel.tagalog),
                ),
              if (_s.blocked && !_s.recoveryNeeded) ...[
                const SizedBox(height: 8),
                const BilingualText(finishFirst, key: Key('tools-finish-first'), style: TextStyle(fontSize: 13, color: WmColors.textMuted)),
              ],
              if (_c.access == ToolsAccess.off) ...[
                const SizedBox(height: 10),
                const BilingualText(toolsOffNow, style: TextStyle(fontSize: 13, color: WmColors.textMuted)),
              ],
              if (_c.loading && !_c.loaded) const Padding(padding: EdgeInsets.all(32), child: Center(child: CircularProgressIndicator())),
              ...switch (_part) {
                ToolsPartView.mine => _mine(can),
                ToolsPartView.team => _team(can),
                ToolsPartView.records => _records(can),
              },
              const SizedBox(height: 16),
              const BilingualText(officeFixes, style: TextStyle(fontSize: 12.5, color: WmColors.textMuted)),
            ],
          );
        },
      );

  Widget _empty(String text) => Padding(
        padding: const EdgeInsets.symmetric(vertical: 32),
        child: Center(child: Text(text, style: const TextStyle(color: WmColors.textMuted))),
      );

  /// One tool: the closed card is the old box with an expand arrow; opened, it
  /// adds exactly what the old tool page showed — the actions allowed and the
  /// history.
  Widget _toolCard(PhoneTool t, {required bool mine, required bool can}) {
    final open = _openId == t.id;
    final full = open && _full?.held == true ? _full! : t;
    return Card(
      margin: const EdgeInsets.only(top: 10),
      color: Colors.white,
      clipBehavior: Clip.antiAlias,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16), side: const BorderSide(color: WmColors.border)),
      child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        InkWell(
          key: Key('tool-${t.id}'),
          onTap: () => _toggle(t, mine: mine),
          child: Padding(
            padding: const EdgeInsets.all(14),
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Row(children: [
                Expanded(child: Text('${t.label} · ${t.name}', style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 16))),
                Icon(open ? Icons.expand_less : Icons.expand_more, color: WmColors.textMuted),
              ]),
              if (t.details.trim().isNotEmpty) Text(t.details, style: const TextStyle(fontSize: 13, color: WmColors.textMuted)),
              if (t.folderName != null) Text('${t.folderName}${t.days == null ? '' : ' · ${heldFor(t.days)}'}'),
              if (t.condition != null && t.condition != ToolCondition.good)
                Text(conditionCopy(t.condition!).english, style: const TextStyle(fontWeight: FontWeight.w700, color: WmColors.brownDeep)),
              if (t.lostPending) const BilingualText(lostPendingCopy, style: TextStyle(fontSize: 13, color: WmColors.brownDeep)),
              for (final k in t.myOpenProblems)
                Text('You reported: ${problemCopy(k).english}', style: const TextStyle(fontSize: 13, color: WmColors.brown)),
            ]),
          ),
        ),
        if (open)
          Padding(
            padding: const EdgeInsets.fromLTRB(14, 0, 14, 14),
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              if (full.holderName != null) Text('With ${full.holderName}', style: const TextStyle(fontWeight: FontWeight.w700)),
              if (full.isIssued) ...[
                const SizedBox(height: 14),
                if (!can) const BilingualText(finishFirst, key: Key('tool-finish-first'), style: TextStyle(fontSize: 13, color: WmColors.textMuted)),
                if (mine)
                  bilingualButton(reportLabel, can ? () => _act(ReportProblemScreen(tool: full, submitter: _s)) : null, key: const Key('tool-report'))
                else ...[
                  if (full.condition == ToolCondition.good)
                    bilingualButton(handoverLabel, can ? () => _act(HandoverToolScreen(tool: full, remote: _c.remote, submitter: _s)) : null,
                        filled: true, key: const Key('tool-handover'))
                  else
                    const BilingualText(needsRepairStays, style: TextStyle(fontSize: 13, color: WmColors.brownDeep)),
                  const SizedBox(height: 8),
                  bilingualButton(returnToolLabel, can ? () => _act(ReturnToolScreen(tool: full, submitter: _s)) : null, key: const Key('tool-return')),
                ],
              ],
              const ToolFieldLabel('History'),
              if (_historyFailure != null)
                BilingualText(_historyFailure == ToolFailure.noConnection ? historyNeedsSignal : toolFailureCopy(_historyFailure!),
                    key: const Key('tool-history-failure'), style: const TextStyle(fontSize: 13, color: WmColors.danger))
              else if (_full == null)
                const LinearProgressIndicator()
              else
                for (final r in _full!.records) _RecordRow(record: r),
            ]),
          ),
      ]),
    );
  }

  List<Widget> _mine(bool can) {
    if (_c.loaded && _c.mine.isEmpty) return [_empty('No tools with you.')];
    return [for (final t in _c.mine) _toolCard(t, mine: true, can: can)];
  }

  List<Widget> _team(bool can) {
    if (_c.notLeading) {
      final copy = toolFailureCopy(ToolFailure.notLeader);
      return [
        Padding(
          padding: const EdgeInsets.only(top: 12),
          child: BilingualText(copy, key: const Key('tools-not-leading'), style: const TextStyle(fontSize: 13, color: WmColors.textMuted)),
        ),
      ];
    }
    final byPerson = <String, List<PhoneTool>>{};
    for (final t in _c.team) {
      byPerson.putIfAbsent(t.holderName ?? '—', () => []).add(t);
    }
    return [
      if (_c.leading) ...[
        const SizedBox(height: 12),
        bilingualButton(issueToolLabel, can ? _issue : null, filled: true, key: const Key('tools-issue')),
      ],
      if (_c.teamSaved && _c.teamAt != null)
        Padding(
          padding: const EdgeInsets.only(top: 8),
          child: Text('Saved copy from ${clockTime(_c.teamAt!)}', style: const TextStyle(fontSize: 13, color: WmColors.textMuted)),
        ),
      if (_c.leading && _c.team.isEmpty) _empty('No tools out with your team.'),
      for (final e in byPerson.entries) ...[
        Padding(
          padding: const EdgeInsets.only(top: 14),
          child: Text(e.key, style: const TextStyle(fontWeight: FontWeight.w700, color: WmColors.textSecondary)),
        ),
        for (final t in e.value) _toolCard(t, mine: false, can: can),
      ],
    ];
  }

  List<Widget> _records(bool can) {
    if (_c.notLeading) return _team(can);
    if (_c.leading && _c.records.isEmpty) return [_empty('Nothing recorded yet.')];
    return [
      for (final r in _c.records)
        ToolBox(
          key: Key('record-${r.id}'),
          children: [
            Row(children: [
              Expanded(child: Text(recordKind(r.kind), style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 15))),
              Text(recordTime(r.at), style: const TextStyle(fontSize: 12.5, color: WmColors.textMuted)),
            ]),
            Text('${r.label} · ${r.itemName}'),
            Text([if (r.holderName != null) r.holderName!, if (r.folderName != null) r.folderName!].join(' · '),
                style: const TextStyle(fontSize: 13, color: WmColors.textMuted)),
            if (r.reversed) const Text('Undone', style: TextStyle(fontSize: 13, fontWeight: FontWeight.w700, color: WmColors.brownDeep)),
            if (r.canReverse && !r.reversed && !_c.teamSaved) ...[
              const SizedBox(height: 8),
              bilingualButton(undoLabel, can ? () => _undo(r) : null, key: Key('undo-${r.id}')),
            ],
          ],
        ),
    ];
  }
}

class _RecordRow extends StatelessWidget {
  const _RecordRow({required this.record});
  final ToolRecord record;

  @override
  Widget build(BuildContext context) {
    final r = record;
    final state = recordState(status: r.status, reversed: r.reversed);
    final who = [if (r.fromName != null) 'from ${r.fromName}', if (r.toName != null) 'to ${r.toName}'].join(' ');
    return Padding(
      padding: const EdgeInsets.only(top: 8),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Row(children: [
          Expanded(child: Text(recordKind(r.kind), style: const TextStyle(fontWeight: FontWeight.w700))),
          Text(recordTime(r.at), style: const TextStyle(fontSize: 12.5, color: WmColors.textMuted)),
        ]),
        Text([if (who.isNotEmpty) who, if (r.folderName != null) r.folderName!, if (r.condition != null) conditionCopy(r.condition!).english]
            .join(' · ')),
        if (state != null) Text(state, style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w700, color: WmColors.brownDeep)),
      ]),
    );
  }
}
