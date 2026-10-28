import 'package:flutter/material.dart';

import '../../purchasing/ui/purchasing_copy.dart' show BilingualText;
import '../../ui/failure_notice.dart';
import '../../ui/theme.dart';
import '../data/stock_remote.dart';
import '../data/stock_submitter.dart';
import '../domain/stock_failure.dart';
import '../domain/stock_forms.dart';
import '../domain/stock_models.dart';
import '../domain/stock_submission.dart';
import 'stock_copy.dart';
import 'stock_widgets.dart';

/// Leftovers of a project purchase (Q3): left at the project's site or
/// brought to the warehouse — their cost stays with that project. Counted
/// in the catalogue item's unit; never more than the line brought.
class LeftoverScreen extends StatefulWidget {
  const LeftoverScreen({super.key, required this.remote, required this.submitter, this.today});

  /// Reads only; writes go through [submitter].
  final StockRemote remote;
  final StockSubmitter submitter;
  final String? today;

  @override
  State<LeftoverScreen> createState() => _LeftoverScreenState();
}

class _LeftoverScreenState extends State<LeftoverScreen> with StockSending {
  @override
  StockSubmitter get submitter => widget.submitter;

  late final String _today = widget.today ?? stockToday();
  StockChoices? _choices;
  StockFailure? _loadFailure;
  String? _project;
  List<StockLine>? _lines;
  StockLine? _line;
  String _where = 'site';
  String _on = '';
  final _qty = TextEditingController();
  final _note = TextEditingController();

  @override
  void initState() {
    super.initState();
    _on = _today;
    _load();
  }

  @override
  void dispose() {
    _qty.dispose();
    _note.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    setState(() => _loadFailure = null);
    try {
      final c = await widget.remote.choices();
      if (mounted) setState(() => _choices = c);
    } catch (e) {
      if (mounted) setState(() => _loadFailure = StockFailure.of(e));
    }
  }

  Future<void> _pickProject(String? folderId) async {
    setState(() {
      _project = folderId;
      _lines = null;
      _line = null;
    });
    if (folderId == null) return;
    try {
      final lines = await widget.remote.projectLines(folderId);
      if (mounted && _project == folderId) setState(() => _lines = lines);
    } catch (e) {
      if (mounted) setState(() => _loadFailure = StockFailure.of(e));
    }
  }

  Future<void> _send() async {
    final line = _line;
    if (line == null) {
      setState(() => failure = StockFailure.notProject);
      return;
    }
    final form = LeftoverForm(line: line, quantity: _qty.text, where: _where, on: _on, note: _note.text);
    final project = _choices?.projects.where((p) => p.folderId == _project).firstOrNull?.name ?? 'the project';
    final ok = await sendChecked(form.problems(today: _today),
        write: StockWrite.leftover,
        params: form.params,
        summary: 'Leftovers ${stockQty(parseStockQty(form.quantity) ?? 0, line.match?.itemUnit ?? '')} ${line.itemName} — '
            '${_where == 'site' ? 'at the site of' : 'brought to the warehouse from'} $project');
    if (ok && mounted) Navigator.of(context).pop(true);
  }

  @override
  Widget build(BuildContext context) => Scaffold(
        appBar: AppBar(title: const Text('Record leftovers')),
        body: SafeArea(
          child: _loadFailure != null
              ? Padding(
                  padding: const EdgeInsets.all(16),
                  child: FailureNotice(
                    key: const Key('stock-load-failure'),
                    english: stockFailureCopy(_loadFailure!).english,
                    tagalog: stockFailureCopy(_loadFailure!).tagalog,
                    actions: [noticeAction('Try again · Subukan ulit', _load)],
                  ),
                )
              : _choices == null
                  ? const Center(child: CircularProgressIndicator())
                  : ListView(padding: const EdgeInsets.all(16), children: _fields(_choices!)),
        ),
      );

  List<Widget> _fields(StockChoices choices) {
    final line = _line;
    final unit = line?.match?.itemUnit ?? '';
    return [
      const StockFieldLabel('Project'),
      DropdownButtonFormField<String>(
        key: const Key('leftover-project'),
        initialValue: _project,
        isExpanded: true,
        hint: const Text('Choose the project'),
        items: [for (final p in choices.projectsInOrder) DropdownMenuItem(value: p.folderId, child: Text(p.label, overflow: TextOverflow.ellipsis))],
        onChanged: locked ? null : _pickProject,
      ),
      if (_project != null && _lines == null) const Padding(padding: EdgeInsets.only(top: 12), child: LinearProgressIndicator()),
      if (_lines != null) ...[
        const StockFieldLabel('Which purchase'),
        if (_lines!.isEmpty) const Text('No purchase for this project yet.', style: TextStyle(color: WmColors.textMuted)),
        IgnorePointer(
          ignoring: locked,
          child: RadioGroup<String>(
            groupValue: line?.key,
            onChanged: (k) => setState(() => _line = _lines!.where((l) => l.key == k).firstOrNull),
            child: Column(children: [
              for (final l in _lines!)
                RadioListTile<String>(
                  key: Key('leftover-line-${l.key}'),
                  value: l.key,
                  contentPadding: EdgeInsets.zero,
                  title: Text('${l.itemName} · ${stockQty(l.quantity, l.unit)}'),
                  subtitle: Text(l.match == null
                      ? 'Bought ${l.purchaseDate} — not matched yet (the office matches it first)'
                      : 'Bought ${l.purchaseDate} — up to ${stockQty(l.leftoverRoom, l.match!.itemUnit)} can be recorded'),
                ),
            ]),
          ),
        ),
      ],
      if (line != null) ...[
        const StockFieldLabel('How much is left over?'),
        TextField(
          key: const Key('leftover-qty'),
          controller: _qty,
          enabled: !locked,
          keyboardType: const TextInputType.numberWithOptions(decimal: true),
          decoration: InputDecoration(suffixText: unit),
        ),
        const StockFieldLabel('Where is it?'),
        SegmentedButton<String>(
          key: const Key('leftover-where'),
          segments: const [
            ButtonSegment(value: 'site', label: Text('At the site')),
            ButtonSegment(value: 'warehouse', label: Text('Brought to the warehouse')),
          ],
          selected: {_where},
          onSelectionChanged: locked ? null : (s) => setState(() => _where = s.first),
        ),
        const StockFieldLabel('When'),
        Align(alignment: Alignment.centerLeft, child: StockDayField(value: _on, today: _today, onChanged: locked ? null : (d) => setState(() => _on = d))),
        const StockFieldLabel('Note (optional)'),
        TextField(key: const Key('leftover-note'), controller: _note, enabled: !locked, maxLength: 300),
      ],
      sendArea(sendKey: const Key('leftover-send'), onSend: _send),
      const SizedBox(height: 8),
      const BilingualText(undoOnWeb, style: TextStyle(fontSize: 12.5, color: WmColors.textMuted)),
    ];
  }
}
