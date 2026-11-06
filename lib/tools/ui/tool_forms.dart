import 'package:flutter/material.dart';

import '../../attendance/ui/attendance_copy.dart' show Bilingual;
import '../../purchasing/ui/purchasing_copy.dart' show BilingualText;
import '../../ui/failure_notice.dart';
import '../../ui/theme.dart';
import '../data/tool_submitter.dart';
import '../data/tools_remote.dart';
import '../domain/tool_failure.dart';
import '../domain/tool_models.dart';
import '../domain/tool_submission.dart';
import 'tool_widgets.dart';
import 'tools_copy.dart';

// The five tool forms (Q22): each checks what the phone can, then sends
// through ToolSubmitter, and locks if the answer is lost. Notes: 300
// characters at most (pur_note); an undo's reason 1 to 500 (pur_reason).

const _noteMax = 300;
const _reasonMax = 500;

List<ToolFailure> _noteProblems(String note) => [if (note.trim().length > _noteMax) ToolFailure.badNote];

/// One choice among a few, as a tappable row (no deprecated Radio API).
class _Choice extends StatelessWidget {
  const _Choice({super.key, required this.label, required this.selected, required this.onTap, this.detail});
  final Bilingual label;
  final bool selected;
  final VoidCallback? onTap;
  final Bilingual? detail;

  @override
  Widget build(BuildContext context) => Card(
        margin: const EdgeInsets.only(top: 8),
        color: selected ? WmColors.greenTint : Colors.white,
        shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(14), side: BorderSide(color: selected ? WmColors.greenBorder : WmColors.border)),
        child: InkWell(
          onTap: onTap,
          borderRadius: BorderRadius.circular(14),
          child: Padding(
            padding: const EdgeInsets.all(12),
            child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Icon(selected ? Icons.radio_button_checked : Icons.radio_button_unchecked, color: selected ? WmColors.green : WmColors.textMuted),
              const SizedBox(width: 10),
              Expanded(
                child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  BilingualText(label),
                  if (detail != null && selected) ...[
                    const SizedBox(height: 4),
                    BilingualText(detail!, style: const TextStyle(fontSize: 13, color: WmColors.brownDeep)),
                  ],
                ]),
              ),
            ]),
          ),
        ),
      );
}

/// The tool a form is about, at its top.
class _ToolHeader extends StatelessWidget {
  const _ToolHeader({required this.label, required this.name, this.details = '', this.extra});
  final String label;
  final String name;
  final String details;
  final String? extra;

  @override
  Widget build(BuildContext context) => Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Text('$label · $name', style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 17)),
        if (details.trim().isNotEmpty) Text(details, style: const TextStyle(color: WmColors.textMuted)),
        if (extra != null) Text(extra!, style: const TextStyle(fontSize: 13, color: WmColors.textSecondary)),
      ]);
}

Widget _loadFailureNotice(ToolFailure f, VoidCallback retry) => Padding(
      padding: const EdgeInsets.all(16),
      child: FailureNotice(
        key: const Key('tool-load-failure'),
        english: f == ToolFailure.noConnection ? toolsNeedSignal.english : toolFailureCopy(f).english,
        tagalog: f == ToolFailure.noConnection ? toolsNeedSignal.tagalog : toolFailureCopy(f).tagalog,
        actions: [noticeAction('Try again · Subukan ulit', retry)],
      ),
    );

// ── Report a problem (a worker, on a tool they hold) ─────────────────

class ReportProblemScreen extends StatefulWidget {
  const ReportProblemScreen({super.key, required this.tool, required this.submitter});
  final PhoneTool tool;
  final ToolSubmitter submitter;

  @override
  State<ReportProblemScreen> createState() => _ReportProblemScreenState();
}

class _ReportProblemScreenState extends State<ReportProblemScreen> with ToolSending {
  @override
  ToolSubmitter get submitter => widget.submitter;

  ProblemKind? _kind;
  final _note = TextEditingController();

