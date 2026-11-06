import 'package:flutter/material.dart';

import '../../attendance/ui/attendance_copy.dart' show Bilingual;
import '../../attendance/ui/formats.dart' show clockTime;
import '../../purchasing/ui/purchasing_copy.dart' show BilingualText, bilingualButton;
import '../../ui/failure_notice.dart';
import '../../ui/theme.dart';
import '../data/tool_submitter.dart';
import '../domain/tool_failure.dart';
import '../domain/tool_submission.dart';
import 'tools_copy.dart';

/// A tool form's Send (Q22, stock's rule): the phone's own checks first, then
/// the submission goes through [ToolSubmitter] — saved with its operation id
/// and exact payload before it leaves. If the answer is lost the form LOCKS:
/// its fields cannot change, and only Send again (the saved payload), Check,
/// or Cancel it and change are offered — the last one unlocks the fields only
/// once the SERVER confirms the id cancelled.
mixin ToolSending<T extends StatefulWidget> on State<T> {
  ToolSubmitter get submitter;

  bool sending = false;
  ToolFailure? failure;
  Bilingual? message;

  /// The unresolved submission this form sent; the fields are locked while set.
  String? unsureOp;
  ToolFailure? _unsureWhy;

  bool get locked => unsureOp != null;

  /// True when the server recorded it.
  Future<bool> sendChecked(
    List<ToolFailure> problems, {
    required ToolWrite write,
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
      if (!mounted) return o.result == ToolSendResult.recorded;
      setState(() {
        switch (o.result) {
          case ToolSendResult.recorded:
            break;
          case ToolSendResult.refused:
            failure = o.failure;
          case ToolSendResult.blocked:
            message = finishFirst;
          case ToolSendResult.unsure:
            unsureOp = o.opId;
            _unsureWhy = o.failure;
        }
      });
      return o.result == ToolSendResult.recorded;
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
        child: ToolUnresolvedBox(
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
          child: FailureNotice(key: const Key('tool-failure'), english: toolFailureCopy(f).english, tagalog: toolFailureCopy(f).tagalog),
        ),
      if (m != null)
        Padding(
          padding: const EdgeInsets.only(top: 12),
          child: FailureNotice(key: const Key('tool-blocked'), english: m.english, tagalog: m.tagalog),
        ),
      const SizedBox(height: 12),
      sending ? const LinearProgressIndicator() : bilingualButton(sendLabel, onSend, filled: true, key: sendKey),
    ]);
  }
}

/// One unresolved tool submission: what it was, and Send again (unchanged),
/// Check (read only) or Cancel it (the server settles the id — recorded, or
/// cancelled for good). Never sends by itself.
class ToolUnresolvedBox extends StatefulWidget {
  const ToolUnresolvedBox({
    super.key,
    required this.submitter,
    required this.opId,
    required this.onRecorded,
    required this.onSettledNotRecorded,
    this.inForm = false,
    this.firstFailure,
  });

  final ToolSubmitter submitter;
  final String opId;
  final VoidCallback onRecorded;

  /// Refused with nothing left to arrive, or cancelled by the server: nothing
  /// was recorded ([ToolFailure.opCancelled] for a cancel).
  final ValueChanged<ToolFailure> onSettledNotRecorded;

  /// In its own form: "Cancel it and change"; on the Tools screen: "Cancel it".
  final bool inForm;
  final ToolFailure? firstFailure;

  @override
  State<ToolUnresolvedBox> createState() => _ToolUnresolvedBoxState();
}

class _ToolUnresolvedBoxState extends State<ToolUnresolvedBox> {
  Bilingual? _note;

  @override
  void initState() {
    super.initState();
    final f = widget.firstFailure;
    if (f != null) _note = toolFailureCopy(f);
  }

  ToolSubmitter get _s => widget.submitter;

  Future<void> _sendAgain() async {
    final o = await _s.retry(widget.opId);
    if (!mounted) return;
    switch (o.result) {
      case ToolSendResult.recorded:
        widget.onRecorded();
      case ToolSendResult.refused:
        widget.onSettledNotRecorded(o.failure ?? ToolFailure.unexpected);
      case ToolSendResult.unsure:
        final f = o.failure;
        setState(() => _note = f == null ? null : (f.uncertain ? toolFailureCopy(f) : retryRefusedCopy(toolFailureCopy(f))));
      case ToolSendResult.blocked:
        break;
    }
  }

  Future<void> _settle({required bool cancel}) async {
    final o = cancel ? await _s.cancel(widget.opId) : await _s.check(widget.opId);
    if (!mounted) return;
    switch (o.result) {
      case ToolSettleResult.recorded:
        widget.onRecorded();
      case ToolSettleResult.cancelled:
        widget.onSettledNotRecorded(ToolFailure.opCancelled);
      case ToolSettleResult.pending:
        setState(() => _note = notYetCopy);
      case ToolSettleResult.unknown:
        setState(() => _note = toolFailureCopy(o.failure ?? ToolFailure.noConnection));
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

/// A saved tool record the phone can no longer read, of this account: Check
/// or Cancel it by its operation id — its payload is never rebuilt, so there
/// is no Send again. Never sends by itself.
class ToolUnreadableBox extends StatefulWidget {
  const ToolUnreadableBox({super.key, required this.submitter, required this.opId, required this.onRecorded, required this.onSettledNotRecorded});

  final ToolSubmitter submitter;
  final String opId;
  final VoidCallback onRecorded;
  final ValueChanged<ToolFailure> onSettledNotRecorded;

  @override
  State<ToolUnreadableBox> createState() => _ToolUnreadableBoxState();
}

class _ToolUnreadableBoxState extends State<ToolUnreadableBox> {
  Bilingual? _note;

  Future<void> _settle({required bool cancel}) async {
    final s = widget.submitter;
    final o = cancel ? await s.cancel(widget.opId) : await s.check(widget.opId);
    if (!mounted) return;
    switch (o.result) {
      case ToolSettleResult.recorded:
        widget.onRecorded();
      case ToolSettleResult.cancelled:
        widget.onSettledNotRecorded(ToolFailure.opCancelled);
      case ToolSettleResult.pending:
        setState(() => _note = unreadablePendingCopy);
      case ToolSettleResult.unknown:
        setState(() => _note = toolFailureCopy(o.failure ?? ToolFailure.noConnection));
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

/// A small heading over a form field.
class ToolFieldLabel extends StatelessWidget {
  const ToolFieldLabel(this.text, {super.key});
  final String text;

  @override
  Widget build(BuildContext context) => Padding(
        padding: const EdgeInsets.only(top: 14, bottom: 6),
        child: Text(text, style: const TextStyle(fontWeight: FontWeight.w700, color: WmColors.textSecondary)),
      );
}

/// A white card, as the Stock tab's.
class ToolBox extends StatelessWidget {
  const ToolBox({super.key, required this.children, this.onTap});
  final List<Widget> children;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) => Card(
        margin: const EdgeInsets.only(top: 10),
        color: Colors.white,
        clipBehavior: Clip.antiAlias,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16), side: const BorderSide(color: WmColors.border)),
        child: InkWell(
          onTap: onTap,
          child: Padding(
            padding: const EdgeInsets.all(14),
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: children),
          ),
        ),
      );
}

/// What a form says it was, if its answer is lost: "TOOL-0003 Grinder".
String toolWords(String label, String name) => '$label $name';
