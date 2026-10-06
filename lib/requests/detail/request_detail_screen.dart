import 'package:flutter/material.dart';

import '../../attendance/ui/attendance_copy.dart';
import '../../attendance/ui/formats.dart';
import '../../ui/failure_notice.dart';
import '../../ui/theme.dart';
import '../data/requests_api.dart';
import '../domain/quantity.dart';
import '../domain/remote_request.dart';
import '../domain/request_draft.dart';
import '../domain/request_op.dart';
import '../domain/request_status.dart';
import '../list/requests_controller.dart';
import '../ui/requests_copy.dart';
import '../ui/sync_chip.dart';

/// One request: each item's progress and expected delivery per weekly batch,
/// what is still on the phone, what was refused, and — for the requester —
/// quantity changes and cancelling. Reads its entry from the shared
/// controller by [entryKey], so it follows every refresh.
class RequestDetailScreen extends StatelessWidget {
  const RequestDetailScreen({
    super.key,
    required this.controller,
    required this.api,
    required this.entryKey,
    required this.onEditDraft,
  });

  final RequestsController controller;
  final RequestsApi api;
  final String entryKey;

  /// A refused draft, back in the editor.
  final void Function(String draftId) onEditDraft;

  Future<void> _changeQuantity(BuildContext context, RemoteRequest r, RemoteLine l, double current) async {
    final qty = await showDialog<double>(context: context, builder: (_) => _QuantityDialog(line: l, current: current));
    if (qty == null || qty == current) return;
    await api.changeQuantity(r, l, qty);
    await controller.refresh();
  }

  Future<bool> _confirm(BuildContext context, String title, String body) async =>
      await showDialog<bool>(
        context: context,
        builder: (context) => AlertDialog(
          title: Text(title),
          content: Text(body),
          actions: [
            TextButton(onPressed: () => Navigator.of(context).pop(false), child: const Text('Keep')),
            TextButton(key: const Key('confirm-cancel'), onPressed: () => Navigator.of(context).pop(true), child: const Text('Cancel it')),
          ],
        ),
      ) ==
      true;

  Future<void> _cancelLine(BuildContext context, RemoteRequest r, RemoteLine l) async {
    if (!await _confirm(context, 'Cancel ${l.description}?', 'The office is told. Anything already arranged is sorted out by them.')) return;
    await api.cancelLine(r, l);
    await controller.refresh();
  }

  Future<void> _cancelRequest(BuildContext context, RemoteRequest r) async {
    if (!await _confirm(context, 'Cancel the whole request?', 'Every item still open is cancelled. Anything already arranged is sorted out by the office.')) {
      return;
    }
    await api.cancelRequest(r);
    await controller.refresh();
  }

  @override
  Widget build(BuildContext context) => ListenableBuilder(
        listenable: controller,
        builder: (context, _) {
          final e = controller.entry(entryKey);
          return Scaffold(
            appBar: AppBar(title: const Text('Request')),
            body: SafeArea(
              child: e == null
                  ? const Center(child: Text('This request is no longer on the list.'))
                  : RefreshIndicator(
                      onRefresh: controller.refresh,
                      child: ListView(
                        physics: const AlwaysScrollableScrollPhysics(),
                        padding: const EdgeInsets.fromLTRB(20, 8, 20, 24),
                        children: e.remote != null ? _remote(context, e, e.remote!) : _onPhone(e, e.draft!),
                      ),
                    ),
            ),
          );
        },
      );

  List<Widget> _failures(RequestEntry e) => [
        for (final op in e.failedOps)
          Padding(
            padding: const EdgeInsets.only(bottom: 12),
            child: FailureNotice(
              leadEnglish: '${_opLabel(op, _lineName(e, op))}: ${notAcceptedLead.english}',
              leadTagalog: notAcceptedLead.tagalog,
              english: opFailureCopy(op).english,
              tagalog: opFailureCopy(op).tagalog,
              actions: [
                if (op.kind == OpKind.submit && op.draftId != null)
                  noticeAction(backToDraftsLabel, () => onEditDraft(op.draftId!))
                else
                  noticeAction(dismissLabel, () => controller.dismissFailed(op)),
              ],
            ),
          ),
      ];

