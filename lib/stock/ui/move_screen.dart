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

/// Where the issue / move / return form starts. The shopping list's "Issue
/// from stock" fixes the item, the project and the request line; a return
/// fixes everything but the quantity.
class MovePreset {
  const MovePreset({
    this.itemId,
    this.from = warehousePlace,
    this.to,
    this.requestLineId,
    this.quantity,
    this.returnsRecord,
    this.returnFrom,
    this.fixed = false,
  });

  final String? itemId;
  final String from;
  final String? to;
  final String? requestLineId;
  final double? quantity;
  final String? returnsRecord;

  /// The issue's project, shown on a return.
  final String? returnFrom;

  /// Item, from, to and request line can't be changed (Issue from stock).
  final bool fixed;
}

/// Issue (warehouse → project), move (project → project, or → warehouse) or
/// return (Q8, Q10, Q26). Online only: the choices and the request lines
/// are read when it opens; Send needs signal and records once (R101).
class MoveScreen extends StatefulWidget {
  const MoveScreen({super.key, required this.remote, required this.submitter, required this.preset, this.overview, this.today});

  /// Reads only; writes go through [submitter].
  final StockRemote remote;
  final StockSubmitter submitter;
  final MovePreset preset;

  /// For the "N there" hint only; the server checks the real balance.
  final StockOverview? overview;
  final String? today;

  @override
  State<MoveScreen> createState() => _MoveScreenState();
}

class _MoveScreenState extends State<MoveScreen> with StockSending {
  @override
  StockSubmitter get submitter => widget.submitter;

  late final String _today = widget.today ?? stockToday();
  late final MoveForm _form = MoveForm(
    itemId: widget.preset.itemId,
    from: widget.preset.from,
    to: widget.preset.to,
    on: _today,
    requestLineId: widget.preset.requestLineId,
    returnsRecord: widget.preset.returnsRecord,
    quantity: widget.preset.quantity == null || widget.preset.quantity! <= 0 ? '' : qtyText(widget.preset.quantity!),
  );
  late final _qty = TextEditingController(text: _form.quantity);
  final _reason = TextEditingController();
  final _note = TextEditingController();

  StockChoices? _choices;
  StockFailure? _loadFailure;
  List<StockRequestLine>? _lines;
  bool _linesFailed = false;

  bool get _isReturn => _form.isReturn;

  @override
  void initState() {
    super.initState();
    _loadChoices();
  }

  @override
  void dispose() {
    _qty.dispose();
    _reason.dispose();
    _note.dispose();
    super.dispose();
  }

  Future<void> _loadChoices() async {
    setState(() => _loadFailure = null);
    try {
      final c = await widget.remote.choices();
      if (!mounted) return;
      setState(() => _choices = c);
      await _loadLines();
    } catch (e) {
      if (mounted) setState(() => _loadFailure = StockFailure.of(e));
    }
  }

  /// The request lines of the project the goods go to (a site only).
  Future<void> _loadLines() async {
    final to = _form.to;
    setState(() {
      _lines = null;
      _linesFailed = false;
    });
    if (_isReturn || to == null || to == warehousePlace) return;
    try {
      final lines = await widget.remote.requestLines(to);
      if (!mounted || _form.to != to) return;
      setState(() {
        _lines = lines;
        if (_form.requestLineId != null && !lines.any((l) => l.lineId == _form.requestLineId)) _form.requestLineId = null;
      });
    } catch (_) {
      if (mounted) setState(() => _linesFailed = true);
    }
  }

  StockItemChoice? get _item => _choices?.item(_form.itemId);

  List<StockRequestLine> get _fitting {
    final item = _item;
    return item == null ? const [] : (_lines ?? const []).where((l) => l.fits(item)).toList();
  }

  String _place(String? id) =>
      id == warehousePlace ? 'Warehouse' : (_choices?.projects.where((p) => p.folderId == id).firstOrNull?.name ?? 'a project');

  /// In words, for the Stock tab if the answer is lost.
  String _summary() {
    final item = _item;
    final q = stockQty(parseStockQty(_form.quantity) ?? 0, item?.unit ?? '');
    final what = item?.name ?? 'Item';
    if (_isReturn) return 'Returned $q $what — ${widget.preset.returnFrom ?? 'a project'} → Warehouse';
    return '${_form.kind == 'issue' ? 'Issued' : 'Moved'} $q $what — ${_place(_form.from)} → ${_place(_form.to)}';
  }

  Future<void> _send() async {
    _form
      ..quantity = _qty.text
      ..unplannedReason = _form.requestLineId == null ? _reason.text : ''
      ..note = _note.text;
    final ok = await sendChecked(_form.problems(today: _today),
        write: StockWrite.move, params: (op) => {'p_op': op, 'p_body': _form.body()}, summary: _summary());
    if (ok && mounted) Navigator.of(context).pop(true);
  }

  String get _title => _isReturn ? 'Return to the warehouse' : (widget.preset.fixed ? 'Issue from stock' : 'Issue or move');