  @override
  void dispose() {
    _note.dispose();
    super.dispose();
  }

  Future<void> _send() async {
    final t = widget.tool;
    final kind = _kind;
    final ok = await sendChecked([if (kind == null) ToolFailure.badKind, ..._noteProblems(_note.text)],
        write: ToolWrite.report,
        params: (op) => {'p_op': op, 'p_tool': t.id, 'p_kind': kind!.code, 'p_note': _note.text.trim()},
        summary: '${toolWords(t.label, t.name)} — reported: ${kind == null ? '' : problemCopy(kind).english}');
    if (ok && mounted) Navigator.of(context).pop(true);
  }

  @override
  Widget build(BuildContext context) {
    final t = widget.tool;
    return Scaffold(
      appBar: AppBar(title: const Text('Report a problem')),
      body: SafeArea(
        child: ListView(padding: const EdgeInsets.all(16), children: [
          _ToolHeader(label: t.label, name: t.name, details: t.details),
          const ToolFieldLabel("What's wrong?"),
          for (final k in ProblemKind.values)
            _Choice(
              key: Key('report-${k.code}'),
              label: problemCopy(k),
              selected: _kind == k,
              onTap: locked ? null : () => setState(() => _kind = k),
            ),
          const ToolFieldLabel('Note (optional)'),
          TextField(key: const Key('tool-note'), controller: _note, enabled: !locked, maxLength: _noteMax),
          sendArea(sendKey: const Key('tool-send'), onSend: _send),
          const SizedBox(height: 8),
          const BilingualText(
              Bilingual('It changes nothing on the tool: the office checks it.', 'Walang binabago sa tool: titingnan ito ng opisina.'),
              style: TextStyle(fontSize: 12.5, color: WmColors.textMuted)),
        ]),
      ),
    );
  }
}

// ── Issue a tool (a leader) ───────────────────────────────────────────

class IssueToolScreen extends StatefulWidget {
  const IssueToolScreen({super.key, required this.remote, required this.submitter});
  final ToolsRemote remote;
  final ToolSubmitter submitter;

  @override
  State<IssueToolScreen> createState() => _IssueToolScreenState();
}

class _IssueToolScreenState extends State<IssueToolScreen> with ToolSending {
  @override
  ToolSubmitter get submitter => widget.submitter;

  final _number = TextEditingController();
  final _note = TextEditingController();
  TeamChoices? _choices;
  ToolFailure? _loadFailure;
  FoundTool? _tool;
  ToolFailure? _findFailure;
  bool _finding = false;
  bool _confirmed = false;
  String? _holder;
  String? _folder;
  List<ToolRequestLine>? _lines;
  bool _linesFailed = false;
  String? _line;

  @override
  void initState() {
    super.initState();
    _loadChoices();
  }

  @override
  void dispose() {
    _number.dispose();
    _note.dispose();
    super.dispose();
  }

  Future<void> _loadChoices() async {
    setState(() => _loadFailure = null);
    try {
      final c = await widget.remote.choices();
      if (mounted) setState(() => _choices = c);
    } catch (e) {
      if (mounted) setState(() => _loadFailure = ToolFailure.of(e));
    }
  }

  Future<void> _find() async {
    if (locked || _finding) return;
    final typed = _number.text.trim();
    if (typed.isEmpty) return setState(() => _findFailure = ToolFailure.noTool);
    setState(() {
      _finding = true;
      _findFailure = null;
    });
    try {
      final t = await widget.remote.find(typed);
      if (!mounted) return;
      setState(() {
        _tool = t;
        _confirmed = false;
        _line = null;
      });
      await _loadLines();
    } catch (e) {
      if (mounted) {
        setState(() {
          _tool = null;
          _findFailure = ToolFailure.of(e);
        });
      }
    } finally {
      if (mounted) setState(() => _finding = false);
    }
  }

  /// A new number means a new tool: nothing found stays chosen.
  void _numberChanged(String _) {
    if (_tool == null && _findFailure == null) return;
    setState(() {
      _tool = null;
      _findFailure = null;
      _confirmed = false;
      _lines = null;
      _line = null;
    });
  }

