import 'package:flutter/material.dart';

import '../../purchasing/ui/purchasing_copy.dart' show BilingualText;
import '../../ui/theme.dart';
import '../data/stock_submitter.dart';
import '../domain/stock_forms.dart';
import '../domain/stock_models.dart';
import '../domain/stock_submission.dart';
import 'stock_copy.dart';
import 'stock_widgets.dart';

/// "Received" (Q6, Q7): part or all of a warehouse purchase line arrived, in
/// the line's own unit. Not matched yet: still recorded — it becomes stock
/// when the office matches it.
class ReceiveSheet extends StatefulWidget {
  const ReceiveSheet({super.key, required this.submitter, required this.line, this.today});

  final StockSubmitter submitter;
  final StockLine line;
  final String? today;

  @override
  State<ReceiveSheet> createState() => _ReceiveSheetState();
}

class _ReceiveSheetState extends State<ReceiveSheet> with StockSending {
  @override
  StockSubmitter get submitter => widget.submitter;

  late final String _today = widget.today ?? stockToday();
  late final ReceiveForm _form = ReceiveForm(line: widget.line, on: _today);
  late final _qty = TextEditingController(text: qtyText(widget.line.awaiting));
  final _note = TextEditingController();

  @override
  void dispose() {
    _qty.dispose();
    _note.dispose();
    super.dispose();
  }

  Future<void> _send() async {
    _form
      ..quantity = _qty.text
      ..note = _note.text;
    final l = widget.line;
    final ok = await sendChecked(_form.problems(today: _today),
        write: StockWrite.receive,
        params: _form.params,
        summary: 'Received ${stockQty(parseStockQty(_form.quantity) ?? 0, l.unit)} ${l.itemName} (bought ${l.purchaseDate})');
    if (ok && mounted) Navigator.of(context).pop(true);
  }

  @override
  Widget build(BuildContext context) {
    final l = widget.line;
    return Padding(
      padding: EdgeInsets.fromLTRB(20, 0, 20, 20 + MediaQuery.of(context).viewInsets.bottom),
      child: SingleChildScrollView(
        child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.start, children: [
          const BilingualText(receivedLabel, style: TextStyle(fontWeight: FontWeight.w800, fontSize: 19)),
          const SizedBox(height: 6),
          Text('${l.itemName} · bought ${l.purchaseDate} by ${l.boughtByName}', style: const TextStyle(color: WmColors.textMuted)),
          Text('Still awaited: ${stockQty(l.awaiting, l.unit)}', style: const TextStyle(fontWeight: FontWeight.w700)),
          if (l.match == null) ...[
            const SizedBox(height: 6),
            const BilingualText(notMatchedYet, style: TextStyle(fontSize: 12.5, color: WmColors.brownDeep)),
          ],
          const StockFieldLabel('How much arrived?'),
          TextField(
            key: const Key('receive-qty'),
            controller: _qty,
            enabled: !locked,
            keyboardType: const TextInputType.numberWithOptions(decimal: true),
            decoration: InputDecoration(suffixText: l.unit),
          ),
          const StockFieldLabel('When'),
          StockDayField(value: _form.on, today: _today, onChanged: locked ? null : (d) => setState(() => _form.on = d)),
          const StockFieldLabel('Note (optional)'),
          TextField(key: const Key('receive-note'), controller: _note, enabled: !locked, maxLength: 300),
          SizedBox(width: double.infinity, child: sendArea(sendKey: const Key('receive-send'), onSend: _send)),
        ]),
      ),
    );
  }
}
