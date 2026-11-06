import 'package:flutter/material.dart';

import '../../purchasing/ui/purchasing_copy.dart' show BilingualText, bilingualButton;
import '../../ui/theme.dart';
import '../data/tool_submitter.dart';
import '../data/tools_remote.dart';
import '../domain/tool_failure.dart';
import '../domain/tool_models.dart';
import 'tool_forms.dart';
import 'tool_widgets.dart';
import 'tools_copy.dart';

/// One tool's page: who has it, where, its condition, and its records while
/// that person had it (Q21). A worker's own tool offers Report a problem; a
/// team member's tool offers Hand over and Return to their leader. Pops true
/// once an action was recorded, so the list refreshes.
class ToolDetailScreen extends StatefulWidget {
  const ToolDetailScreen({super.key, required this.tool, required this.mine, required this.remote, required this.submitter});

  /// The tool as the list showed it (fresh or saved): enough to act on.
  final PhoneTool tool;

  /// The caller's own tool (My tools); otherwise a team member's (Team).
  final bool mine;
  final ToolsRemote remote;
  final ToolSubmitter submitter;

  @override
  State<ToolDetailScreen> createState() => _ToolDetailScreenState();
}

class _ToolDetailScreenState extends State<ToolDetailScreen> {
  PhoneTool? _full;
  ToolFailure? _failure;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() => _failure = null);
    try {
      final t = widget.mine ? await widget.remote.myTool(widget.tool.id) : await widget.remote.teamTool(widget.tool.id);
      if (mounted) setState(() => _full = t);
    } catch (e) {
      if (mounted) setState(() => _failure = ToolFailure.of(e));
    }
  }

  Future<void> _open(Widget form) async {
    final done = await Navigator.of(context).push<bool>(MaterialPageRoute(builder: (_) => form));
    if (done == true && mounted) Navigator.of(context).pop(true);
  }

  @override
  Widget build(BuildContext context) {
    final t = _full?.held == true ? _full! : widget.tool;
    final s = widget.submitter;
    return Scaffold(
      appBar: AppBar(title: Text(t.label)),
      body: SafeArea(
        child: ListenableBuilder(
          listenable: s,
          builder: (context, _) {
            final can = !s.blocked;
            return RefreshIndicator(
              onRefresh: _load,
              child: ListView(padding: const EdgeInsets.all(16), children: [
                Text(t.name, style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 21)),
                if (t.details.trim().isNotEmpty) Text(t.details, style: const TextStyle(color: WmColors.textMuted)),
                const SizedBox(height: 8),
                if (t.holderName != null) Text('With ${t.holderName}', style: const TextStyle(fontWeight: FontWeight.w700)),
                if (t.folderName != null) Text('${t.folderName}${t.days == null ? '' : ' · ${heldFor(t.days)}'}'),
                if (t.condition != null && t.condition != ToolCondition.good)
                  Text(conditionCopy(t.condition!).english, style: const TextStyle(fontWeight: FontWeight.w700, color: WmColors.brownDeep)),
                if (t.lostPending) ...[
                  const SizedBox(height: 6),
                  const BilingualText(lostPendingCopy, style: TextStyle(fontWeight: FontWeight.w700, color: WmColors.brownDeep)),
                ],
                for (final k in t.myOpenProblems)
                  Text('You reported: ${problemCopy(k).english}', style: const TextStyle(fontSize: 13, color: WmColors.brown)),
                if (t.isIssued) ...[
                  const SizedBox(height: 14),
                  if (!can) const BilingualText(finishFirst, key: Key('tool-finish-first'), style: TextStyle(fontSize: 13, color: WmColors.textMuted)),
                  if (widget.mine)
                    bilingualButton(reportLabel, can ? () => _open(ReportProblemScreen(tool: t, submitter: s)) : null, key: const Key('tool-report'))
                  else ...[
                    if (t.condition == ToolCondition.good)
                      bilingualButton(handoverLabel, can ? () => _open(HandoverToolScreen(tool: t, remote: widget.remote, submitter: s)) : null,
                          filled: true, key: const Key('tool-handover'))
                    else
                      const BilingualText(needsRepairStays, style: TextStyle(fontSize: 13, color: WmColors.brownDeep)),
                    const SizedBox(height: 8),
                    bilingualButton(returnToolLabel, can ? () => _open(ReturnToolScreen(tool: t, submitter: s)) : null, key: const Key('tool-return')),
                  ],
                ],
                const ToolFieldLabel('History'),
                if (_failure != null)
                  BilingualText(_failure == ToolFailure.noConnection ? historyNeedsSignal : toolFailureCopy(_failure!),
                      key: const Key('tool-history-failure'), style: const TextStyle(fontSize: 13, color: WmColors.danger))
                else if (_full == null)
                  const LinearProgressIndicator()
                else
                  for (final r in _full!.records) _RecordRow(record: r),
              ]),
            );
          },
        ),
      ),
    );
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