  /// Sent from this phone, not yet confirmed by the server (or refused).
  List<Widget> _onPhone(RequestEntry e, RequestDraft d) => [
        Row(children: [
          Expanded(child: Text(d.destination?.label ?? '', style: const TextStyle(fontSize: 20, fontWeight: FontWeight.w800))),
          SyncChip(e.state),
        ]),
        const SizedBox(height: 4),
        Text(d.teamName == null ? 'Just me' : 'Team ${d.teamName}', style: const TextStyle(color: WmColors.textMuted)),
        const SizedBox(height: 12),
        if (e.state == SyncState.pending)
          const Text('Saved on this phone. It is sent as soon as there is signal.', style: TextStyle(color: WmColors.brown)),
        ..._failures(e),
        const SizedBox(height: 8),
        for (final l in d.lines)
          _Card(children: [
            Text(l.description, style: const TextStyle(fontWeight: FontWeight.w800)),
            Text(
              [l.kind.label, if (l.spec.isNotEmpty) l.spec, '${formatQuantity(parseQuantity(l.quantity) ?? 0)} ${l.unit}'].join(' · '),
              style: const TextStyle(color: WmColors.textMuted),
            ),
            if (l.urgent) ...[const SizedBox(height: 6), UrgentTag(neededBy: l.neededBy)],
          ]),
      ];

  List<Widget> _remote(BuildContext context, RequestEntry e, RemoteRequest r) => [
        Row(children: [
          Expanded(child: Text(r.title, style: const TextStyle(fontSize: 20, fontWeight: FontWeight.w800))),
          SyncChip(e.state),
        ]),
        const SizedBox(height: 4),
        Text(
          [
            if (!r.mine) 'From ${r.requesterName}',
            r.teamName == null ? 'Just me' : 'Team ${r.teamName}',
            'Received ${dayMonth(r.receivedAt)}, ${clockTime(r.receivedAt)}',
          ].join(' · '),
          style: const TextStyle(color: WmColors.textMuted),
        ),
        if (r.note.isNotEmpty) ...[const SizedBox(height: 6), Text(r.note)],
        // The chip says it already, unless something unsent outranks it.
        if (r.cancelled && e.state != SyncState.cancelled) ...[const SizedBox(height: 8), const Text('Cancelled', style: TextStyle(color: WmColors.danger, fontWeight: FontWeight.w700))],
        const SizedBox(height: 12),
        ..._failures(e),
        for (final l in r.lines) _line(context, e, r, l),
        if (canCancelRequest(r) && !e.pendingOps.any((o) => o.kind == OpKind.cancelRequest))
          TextButton(
            key: const Key('cancel-request'),
            onPressed: () => _cancelRequest(context, r),
            style: TextButton.styleFrom(foregroundColor: WmColors.danger),
            child: const Text('Cancel the whole request'),
          ),
      ];

  Widget _line(BuildContext context, RequestEntry e, RemoteRequest r, RemoteLine l) {
    final pendingQty = e.pendingQuantity(l.id);
    final cancelPending = e.cancelPending(l.id);
    final progress = lineProgress(l);
    final photos = r.photos.where((p) => p.lineId == l.id).toList();
    return _Card(key: Key('line-${l.id}'), children: [
      Row(children: [
        Expanded(child: Text(l.description, style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 16))),
        Text('${formatQuantity(l.needed)} ${l.unit}', style: const TextStyle(fontWeight: FontWeight.w800)),
      ]),
      Text(
        [
          l.kind.label,
          if (l.spec.isNotEmpty) l.spec,
          if (l.catalogItemId == null) 'Not in the list',
          if (l.intendedMemberName != null) 'For ${l.intendedMemberName}',
        ].join(' · '),
        style: const TextStyle(color: WmColors.textMuted, fontSize: 13),
      ),
      const SizedBox(height: 6),
      Wrap(spacing: 6, runSpacing: 6, children: [
        Text(lineProgressLabel(progress),
            style: TextStyle(
              fontWeight: FontWeight.w700,
              color: progress == LineProgress.needsResolution || progress == LineProgress.officeChecking ? WmColors.danger : WmColors.green,
            )),
        if (l.urgent) UrgentTag(neededBy: l.neededBy),
      ]),
      if (pendingQty != null)
        Text('Changing to ${formatQuantity(pendingQty)} ${l.unit} · ${syncLabel(SyncState.pending)}',
            style: const TextStyle(color: WmColors.brown, fontWeight: FontWeight.w700)),
      if (cancelPending) Text('Cancelling · ${syncLabel(SyncState.pending)}', style: const TextStyle(color: WmColors.brown, fontWeight: FontWeight.w700)),
      if (progress == LineProgress.needsResolution)
        const Text('Your change and the office\'s change differ. The office will decide and tell you.',
            style: TextStyle(fontSize: 12.5, color: WmColors.textMuted)),
      const SizedBox(height: 6),
      for (final p in l.portions)
        Text(
          '${formatQuantity(p.quantity)} ${l.unit} · ${p.arranged ? 'Arranged · ' : ''}Expected ${calendarDay(p.deliveryOn)}',
          style: const TextStyle(fontSize: 13),
        ),
      if (photos.isNotEmpty) ...[
        const SizedBox(height: 8),
        Wrap(spacing: 8, children: [for (final p in photos) _RemotePhoto(key: ValueKey(p.path), api: api, path: p.path)]),
      ],
      if (canChangeLine(r, l) && !cancelPending) ...[
        const SizedBox(height: 4),
        Wrap(children: [
          TextButton(
            key: Key('change-${l.id}'),
            onPressed: () => _changeQuantity(context, r, l, pendingQty ?? l.needed),
            child: const Text('Change quantity'),
          ),
          TextButton(
            key: Key('cancel-${l.id}'),
            onPressed: () => _cancelLine(context, r, l),
            style: TextButton.styleFrom(foregroundColor: WmColors.danger),
            child: const Text('Cancel item'),
          ),
        ]),
      ],
    ]);
  }
}