  @override
  Widget build(BuildContext context) {
    final choices = _choices;
    return Scaffold(
      appBar: AppBar(title: Text(_title)),
      body: SafeArea(
        child: _loadFailure != null
            ? Padding(
                padding: const EdgeInsets.all(16),
                child: FailureNotice(
                  key: const Key('stock-load-failure'),
                  english: stockFailureCopy(_loadFailure!).english,
                  tagalog: stockFailureCopy(_loadFailure!).tagalog,
                  actions: [noticeAction('Try again · Subukan ulit', _loadChoices)],
                ),
              )
            : choices == null
                ? const Center(child: CircularProgressIndicator())
                : ListView(padding: const EdgeInsets.all(16), children: _fields(choices)),
      ),
    );
  }

  List<Widget> _fields(StockChoices choices) {
    final item = _item;
    final unit = item?.unit ?? '';
    final places = [
      const DropdownMenuItem<String>(value: warehousePlace, child: Text('Warehouse')),
      for (final p in choices.projectsInOrder) DropdownMenuItem<String>(value: p.folderId, child: Text(p.label, overflow: TextOverflow.ellipsis)),
    ];
    final there = widget.overview?.item(_form.itemId)?.at(_form.from);
    final fixed = widget.preset.fixed || _isReturn || locked;
    return [
      if (_isReturn)
        Text('From ${widget.preset.returnFrom ?? 'the project'}, back to the warehouse. The same lots go back.',
            style: const TextStyle(color: WmColors.textMuted)),
      const StockFieldLabel('Item'),
      DropdownButtonFormField<String>(
        key: const Key('move-item'),
        initialValue: _form.itemId,
        isExpanded: true,
        hint: const Text('Choose the item'),
        items: [for (final i in choices.items) DropdownMenuItem(value: i.itemId, child: Text(i.label, overflow: TextOverflow.ellipsis))],
        onChanged: fixed
            ? null
            : (v) => setState(() {
                  _form.itemId = v;
                  _form.requestLineId = null;
                }),
      ),
      if (!_isReturn) ...[
        const StockFieldLabel('From'),
        DropdownButtonFormField<String>(
          key: const Key('move-from'),
          initialValue: _form.from,
          isExpanded: true,
          items: places,
          onChanged: fixed ? null : (v) => setState(() => _form.from = v ?? warehousePlace),
        ),
        const StockFieldLabel('To'),
        DropdownButtonFormField<String>(
          key: const Key('move-to'),
          initialValue: _form.to,
          isExpanded: true,
          hint: const Text('Choose where it goes'),
          items: places,
          onChanged: fixed
              ? null
              : (v) {
                  setState(() {
                    _form.to = v;
                    _form.requestLineId = null;
                  });
                  _loadLines();
                },
        ),
      ],
      const StockFieldLabel('Quantity'),
      TextField(
        key: const Key('move-qty'),
        controller: _qty,
        enabled: !locked,
        keyboardType: const TextInputType.numberWithOptions(decimal: true),
        decoration: InputDecoration(
          suffixText: unit,
          helperText: there == null ? null : '${stockQty(there, unit)} there now',
        ),
      ),
      if (_form.toSite) ..._requestFields(),
      const StockFieldLabel('When'),
      Align(
        alignment: Alignment.centerLeft,
        child: StockDayField(value: _form.on, today: _today, onChanged: locked ? null : (d) => setState(() => _form.on = d)),
      ),
      const StockFieldLabel('Note (optional)'),
      TextField(key: const Key('move-note'), controller: _note, enabled: !locked, maxLength: 300),
      sendArea(sendKey: const Key('move-send'), onSend: _send),
      const SizedBox(height: 8),
      const BilingualText(undoOnWeb, style: TextStyle(fontSize: 12.5, color: WmColors.textMuted)),
    ];
  }

  /// To a project: a request line it fills, or why it is needed (R58).
  List<Widget> _requestFields() {
    final fitting = _fitting;
    final fixedLine = (widget.preset.fixed && _form.requestLineId != null) || locked;
    return [
      const StockFieldLabel('For a request'),
      if (_lines == null && !_linesFailed) const LinearProgressIndicator(),
      if (_linesFailed)
        const BilingualText(stockNeedsSignal, style: TextStyle(fontSize: 13, color: WmColors.danger)),
      if (_lines != null)
        // A new item or place starts the choice afresh (its lines differ).
        KeyedSubtree(
          key: ValueKey('request-${_form.itemId}-${_form.to}'),
          child: DropdownButtonFormField<String?>(
            key: const Key('move-request'),
            initialValue: _form.requestLineId,
            isExpanded: true,
            items: [
              const DropdownMenuItem<String?>(value: null, child: Text('None — unplanned')),
              for (final l in fitting)
                DropdownMenuItem<String?>(
                  value: l.lineId,
                  child: Text('${l.description}${l.spec.isEmpty ? '' : ' · ${l.spec}'} — ${l.requesterName} · '
                      '${stockQty(l.stillToBuy, l.unit)} still needed', overflow: TextOverflow.ellipsis),
                ),
            ],
            onChanged: fixedLine ? null : (v) => setState(() => _form.requestLineId = v),
          ),
        ),
      if (_form.requestLineId == null) ...[
        const StockFieldLabel('Why it is needed'),
        TextField(key: const Key('move-reason'), controller: _reason, enabled: !locked, maxLength: 300),
      ],
    ];
  }
}