  /// The request lines this tool can fill on the chosen project.
  Future<void> _loadLines() async {
    final tool = _tool;
    final folder = _folder;
    setState(() {
      _lines = null;
      _linesFailed = false;
    });
    if (tool == null || folder == null) return;
    try {
      final lines = await widget.remote.requestLines(tool.id, folder);
      if (!mounted || _tool?.id != tool.id || _folder != folder) return;
      setState(() {
        _lines = lines;
        if (_line != null && !lines.any((l) => l.lineId == _line)) _line = null;
      });
    } catch (_) {
      if (mounted) setState(() => _linesFailed = true);
    }
  }

  Future<void> _send() async {
    final tool = _tool;
    final c = _choices;
    final ok = await sendChecked([
      if (tool == null) ToolFailure.noTool,
      if (tool != null && !_confirmed) ToolFailure.notConfirmed,
      if (_holder == null) ToolFailure.badPerson,
      if (_folder == null) ToolFailure.badProject,
      ..._noteProblems(_note.text),
    ],
        write: ToolWrite.issue,
        params: (op) => {
              'p_op': op,
              'p_body': {'tool_id': tool!.id, 'holder_id': _holder, 'folder_id': _folder, 'request_line_id': _line, 'note': _note.text.trim()},
            },
        summary: tool == null
            ? ''
            : 'Issued ${toolWords(tool.label, tool.name)} to ${c?.member(_holder)?.name ?? 'a team member'} — ${c?.project(_folder)?.name ?? 'a project'}');
    if (ok && mounted) Navigator.of(context).pop(true);
  }

  @override
  Widget build(BuildContext context) {
    final c = _choices;
    final failure = _loadFailure;
    return Scaffold(
      appBar: AppBar(title: const Text('Issue a tool')),
      body: SafeArea(
        child: failure != null
            ? _loadFailureNotice(failure, _loadChoices)
            : c == null
                ? const Center(child: CircularProgressIndicator())
                : ListView(padding: const EdgeInsets.all(16), children: _fields(c)),
      ),
    );
  }

