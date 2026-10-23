import 'package:flutter/material.dart';

import '../../attendance/ui/attendance_copy.dart' show Bilingual;
import '../../requests/domain/quantity.dart';
import '../../ui/failure_notice.dart';
import '../../ui/theme.dart';
import '../data/purchasing_api.dart';
import '../domain/pay_models.dart';
import '../domain/pur_failure.dart';
import '../domain/pur_models.dart';
import '../pay/record_payment_screen.dart';
import '../purchasing_services.dart';
import '../ui/pay_copy.dart';
import '../ui/pay_widgets.dart';
import '../ui/purchasing_copy.dart';
import 'correct_screen.dart';

/// One purchase in full (Q12): lines, fees, receipts and where it stands.
/// The buyer may correct their own recorded purchase here (Q13); voiding
/// stays on Dacs Web.
class PurchaseDetailScreen extends StatefulWidget {
  const PurchaseDetailScreen({super.key, required this.purchaseId, required this.services});
  final String purchaseId;
  final PurchasingServices services;

  @override
  State<PurchaseDetailScreen> createState() => _PurchaseDetailScreenState();
}

class _PurchaseDetailScreenState extends State<PurchaseDetailScreen> {
  PurchaseDetail? _p;
  Bilingual? _error;
  bool _changed = false;

  /// Its payments (0102), read online beside the purchase; their own failure
  /// never hides the purchase.
  PurchasePayments? _pay;
  Bilingual? _payNotice;

