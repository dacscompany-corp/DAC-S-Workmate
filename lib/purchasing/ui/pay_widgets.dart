import 'package:flutter/material.dart';

import '../../attendance/ui/attendance_copy.dart' show Bilingual;
import '../../ui/theme.dart';
import 'pay_copy.dart';

/// A warning that never blocks (Q16 overspending, Q21 own money not allowed).
class PayWarning extends StatelessWidget {
  const PayWarning({super.key, required this.text});
  final Bilingual text;

  @override
  Widget build(BuildContext context) => Container(
        width: double.infinity,
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(color: WmColors.brownTint, borderRadius: BorderRadius.circular(10)),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text(text.english, style: const TextStyle(color: WmColors.brownDeep, fontWeight: FontWeight.w700, fontSize: 13)),
          Text(text.tagalog, style: const TextStyle(color: WmColors.brownDeep, fontSize: 12)),
        ]),
      );
}

/// A purchase's payment state as a small pill (the Purchasing tab's colours).
class PayPill extends StatelessWidget {
  const PayPill(this.state, {super.key});
  final String state;

  @override
  Widget build(BuildContext context) {
    final (fg, bg) = switch (state) {
      'paid' => (WmColors.green, WmColors.greenTint),
      'partial' => (WmColors.brownDeep, WmColors.brownTint),
      'unpaid' || 'overpaid' || 'void_paid' => (WmColors.danger, WmColors.dangerTint),
      _ => (WmColors.textSecondary, WmColors.inert),
    };
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 3),
      decoration: BoxDecoration(color: bg, borderRadius: BorderRadius.circular(20)),
      child: Text(payStateCopy(state).english, style: TextStyle(fontSize: 12, fontWeight: FontWeight.w700, color: fg)),
    );
  }
}

/// Asks for a note the server requires (a void's reason, "I did not receive
/// this"): the action stays off until something is typed. Null when cancelled.
/// The dialog owns its text box, so it is released only once the dialog has
/// gone — never while its closing animation still shows it.
Future<String?> askRequiredNote(
  BuildContext context, {
  required String title,
  required String message,
  required String action,
  String label = 'Note',
  Key fieldKey = const Key('note-field'),
  Key sendKey = const Key('note-send'),
}) =>
    showDialog<String>(
      context: context,
      builder: (_) => _NoteDialog(title: title, message: message, action: action, label: label, fieldKey: fieldKey, sendKey: sendKey),
    );

class _NoteDialog extends StatefulWidget {
  const _NoteDialog({required this.title, required this.message, required this.action, required this.label, required this.fieldKey, required this.sendKey});
  final String title;
  final String message;
  final String action;
  final String label;
  final Key fieldKey;
  final Key sendKey;

  @override
  State<_NoteDialog> createState() => _NoteDialogState();
}

class _NoteDialogState extends State<_NoteDialog> {
  final _text = TextEditingController();

  @override
  void dispose() {
    _text.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => AlertDialog(
        title: Text(widget.title),
        content: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text(widget.message, style: const TextStyle(fontSize: 13, color: WmColors.textMuted)),
          TextField(
            key: widget.fieldKey,
            controller: _text,
            autofocus: true,
            decoration: InputDecoration(labelText: widget.label),
            onChanged: (_) => setState(() {}),
          ),
        ]),
        actions: [
          TextButton(onPressed: () => Navigator.of(context).pop(), child: const Text('Cancel')),
          TextButton(
            key: widget.sendKey,
            onPressed: _text.text.trim().isEmpty ? null : () => Navigator.of(context).pop(_text.text.trim()),
            child: Text(widget.action),
          ),
        ],
      );
}
