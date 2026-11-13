import 'package:flutter/material.dart';

import '../../purchasing/ui/purchasing_copy.dart' show BilingualText;
import '../../ui/theme.dart';
import '../../ui/wm_sheet.dart';
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

  /// − and +: one more or one less than what is typed (an empty or unreadable
  /// box counts as 0), never below zero. A typed decimal is kept (2.5 → 3.5).
  void _step(int by) {
    if (sending || locked) return;
    final now = parseStockQty(_qty.text) ?? 0;
    final next = (now + by) < 0 ? 0.0 : now + by;
    _qty.value = TextEditingValue(text: qtyText(next), selection: TextSelection.collapsed(offset: qtyText(next).length));
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
    final stepsOff = sending || locked;
    return WmSheetFrame(
      title: receivedLabel.english,
      subtitle: receivedLabel.tagalog,
      footer: sendFooter(sendKey: const Key('receive-send'), onSend: _send),
      children: [
        Text(l.itemName, style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 16)),
        Text('Bought ${l.purchaseDate} by ${l.boughtByName}', style: const TextStyle(fontSize: 13, color: WmColors.textMuted)),
        Text('Still awaited: ${stockQty(l.awaiting, l.unit)}', style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 14)),
        if (l.match == null) ...[
          const SizedBox(height: 6),
          const BilingualText(notMatchedYet, style: TextStyle(fontSize: 12.5, color: WmColors.brownDeep)),
        ],
        const SizedBox(height: 18),
        const Text('How many arrived?', style: TextStyle(fontWeight: FontWeight.w700, fontSize: 14)),
        const SizedBox(height: 8),
        Row(crossAxisAlignment: CrossAxisAlignment.center, children: [
          _StepButton(key: const Key('receive-minus'), icon: Icons.remove, label: 'One less', onTap: stepsOff ? null : () => _step(-1)),
          const SizedBox(width: 12),
          Expanded(
            child: TextField(
              key: const Key('receive-qty'),
              controller: _qty,
              enabled: !locked,
              textAlign: TextAlign.center,
              keyboardType: const TextInputType.numberWithOptions(decimal: true),
              style: const TextStyle(fontFamily: 'IBM Plex Mono', fontWeight: FontWeight.w700, fontSize: 20),
              decoration: InputDecoration(
                suffixText: l.unit,
                // Filled like every other field (the app's field colour); only the buttons beside it are white.
                contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 14),
                border: _box(WmColors.border),
                enabledBorder: _box(WmColors.border),
                disabledBorder: _box(WmColors.border),
                focusedBorder: _box(WmColors.green),
              ),
            ),
          ),
          const SizedBox(width: 12),
          _StepButton(key: const Key('receive-plus'), icon: Icons.add, label: 'One more', onTap: stepsOff ? null : () => _step(1)),
        ]),
        const StockFieldLabel('When'),
        StockDayField(value: _form.on, today: _today, onChanged: locked ? null : (d) => setState(() => _form.on = d)),
        const StockFieldLabel('Note (optional)'),
        TextField(key: const Key('receive-note'), controller: _note, enabled: !locked, maxLength: 300),
        ?sendBox(),
      ],
    );
  }

  static OutlineInputBorder _box(Color c) =>
      OutlineInputBorder(borderRadius: BorderRadius.circular(14), borderSide: BorderSide(color: c));
}

/// The 52-px − / + button beside the quantity (radius 14, white, green icon).
class _StepButton extends StatelessWidget {
  const _StepButton({super.key, required this.icon, required this.label, required this.onTap});

  final IconData icon;
  final String label;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) => Semantics(
        button: true,
        enabled: onTap != null,
        label: label,
        excludeSemantics: true,
        child: SizedBox(
          width: 52,
          height: 52,
          child: Material(
            color: Colors.white,
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14), side: const BorderSide(color: WmColors.border)),
            clipBehavior: Clip.antiAlias,
            child: InkWell(
              onTap: onTap,
              child: Center(widthFactor: 1, heightFactor: 1, child: Icon(icon, size: 24, color: onTap == null ? WmColors.textDisabled : WmColors.green)),
            ),
          ),
        ),
      );
}