  List<Widget> _fields(TeamChoices c) {
    final tool = _tool;
    final f = _findFailure;
    return [
      const ToolFieldLabel('Tool number'),
      Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Expanded(
          child: TextField(
            key: const Key('issue-number'),
            controller: _number,
            enabled: !locked,
            textCapitalization: TextCapitalization.characters,
            decoration: const InputDecoration(hintText: 'TOOL-0003 or 3'),
            onChanged: _numberChanged,
            onSubmitted: (_) => _find(),
          ),
        ),
        const SizedBox(width: 8),
        SizedBox(
          height: 52,
          child: _finding
              ? const Padding(padding: EdgeInsets.all(14), child: CircularProgressIndicator(strokeWidth: 2.5))
              // The theme's buttons are full width: beside a field, its own size.
              : FilledButton(
                  key: const Key('issue-find'),
                  onPressed: locked ? null : _find,
                  style: FilledButton.styleFrom(minimumSize: const Size(0, 52)),
                  child: Text(findLabel.english),
                ),
        ),
      ]),
      if (f != null)
        Padding(
          padding: const EdgeInsets.only(top: 10),
          child: FailureNotice(key: const Key('issue-find-failure'), english: toolFailureCopy(f).english, tagalog: toolFailureCopy(f).tagalog),
        ),
      if (tool != null) ...[
        ToolBox(key: Key('issue-found-${tool.id}'), children: [
          _ToolHeader(label: tool.label, name: tool.name, details: tool.details),
          CheckboxListTile(
            key: const Key('issue-confirm'),
            contentPadding: EdgeInsets.zero,
            controlAffinity: ListTileControlAffinity.leading,
            value: _confirmed,
            onChanged: locked ? null : (v) => setState(() => _confirmed = v == true),
            title: const BilingualText(confirmToolLabel),
          ),
        ]),
      ],
      const ToolFieldLabel('Who gets it'),
      DropdownButtonFormField<String>(
        key: const Key('issue-person'),
        initialValue: _holder,
        isExpanded: true,
        hint: const Text('Choose the person'),
        items: [for (final m in c.members) DropdownMenuItem(value: m.id, child: Text(m.name, overflow: TextOverflow.ellipsis))],
        onChanged: locked ? null : (v) => setState(() => _holder = v),
      ),
      const ToolFieldLabel('Project'),
      DropdownButtonFormField<String>(
        key: const Key('issue-project'),
        initialValue: _folder,
        isExpanded: true,
        hint: const Text('Choose the project'),
        items: [for (final p in c.projects) DropdownMenuItem(value: p.folderId, child: Text(p.name, overflow: TextOverflow.ellipsis))],
        onChanged: locked
            ? null
            : (v) {
                setState(() {
                  _folder = v;
                  _line = null;
                });
                _loadLines();
              },
      ),
      if (tool != null && _folder != null) ..._requestFields(),
      const ToolFieldLabel('Note (optional)'),
      TextField(key: const Key('tool-note'), controller: _note, enabled: !locked, maxLength: _noteMax),
      sendArea(sendKey: const Key('tool-send'), onSend: _send),
      const SizedBox(height: 8),
      const BilingualText(officeFixes, style: TextStyle(fontSize: 12.5, color: WmColors.textMuted)),
    ];
  }

  /// A request line it fills, if any — only lines the leader can already see.
  List<Widget> _requestFields() => [
        const ToolFieldLabel('For a request (optional)'),
        if (_lines == null && !_linesFailed) const LinearProgressIndicator(),
        if (_linesFailed) const BilingualText(toolsNeedSignal, style: TextStyle(fontSize: 13, color: WmColors.danger)),
        if (_lines != null)
          KeyedSubtree(
            key: ValueKey('request-${_tool?.id}-$_folder'),
            child: DropdownButtonFormField<String?>(
              key: const Key('issue-request'),
              initialValue: _line,
              isExpanded: true,
              items: [
                const DropdownMenuItem<String?>(value: null, child: Text('None')),
                for (final l in _lines!)
                  DropdownMenuItem<String?>(
                    value: l.lineId,
                    child: Text(
                        '${l.description}${l.spec.isEmpty ? '' : ' · ${l.spec}'} — ${l.requesterName}'
                        '${l.boughtForThisTool ? ' · bought for this tool' : ' · ${_qty(l.stillToFill)} ${l.unit} still to fill'}',
                        overflow: TextOverflow.ellipsis),
                  ),
              ],
              onChanged: locked ? null : (v) => setState(() => _line = v),
            ),
          ),
      ];
}

String _qty(double v) => v == v.roundToDouble() ? v.toInt().toString() : v.toString();

// ── Hand over (a leader: from one member to another) ──────────────────

class HandoverToolScreen extends StatefulWidget {
  const HandoverToolScreen({super.key, required this.tool, required this.remote, required this.submitter});
  final PhoneTool tool;
  final ToolsRemote remote;
  final ToolSubmitter submitter;

  @override
  State<HandoverToolScreen> createState() => _HandoverToolScreenState();
}

class _HandoverToolScreenState extends State<HandoverToolScreen> with ToolSending {
  @override
  ToolSubmitter get submitter => widget.submitter;

  final _note = TextEditingController();
  TeamChoices? _choices;
  ToolFailure? _loadFailure;
  String? _holder;
  late String? _folder = widget.tool.folderId;

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void dispose() {
    _note.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    setState(() => _loadFailure = null);
    try {
      final c = await widget.remote.choices();
      if (mounted) setState(() => _choices = c);
    } catch (e) {
      if (mounted) setState(() => _loadFailure = ToolFailure.of(e));
    }
  }

