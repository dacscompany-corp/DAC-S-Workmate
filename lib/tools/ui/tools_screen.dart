import 'package:flutter/material.dart';

import '../../attendance/ui/formats.dart' show clockTime;
import '../../purchasing/ui/purchasing_copy.dart' show BilingualText, bilingualButton;
import '../../ui/failure_notice.dart';
import '../../ui/theme.dart';
import '../data/tool_submitter.dart';
import '../domain/tool_failure.dart';
import '../domain/tool_models.dart';
import 'tool_detail_screen.dart';
import 'tool_forms.dart';
import 'tool_widgets.dart';
import 'tools_controller.dart';
import 'tools_copy.dart';

enum ToolsPartView { mine, team, records }

/// The Tools screen (Stage 3b), opened from Home's My tools card: Mine for
/// everyone; Team and My records for a team leader. Never a peso. A record
/// whose answer was lost waits at the top, and no new one starts until it is
/// resolved (Q22).
class ToolsScreen extends StatefulWidget {
  const ToolsScreen({super.key, required this.controller, required this.submitter});

  final ToolsController controller;
  final ToolSubmitter submitter;

  @override
  State<ToolsScreen> createState() => _ToolsScreenState();
}

class _ToolsScreenState extends State<ToolsScreen> {
  ToolsPartView _part = ToolsPartView.mine;

  ToolsController get _c => widget.controller;
  ToolSubmitter get _s => widget.submitter;

  @override
  void initState() {
    super.initState();
    if (_s.blocked) _s.checkAll();
  }

  Future<void> _after(Future<bool?> recorded) async {
    if (await recorded == true) await _recorded();
  }

  Future<void> _recorded() async {
    await _c.refresh();
    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(key: Key('tool-recorded'), content: Text('Recorded. · Naitala na.')));
    }
  }

  void _refused(ToolFailure f) {
    final copy = toolFailureCopy(f);
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(key: const Key('tool-refused'), content: Text('${copy.english}\n${copy.tagalog}')));
  }

  Future<bool?> _push(Widget screen) => Navigator.of(context).push<bool>(MaterialPageRoute(builder: (_) => screen));

  void _openTool(PhoneTool t, {required bool mine}) =>
      _after(_push(ToolDetailScreen(tool: t, mine: mine, remote: _c.remote, submitter: _s)));

  void _issue() => _after(_push(IssueToolScreen(remote: _c.remote, submitter: _s)));

  void _undo(LeaderRecord r) => _after(_push(UndoRecordScreen(record: r, submitter: _s)));

  @override
  Widget build(BuildContext context) => Scaffold(
        appBar: AppBar(title: const Text('Tools')),
        body: SafeArea(
          child: ListenableBuilder(
            listenable: Listenable.merge([_c, _s]),
            builder: (context, _) {
              final can = !_s.blocked;
              final failure = _c.failure;
              return RefreshIndicator(
                onRefresh: _c.refresh,
                child: ListView(padding: const EdgeInsets.all(16), children: [
                  if (_c.isLeader)
                    SegmentedButton<ToolsPartView>(
                      key: const Key('tools-parts'),
                      showSelectedIcon: false,
                      segments: [
                        ButtonSegment(value: ToolsPartView.mine, label: Text('Mine (${_c.mine.length})')),
                        ButtonSegment(value: ToolsPartView.team, label: Text('Team (${_c.team.length})')),
                        const ButtonSegment(value: ToolsPartView.records, label: Text('My records')),
                      ],
                      selected: {_part},
                      onSelectionChanged: (s) => setState(() => _part = s.first),
                    )
                  else
                    const BilingualText(myToolsTitle, style: TextStyle(fontWeight: FontWeight.w800, fontSize: 21)),
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
                    ToolsPartView.mine => _mine(),
                    ToolsPartView.team => _team(can),
                    ToolsPartView.records => _records(can),
                  },
                  const SizedBox(height: 16),
                  const BilingualText(officeFixes, style: TextStyle(fontSize: 12.5, color: WmColors.textMuted)),
                ]),
              );
            },
          ),
        ),
      );

  Widget _empty(String text) => Padding(
        padding: const EdgeInsets.symmetric(vertical: 32),
        child: Center(child: Text(text, style: const TextStyle(color: WmColors.textMuted))),
      );

  Widget _toolBox(PhoneTool t, {required bool mine}) => ToolBox(
        key: Key('tool-${t.id}'),
        onTap: () => _openTool(t, mine: mine),
        children: [
          Row(children: [
            Expanded(child: Text('${t.label} · ${t.name}', style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 16))),
            const Icon(Icons.chevron_right, color: WmColors.textMuted),
          ]),
          if (t.details.trim().isNotEmpty) Text(t.details, style: const TextStyle(fontSize: 13, color: WmColors.textMuted)),
          if (t.folderName != null) Text('${t.folderName}${t.days == null ? '' : ' · ${heldFor(t.days)}'}'),
          if (t.condition != null && t.condition != ToolCondition.good)
            Text(conditionCopy(t.condition!).english, style: const TextStyle(fontWeight: FontWeight.w700, color: WmColors.brownDeep)),
          if (t.lostPending) const BilingualText(lostPendingCopy, style: TextStyle(fontSize: 13, color: WmColors.brownDeep)),
          for (final k in t.myOpenProblems)
            Text('You reported: ${problemCopy(k).english}', style: const TextStyle(fontSize: 13, color: WmColors.brown)),
        ],
      );

  List<Widget> _mine() {
    if (_c.loaded && _c.mine.isEmpty) return [_empty('No tools with you.')];
    return [for (final t in _c.mine) _toolBox(t, mine: true)];
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
        for (final t in e.value) _toolBox(t, mine: false),
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
