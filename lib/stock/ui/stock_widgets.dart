import 'package:flutter/material.dart';

import '../../attendance/domain/work_date.dart';
import '../../attendance/ui/attendance_copy.dart' show Bilingual;
import '../../attendance/ui/formats.dart' show clockTime;
import '../../purchasing/ui/purchasing_copy.dart' show BilingualText, bilingualButton;
import '../../ui/failure_notice.dart';
import '../../ui/theme.dart';
import '../data/stock_submitter.dart';
import '../domain/stock_failure.dart';
import '../domain/stock_submission.dart';
import 'stock_copy.dart';

/// Manila's today ("2026-10-27"): the latest day a stock record may carry.
String stockToday([DateTime? now]) => WorkDate.today(now).iso;

/// A stock form's Send (R101): the phone's own checks first, then the
/// submission goes through [StockSubmitter] — saved with its operation id
/// and exact payload before it leaves. If the answer is lost the form
/// LOCKS: its fields cannot change, and only Send again (the saved payload),
/// Check, or Cancel it and change are offered — the last one unlocks the
/// fields only once the SERVER confirms the id cancelled (R102).
mixin StockSending<T extends StatefulWidget> on State<T> {
  StockSubmitter get submitter;

  bool sending = false;
  StockFailure? failure;
  Bilingual? message;

  /// The unresolved submission this form sent; the fields are locked while set.
  String? unsureOp;
  StockFailure? _unsureWhy;

  bool get locked => unsureOp != null;

  /// True when the server recorded it.
  Future<bool> sendChecked(
    List<StockFailure> problems, {
    required StockWrite write,
    required Map<String, dynamic> Function(String opId) params,
    required String summary,
  }) async {
    if (sending || locked) return false;
    if (problems.isNotEmpty) {
      setState(() {
        failure = problems.first;
        message = null;
      });
      return false;
    }
    setState(() {
      sending = true;
      failure = null;
      message = null;
    });
    try {
      final o = await submitter.submit(write: write, params: params, summary: summary);
      if (!mounted) return o.result == StockSendResult.recorded;
      setState(() {
        switch (o.result) {
          case StockSendResult.recorded:
            break;
          case StockSendResult.refused:
            failure = o.failure;
          case StockSendResult.blocked:
            message = finishFirst;
          case StockSendResult.unsure:
            unsureOp = o.opId;
            _unsureWhy = o.failure;
        }
      });
      return o.result == StockSendResult.recorded;
    } finally {
      if (mounted) setState(() => sending = false);
    }
  }

  /// Send, or — once locked — the unresolved box in its place.
  Widget sendArea({required Key sendKey, required VoidCallback onSend}) {
    final op = unsureOp;
    if (op != null) {
      return Padding(
        padding: const EdgeInsets.only(top: 12),
        child: UnresolvedBox(
          submitter: submitter,
          opId: op,
          firstFailure: _unsureWhy,
          inForm: true,
          onRecorded: () {
            if (mounted) Navigator.of(context).pop(true);
          },
          // Settled not recorded — refused, or cancelled by the server: the
          // fields open again, saying why; the next Send is a new operation.
          onSettledNotRecorded: (f) => setState(() {
            unsureOp = null;
            failure = f;
          }),
        ),
      );
    }
    final f = failure;
    final m = message;
    return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
      if (f != null)
        Padding(
          padding: const EdgeInsets.only(top: 12),
          child: FailureNotice(key: const Key('stock-failure'), english: stockFailureCopy(f).english, tagalog: stockFailureCopy(f).tagalog),
        ),
      if (m != null)
        Padding(
          padding: const EdgeInsets.only(top: 12),
          child: FailureNotice(key: const Key('stock-blocked'), english: m.english, tagalog: m.tagalog),
        ),
      const SizedBox(height: 12),
      sending ? const LinearProgressIndicator() : bilingualButton(sendLabel, onSend, filled: true, key: sendKey),
    ]);
  }
}