  /// Payments on this purchase the payments read does not count (Q6, R38):
  /// shown, and counted in what is left — as on My purchases — so the same
  /// remainder is never offered twice.
  List<QueuedCashAction> _queued = const [];
  double get _unsent =>
      _queued.where((q) => q.state != QueuedState.needsAttention).fold<double>(0, (a, q) => a + q.amount);

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() => _error = null);
    try {
      final p = await widget.services.api.purchase(widget.purchaseId);
      if (mounted) setState(() => _p = p);
    } catch (e) {
      if (mounted) setState(() => _error = purFailureCopy(PurFailure.of(e)));
    }
    try {
      // R38: the payments and what is still on the phone, from one read.
      final v = await widget.services.api.purchasePayments(widget.purchaseId);
      if (mounted) {
        setState(() {
          _pay = v.pay;
          _queued = v.queued;
        });
      }
    } catch (_) {
      // Shown as "needs signal" in the Payments part only; what is on the
      // phone still shows.
      try {
        final queued = await widget.services.api.queuedPayments(widget.purchaseId);
        if (mounted) setState(() => _queued = queued);
      } catch (_) {
        // Nothing on the phone to show.
      }
    }
  }

  Future<void> _recordPayment(PurchaseDetail p, PurchasePayments pay) async {
    final queued = await openRecordPayment(context, widget.services,
        purchaseId: p.id, supplier: p.supplier, supplierId: pay.supplierId ?? p.supplierId, left: pay.pay.leftAfter(_unsent));
    if (!queued || !mounted) return;
    _changed = true;
    ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
      content: Text('Saved. It is sent when there is signal. · Nai-save. Ipapadala kapag may signal.'),
    ));
    await _load();
  }

  /// Q7: never edited or deleted — voided with a reason, by whoever recorded it.
  Future<void> _void(PurPayment x) async {
    final api = widget.services.api;
    final opId = api.newLineKey(); // minted once per form: a resend voids once
    final reason = await askRequiredNote(
      context,
      title: 'Void this payment?',
      message: '${peso(x.amount)} on ${x.paidOn}. It stays in the history, marked void. Petty cash it used comes back on your balance.',
      action: 'Void',
      label: 'Reason',
      fieldKey: const Key('void-reason'),
      sendKey: const Key('void-yes'),
    );
    if (reason == null || !mounted) return;
    setState(() => _payNotice = null);
    try {
      await api.voidPayment(x.id, reason, opId: opId);
      _changed = true;
    } catch (e) {
      final f = PurFailure.of(e);
      if (mounted) setState(() => _payNotice = f == PurFailure.noConnection ? needsSignal : purFailureCopy(f));
    }
    await _load();
  }

  Widget _payments(PurchaseDetail p) {
    final pay = _pay;
    if (pay == null) {
      return const Padding(
        key: Key('payments-offline'),
        padding: EdgeInsets.only(top: 16),
        child: Text('Payments show when there is signal.', style: TextStyle(color: WmColors.textMuted)),
      );
    }
    final s = pay.pay;
    return Column(key: const Key('payments'), crossAxisAlignment: CrossAxisAlignment.start, children: [
      const SizedBox(height: 16),
      Row(children: [
        const Expanded(child: BilingualText(paymentsLabel)),
        PayPill(s.state),
      ]),
      Text(
        s.state == 'not_tracked'
            ? 'Recorded before payments were tracked.'
            : s.state == 'overpaid'
                ? 'Paid ${peso(s.paid)} on ${peso(s.due)} — ${peso(s.unresolved)} over, the owner resolves it.'
                : 'Receipt ${peso(s.due)} · paid ${peso(s.paid)} · left ${peso(s.leftAfter(_unsent))}'
                    '${_unsent > 0 ? ' · ${peso(_unsent)} ${_queued.any((q) => q.state == QueuedState.sent) ? 'not in this list yet' : 'waiting to send'}' : ''}',
        style: const TextStyle(fontSize: 13, color: WmColors.textSecondary),
      ),
      if (_payNotice != null) ...[
        const SizedBox(height: 8),
        FailureNotice(english: _payNotice!.english, tagalog: _payNotice!.tagalog),
      ],
      for (final q in _queued)
        ListTile(
          key: Key('payment-queued-${q.opId}'),
          contentPadding: EdgeInsets.zero,
          title: Text(peso(q.amount)),
          subtitle: Text([
            paySourceCopy(q.source).english,
            switch (q.state) {
              QueuedState.waiting => waitingToSendPayLabel.english,
              QueuedState.sent => sentLabel.english,
              QueuedState.needsAttention => attentionLabel.english,
            },
            if (q.failure != null) purFailureCopy(q.failure!).english,
          ].join(' · ')),
        ),
      for (final x in pay.payments)
        ListTile(
          key: Key('payment-${x.id}'),
          contentPadding: EdgeInsets.zero,
          leading: x.proofUrl.isEmpty ? null : SizedBox(width: 48, height: 48, child: _Receipt(url: x.proofUrl, services: widget.services)),
          title: Text('${peso(x.amount)} · ${x.paidOn}', style: TextStyle(decoration: x.voided ? TextDecoration.lineThrough : null)),
          subtitle: Text([
            paySourceCopy(x.source).english,
            if (x.source != 'credit') payMethodLabel(x.method),
            if (x.createdByName.isNotEmpty) 'recorded by ${x.createdByName}',
            if (x.moved) 'carried over from the earlier version',
            if (x.toReview) 'own money: the owner reviews it',
            if (x.rejectedAt != null) 'rejected by the owner: ${x.rejectReason} — not owed',
            if (x.voided) 'voided: ${x.voidReason}',
            if (x.note.isNotEmpty) x.note,
          ].join(' · ')),
          trailing: x.canVoid && !x.voided ? TextButton(key: Key('void-${x.id}'), onPressed: () => _void(x), child: const Text('Void…')) : null,
        ),
      if (s.canRecordPayment && p.recorded && p.replacedBy == null) ...[
        const SizedBox(height: 8),
        bilingualButton(recordPaymentLabel, () => _recordPayment(p, pay), key: const Key('detail-pay')),
      ],
    ]);
  }

  Future<void> _correct(PurchaseDetail p) async {
    final done = await Navigator.of(context).push<String>(
      MaterialPageRoute(builder: (_) => CorrectScreen(purchase: p, services: widget.services)),
    );
    if (done == null || !mounted) return;
    _changed = true;
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(done)));
    await _load();
  }

  @override
  Widget build(BuildContext context) {
    final p = _p;
    return PopScope(
      canPop: false,
      onPopInvokedWithResult: (didPop, _) {
        if (!didPop) Navigator.of(context).pop(_changed);
      },
      child: Scaffold(
        appBar: AppBar(title: const Text('Purchase')),
        body: SafeArea(
          child: _error != null && p == null
              ? Padding(
                  padding: const EdgeInsets.all(16),
                  child: FailureNotice(english: _error!.english, tagalog: _error!.tagalog, actions: [noticeAction('Try again · Subukan ulit', _load)]),
                )
              : p == null
                  ? const Center(child: CircularProgressIndicator())
                  : _body(p),
        ),
      ),
    );
  }

  Widget _body(PurchaseDetail p) {
    final canCorrect = p.recorded && !p.waitingForOwner && p.replacedBy == null;
    return ListView(padding: const EdgeInsets.all(16), children: [
      Row(children: [
        Expanded(child: Text(p.supplier.isEmpty ? 'No supplier' : p.supplier, style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 20))),
        Text(peso(p.receiptTotal), style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 20)),
      ]),
      Text('${p.purchaseDate} · bought by ${p.boughtByName}${p.paymentMethod.isEmpty ? '' : ' · ${p.paymentMethod}'}',
          style: const TextStyle(color: WmColors.textMuted)),
      const SizedBox(height: 8),
      Wrap(spacing: 6, runSpacing: 6, children: [
        if (!p.recorded) const Chip(label: Text('Voided')),
        if (p.waitingForOwner) const Chip(key: Key('waiting-owner'), label: Text('Waiting for the owner')),
        if (p.needsOfficeCheck) const Chip(label: Text('Needs office check')),
        if (p.noReceiptReason.isNotEmpty) Chip(label: Text('No receipt: ${p.noReceiptReason}')),
      ]),
      const SizedBox(height: 14),
      for (final l in p.lines)
        Card(
          color: Colors.white,
          child: ListTile(
            title: Text(l.itemName, style: const TextStyle(fontWeight: FontWeight.w700)),
            subtitle: Text([
              qtyUnit(l.quantity, l.unit),
              l.destination == 'warehouse' ? 'Warehouse' : l.folderName,
              if (l.unitCheck == 'pending') 'counts after the office check',
              if (l.unplannedReason.isNotEmpty) 'no request: ${l.unplannedReason}',
              if (l.extra > 0) 'extra ${formatQuantity(l.extra)}',
            ].join(' · ')),
            trailing: Text(peso(l.amount)),
          ),
        ),
      for (final c in p.charges)
        ListTile(
          dense: true,
          title: Text(c.kind == 'delivery_fee' ? 'Delivery fee' : 'Discount'),
          trailing: Text('${c.kind == 'discount' ? '−' : ''}${peso(c.amount)}'),
        ),
      const SizedBox(height: 12),
      const Text('Receipt photos', style: TextStyle(fontWeight: FontWeight.w800)),
      const SizedBox(height: 6),
      if (p.docs.isEmpty) Text(p.noReceiptReason.isEmpty ? 'None' : 'No receipt: ${p.noReceiptReason}'),
      Wrap(spacing: 8, runSpacing: 8, children: [
        for (final e in p.docs.entries) _Receipt(key: Key('receipt-${e.key}'), url: e.value, services: widget.services),
      ]),
      for (final r in p.changeRequests)
        Padding(
          padding: const EdgeInsets.only(top: 10),
          child: Text('Change sent to the owner (${r.status}): ${r.reason}${r.decisionNote.isEmpty ? '' : ' — ${r.decisionNote}'}',
              style: const TextStyle(color: WmColors.textSecondary)),
        ),
      _payments(p),
      const SizedBox(height: 20),
      if (canCorrect) bilingualButton(const Bilingual('Correct this purchase', 'Itama ang purchase'), () => _correct(p), key: const Key('correct')),
      const SizedBox(height: 8),
      const Text('A purchase is voided on Dacs Web only.', style: TextStyle(fontSize: 12.5, color: WmColors.textMeta)),
    ]);
  }
}

class _Receipt extends StatelessWidget {
  const _Receipt({super.key, required this.url, required this.services});
  final String url;
  final PurchasingServices services;

  @override
  Widget build(BuildContext context) => FutureBuilder(
        future: services.api.receipt(url),
        builder: (context, snap) {
          final bytes = snap.data;
          return ClipRRect(
            borderRadius: BorderRadius.circular(10),
            child: SizedBox(
              width: 96,
              height: 96,
              child: bytes == null
                  ? const ColoredBox(color: WmColors.inert, child: Icon(Icons.receipt_long))
                  : GestureDetector(
                      onTap: () => Navigator.of(context).push(MaterialPageRoute<void>(
                        builder: (_) => Scaffold(
                          backgroundColor: WmColors.viewerBackdrop,
                          appBar: AppBar(backgroundColor: WmColors.viewerBackdrop, foregroundColor: Colors.white),
                          body: InteractiveViewer(child: Center(child: Image.memory(bytes))),
                        ),
                      )),
                      child: Image.memory(bytes, fit: BoxFit.cover, errorBuilder: (_, _, _) => const Icon(Icons.receipt_long)),
                    ),
            ),
          );
        },
      );
}