  Future<void> _send() async {
    final t = widget.tool;
    final c = _choices;
    final ok = await sendChecked([if (_holder == null) ToolFailure.badPerson, ..._noteProblems(_note.text)],
        write: ToolWrite.handover,
        params: (op) => {
              'p_op': op,
              'p_body': {'tool_id': t.id, 'holder_id': _holder, 'folder_id': _folder ?? t.folderId, 'note': _note.text.trim()},
            },
        summary: 'Handed over ${toolWords(t.label, t.name)}: ${t.holderName ?? ''} → ${c?.member(_holder)?.name ?? 'a team member'}');
    if (ok && mounted) Navigator.of(context).pop(true);
  }

  @override
  Widget build(BuildContext context) {
    final c = _choices;
    final t = widget.tool;
    final failure = _loadFailure;
    return Scaffold(
      appBar: AppBar(title: const Text('Hand over')),
      body: SafeArea(
        child: failure != null
            ? _loadFailureNotice(failure, _load)
            : c == null
                ? const Center(child: CircularProgressIndicator())
                : ListView(padding: const EdgeInsets.all(16), children: [
                    _ToolHeader(label: t.label, name: t.name, details: t.details, extra: 'With ${t.holderName ?? '—'} · ${t.folderName ?? ''}'),
                    if (t.condition != null && t.condition != ToolCondition.good)
                      const Padding(
                        padding: EdgeInsets.only(top: 10),
                        child: BilingualText(needsRepairStays, style: TextStyle(fontSize: 13, color: WmColors.brownDeep)),
                      ),
                    const ToolFieldLabel('Hand it to'),
                    DropdownButtonFormField<String>(
                      key: const Key('handover-person'),
                      initialValue: _holder,
                      isExpanded: true,
                      hint: const Text('Choose the person'),
                      items: [
                        for (final m in c.members)
                          if (m.id != t.holderId) DropdownMenuItem(value: m.id, child: Text(m.name, overflow: TextOverflow.ellipsis)),
                      ],
                      onChanged: locked ? null : (v) => setState(() => _holder = v),
                    ),
                    const ToolFieldLabel('Project'),
                    DropdownButtonFormField<String>(
                      key: const Key('handover-project'),
                      initialValue: _folder,
                      isExpanded: true,
                      items: [
                        if (t.folderId != null)
                          DropdownMenuItem(value: t.folderId, child: Text('Stays on ${t.folderName ?? 'its project'}', overflow: TextOverflow.ellipsis)),
                        for (final p in c.projects)
                          if (p.folderId != t.folderId) DropdownMenuItem(value: p.folderId, child: Text(p.name, overflow: TextOverflow.ellipsis)),
                      ],
                      onChanged: locked ? null : (v) => setState(() => _folder = v),
                    ),
                    const ToolFieldLabel('Note (optional)'),
                    TextField(key: const Key('tool-note'), controller: _note, enabled: !locked, maxLength: _noteMax),
                    sendArea(sendKey: const Key('tool-send'), onSend: _send),
                    const SizedBox(height: 8),
                    const BilingualText(officeFixes, style: TextStyle(fontSize: 12.5, color: WmColors.textMuted)),
                  ]),
      ),
    );
  }
}

// ── Return (a leader: back to the warehouse, with its condition) ───────

class ReturnToolScreen extends StatefulWidget {
  const ReturnToolScreen({super.key, required this.tool, required this.submitter});
  final PhoneTool tool;
  final ToolSubmitter submitter;

  @override
  State<ReturnToolScreen> createState() => _ReturnToolScreenState();
}

class _ReturnToolScreenState extends State<ReturnToolScreen> with ToolSending {
  @override
  ToolSubmitter get submitter => widget.submitter;

  ToolCondition? _condition;
  final _note = TextEditingController();

  @override
  void dispose() {
    _note.dispose();
    super.dispose();
  }