/// The item an operation was about, for the refusal's lead line.
String? _lineName(RequestEntry e, RequestOp op) =>
    e.remote?.lines.where((l) => l.id == op.lineId).firstOrNull?.description;

String _opLabel(RequestOp op, String? item) => switch (op.kind) {
      OpKind.submit => 'Sending the request',
      OpKind.photo => item == null ? 'A photo' : 'A photo of $item',
      OpKind.quantity => 'Changing ${item ?? 'an item'} to ${formatQuantity(op.quantity ?? 0)}',
      OpKind.cancelLine => 'Cancelling ${item ?? 'an item'}',
      OpKind.cancelRequest => 'Cancelling the request',
    };

class _Card extends StatelessWidget {
  const _Card({super.key, required this.children});
  final List<Widget> children;

  @override
  Widget build(BuildContext context) => Container(
        margin: const EdgeInsets.only(bottom: 10),
        padding: const EdgeInsets.all(14),
        decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(16), border: Border.all(color: WmColors.border)),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: children),
      );
}

/// A private photo through a short-lived link; a grey box when it cannot load.
/// The link is asked for once per photo, not on every rebuild: each new link
/// would be a new download on a site connection.
class _RemotePhoto extends StatefulWidget {
  const _RemotePhoto({super.key, required this.api, required this.path});
  final RequestsApi api;
  final String path;

  @override
  State<_RemotePhoto> createState() => _RemotePhotoState();
}

class _RemotePhotoState extends State<_RemotePhoto> {
  late Future<String?> _url = widget.api.photoUrl(widget.path);

  @override
  void didUpdateWidget(_RemotePhoto old) {
    super.didUpdateWidget(old);
    if (old.path != widget.path) _url = widget.api.photoUrl(widget.path);
  }

  @override
  Widget build(BuildContext context) => FutureBuilder<String?>(
        future: _url,
        builder: (context, snap) {
          final url = snap.data;
          final box = Container(width: 72, height: 72, color: WmColors.inert);
          if (url == null) return box;
          return ClipRRect(
            borderRadius: BorderRadius.circular(10),
            child: Image.network(url, width: 72, height: 72, fit: BoxFit.cover, errorBuilder: (_, _, _) => box),
          );
        },
      );
}

/// The new "still needed" number. Owns its text field, so the field lives
/// exactly as long as the dialog (closing animation included).
class _QuantityDialog extends StatefulWidget {
  const _QuantityDialog({required this.line, required this.current});
  final RemoteLine line;
  final double current;

  @override
  State<_QuantityDialog> createState() => _QuantityDialogState();
}

class _QuantityDialogState extends State<_QuantityDialog> {
  late final _text = TextEditingController(text: formatQuantity(widget.current).replaceAll(',', ''));

  @override
  void dispose() {
    _text.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final parsed = parseQuantity(_text.text);
    return AlertDialog(
      title: Text('Change ${widget.line.description}'),
      content: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.start, children: [
        TextField(
          key: const Key('qty-field'),
          controller: _text,
          autofocus: true,
          keyboardType: const TextInputType.numberWithOptions(decimal: true),
          onChanged: (_) => setState(() {}),
          decoration: InputDecoration(
            labelText: 'Still needed (${widget.line.unit})',
            errorText: parsed == null ? draftIssueText(DraftIssueKind.badQuantity) : null,
          ),
        ),
        const SizedBox(height: 8),
        const Text(
          'What the office already arranged is never erased: a smaller number is flagged for them to sort out.',
          style: TextStyle(fontSize: 12.5, color: WmColors.textMuted),
        ),
      ]),
      actions: [
        TextButton(onPressed: () => Navigator.of(context).pop(), child: const Text('Cancel')),
        TextButton(
          key: const Key('qty-save'),
          onPressed: parsed == null ? null : () => Navigator.of(context).pop(parsed),
          child: const Text('Save'),
        ),
      ],
    );
  }
}