/// One unresolved stock submission (R101–R103): what it was, and Send again
/// (unchanged), Check (read only) or Cancel it (the server settles the id —
/// recorded, or cancelled for good). Never sends by itself.
class UnresolvedBox extends StatefulWidget {
  const UnresolvedBox({
    super.key,
    required this.submitter,
    required this.opId,
    required this.onRecorded,
    required this.onSettledNotRecorded,
    this.inForm = false,
    this.firstFailure,
  });

  final StockSubmitter submitter;
  final String opId;
  final VoidCallback onRecorded;

  /// Refused with nothing left to arrive, or cancelled by the server: nothing
  /// was recorded ([StockFailure.opCancelled] for a cancel).
  final ValueChanged<StockFailure> onSettledNotRecorded;

  /// In its own form: "Cancel it and change"; on the Stock tab: "Cancel it".
  final bool inForm;
  final StockFailure? firstFailure;

  @override
  State<UnresolvedBox> createState() => _UnresolvedBoxState();
}

class _UnresolvedBoxState extends State<UnresolvedBox> {
  Bilingual? _note;

  @override
  void initState() {
    super.initState();
    final f = widget.firstFailure;
    if (f != null) _note = stockFailureCopy(f);
  }

  StockSubmitter get _s => widget.submitter;

  Future<void> _sendAgain() async {
    final o = await _s.retry(widget.opId);
    if (!mounted) return;
    switch (o.result) {
      case StockSendResult.recorded:
        widget.onRecorded();
      case StockSendResult.refused:
        widget.onSettledNotRecorded(o.failure ?? StockFailure.unexpected);
      case StockSendResult.unsure:
        final f = o.failure;
        setState(() => _note = f == null ? null : (f.uncertain ? stockFailureCopy(f) : retryRefusedCopy(stockFailureCopy(f))));
      case StockSendResult.blocked:
        break;
    }
  }

  Future<void> _settle({required bool cancel}) async {
    final o = cancel ? await _s.cancel(widget.opId) : await _s.check(widget.opId);
    if (!mounted) return;
    switch (o.result) {
      case StockSettleResult.recorded:
        widget.onRecorded();
      case StockSettleResult.cancelled:
        widget.onSettledNotRecorded(StockFailure.opCancelled);
      case StockSettleResult.pending:
        setState(() => _note = notYetCopy);
      case StockSettleResult.unknown:
        setState(() => _note = stockFailureCopy(o.failure ?? StockFailure.noConnection));
    }
  }

  @override
  Widget build(BuildContext context) => ListenableBuilder(
        listenable: _s,
        builder: (context, _) {
          final s = _s.byOp(widget.opId);
          if (s == null) return const SizedBox.shrink();
          final busy = _s.isBusy(s.opId);
          final note = _note;
          return Container(
            key: Key('unsure-${s.opId}'),
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(color: WmColors.brownTint, borderRadius: BorderRadius.circular(14)),
            child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
              const BilingualText(notSureLabel, style: TextStyle(fontWeight: FontWeight.w700, color: WmColors.brownDeep)),
              const SizedBox(height: 6),
              Text(s.summary, style: const TextStyle(fontWeight: FontWeight.w700)),
              if (s.lastSentAt != null)
                Text('Sent ${s.sends == 1 ? 'once' : '${s.sends} times'} · last ${clockTime(s.lastSentAt!)}',
                    style: const TextStyle(fontSize: 12.5, color: WmColors.textMuted)),
              if (note != null) ...[
                const SizedBox(height: 6),
                BilingualText(note, style: const TextStyle(fontSize: 13, color: WmColors.danger)),
              ],
              const SizedBox(height: 10),
              if (busy)
                const LinearProgressIndicator()
              else ...[
                Row(children: [
                  Expanded(child: bilingualButton(sendAgainLabel, _sendAgain, filled: true, key: const Key('unsure-send-again'))),
                  const SizedBox(width: 8),
                  Expanded(child: bilingualButton(checkLabel, () => _settle(cancel: false), key: const Key('unsure-check'))),
                ]),
                const SizedBox(height: 8),
                bilingualButton(widget.inForm ? cancelChangeLabel : cancelLabel, () => _settle(cancel: true), key: const Key('unsure-cancel')),
              ],
            ]),
          );
        },
      );
}