  Future<void> _send() async {
    final t = widget.tool;
    final cond = _condition;
    final ok = await sendChecked([if (cond == null) ToolFailure.badCondition, ..._noteProblems(_note.text)],
        write: ToolWrite.giveBack,
        params: (op) => {
              'p_op': op,
              'p_body': {'tool_id': t.id, 'condition': cond!.code, 'note': _note.text.trim()},
            },
        summary: 'Returned ${toolWords(t.label, t.name)} from ${t.holderName ?? ''} — ${cond == null ? '' : conditionCopy(cond).english}');
    if (ok && mounted) Navigator.of(context).pop(true);
  }

  @override
  Widget build(BuildContext context) {
    final t = widget.tool;
    return Scaffold(
      appBar: AppBar(title: const Text('Return')),
      body: SafeArea(
        child: ListView(padding: const EdgeInsets.all(16), children: [
          _ToolHeader(label: t.label, name: t.name, details: t.details, extra: 'From ${t.holderName ?? '—'} · ${t.folderName ?? ''}'),
          const ToolFieldLabel('Its condition'),
          for (final c in ToolCondition.values)
            _Choice(
              key: Key('return-${c.code}'),
              label: conditionCopy(c),
              selected: _condition == c,
              detail: c == ToolCondition.damaged ? damagedAsksOwner : null,
              onTap: locked ? null : () => setState(() => _condition = c),
            ),
          const ToolFieldLabel('Note (optional)'),
          TextField(key: const Key('tool-note'), controller: _note, enabled: !locked, maxLength: _noteMax),
          sendArea(sendKey: const Key('tool-send'), onSend: _send),
          const SizedBox(height: 8),
          const BilingualText(officeFixes, style: TextStyle(fontSize: 12.5, color: WmColors.textMuted)),
        ]),
      ),
    );
  }
}

// ── Undo (a leader's own latest record, with a reason) ────────────────

class UndoRecordScreen extends StatefulWidget {
  const UndoRecordScreen({super.key, required this.record, required this.submitter});
  final LeaderRecord record;
  final ToolSubmitter submitter;

  @override
  State<UndoRecordScreen> createState() => _UndoRecordScreenState();
}

class _UndoRecordScreenState extends State<UndoRecordScreen> with ToolSending {
  @override
  ToolSubmitter get submitter => widget.submitter;

  final _reason = TextEditingController();

  @override
  void dispose() {
    _reason.dispose();
    super.dispose();
  }

  Future<void> _send() async {
    final r = widget.record;
    final reason = _reason.text.trim();
    final ok = await sendChecked([if (reason.isEmpty || reason.length > _reasonMax) ToolFailure.reasonRequired],
        write: ToolWrite.undo,
        params: (op) => {'p_op': op, 'p_record': r.id, 'p_reason': reason},
        summary: 'Undo: ${recordKind(r.kind)} ${toolWords(r.label, r.itemName)}${r.holderName == null ? '' : ' — ${r.holderName}'}');
    if (ok && mounted) Navigator.of(context).pop(true);
  }

  @override
  Widget build(BuildContext context) {
    final r = widget.record;
    return Scaffold(
      appBar: AppBar(title: const Text('Undo')),
      body: SafeArea(
        child: ListView(padding: const EdgeInsets.all(16), children: [
          _ToolHeader(
              label: r.label,
              name: r.itemName,
              extra: '${recordKind(r.kind)}${r.holderName == null ? '' : ' · ${r.holderName}'} · ${recordTime(r.at)}'),
          const SizedBox(height: 10),
          const BilingualText(
              Bilingual('Undo puts the tool back where it was before this record. The record stays in the history, marked Undone.',
                  'Ibabalik ng undo ang tool sa dati bago ang record na ito. Mananatili ang record sa kasaysayan, may markang Undone.'),
              style: TextStyle(fontSize: 13, color: WmColors.textSecondary)),
          const ToolFieldLabel('Why (required)'),
          TextField(key: const Key('undo-reason'), controller: _reason, enabled: !locked, maxLength: _reasonMax),
          sendArea(sendKey: const Key('tool-send'), onSend: _send),
        ]),
      ),
    );
  }
}