/// A saved stock record the phone can no longer read, of this account (R104):
/// Check or Cancel it by its operation id — its payload is never rebuilt, so
/// there is no Send again. Never sends by itself.
class UnreadableBox extends StatefulWidget {
  const UnreadableBox({super.key, required this.submitter, required this.opId, required this.onRecorded, required this.onSettledNotRecorded});

  final StockSubmitter submitter;
  final String opId;
  final VoidCallback onRecorded;
  final ValueChanged<StockFailure> onSettledNotRecorded;

  @override
  State<UnreadableBox> createState() => _UnreadableBoxState();
}

class _UnreadableBoxState extends State<UnreadableBox> {
  Bilingual? _note;

  Future<void> _settle({required bool cancel}) async {
    final s = widget.submitter;
    final o = cancel ? await s.cancel(widget.opId) : await s.check(widget.opId);
    if (!mounted) return;
    switch (o.result) {
      case StockSettleResult.recorded:
        widget.onRecorded();
      case StockSettleResult.cancelled:
        widget.onSettledNotRecorded(StockFailure.opCancelled);
      case StockSettleResult.pending:
        setState(() => _note = unreadablePendingCopy);
      case StockSettleResult.unknown:
        setState(() => _note = stockFailureCopy(o.failure ?? StockFailure.noConnection));
    }
  }

  @override
  Widget build(BuildContext context) => ListenableBuilder(
        listenable: widget.submitter,
        builder: (context, _) {
          final s = widget.submitter;
          if (!s.unreadable.any((u) => u.opId == widget.opId)) return const SizedBox.shrink();
          final note = _note;
          return Container(
            key: Key('unreadable-${widget.opId}'),
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(color: WmColors.dangerTint, borderRadius: BorderRadius.circular(14)),
            child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
              const BilingualText(unreadableLabel, style: TextStyle(fontWeight: FontWeight.w700, color: WmColors.danger)),
              if (note != null) ...[
                const SizedBox(height: 6),
                BilingualText(note, style: const TextStyle(fontSize: 13, color: WmColors.danger)),
              ],
              const SizedBox(height: 10),
              if (s.isBusy(widget.opId))
                const LinearProgressIndicator()
              else
                Row(children: [
                  Expanded(child: bilingualButton(checkLabel, () => _settle(cancel: false), key: const Key('unreadable-check'))),
                  const SizedBox(width: 8),
                  Expanded(child: bilingualButton(cancelLabel, () => _settle(cancel: true), filled: true, key: const Key('unreadable-cancel'))),
                ]),
            ]),
          );
        },
      );
}

/// The day the goods moved: today unless picked earlier (never later).
class StockDayField extends StatelessWidget {
  const StockDayField({super.key, required this.value, required this.today, required this.onChanged});

  final String value;
  final String today;

  /// Null: locked.
  final ValueChanged<String>? onChanged;

  @override
  Widget build(BuildContext context) => OutlinedButton.icon(
        key: const Key('stock-day'),
        icon: const Icon(Icons.event_outlined),
        label: Text(value == today ? 'Today · $value' : value),
        onPressed: onChanged == null
            ? null
            : () async {
                final last = DateTime.parse(today);
                final picked = await showDatePicker(
                  context: context,
                  initialDate: DateTime.tryParse(value) ?? last,
                  firstDate: DateTime(2020),
                  lastDate: last,
                );
                if (picked != null) {
                  onChanged!('${picked.year.toString().padLeft(4, '0')}-${picked.month.toString().padLeft(2, '0')}-${picked.day.toString().padLeft(2, '0')}');
                }
              },
      );
}

/// A small heading over a form field.
class StockFieldLabel extends StatelessWidget {
  const StockFieldLabel(this.text, {super.key});
  final String text;

  @override
  Widget build(BuildContext context) => Padding(
        padding: const EdgeInsets.only(top: 14, bottom: 6),
        child: Text(text, style: const TextStyle(fontWeight: FontWeight.w700, color: WmColors.textSecondary)),
      );
}
