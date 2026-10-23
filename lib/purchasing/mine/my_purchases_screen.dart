import 'package:flutter/material.dart';

import '../../attendance/ui/attendance_copy.dart' show Bilingual;
import '../../attendance/ui/formats.dart';
import '../../ui/failure_notice.dart';
import '../../ui/theme.dart';
import '../data/purchasing_api.dart';
import '../domain/pur_failure.dart';
import '../domain/pur_models.dart';
import '../domain/purchase_draft.dart';
import '../pay/my_cash_screen.dart';
import '../pay/record_payment_screen.dart';
import '../purchasing_services.dart';
import '../ui/pay_copy.dart';
import '../ui/pay_widgets.dart';
import '../ui/purchasing_copy.dart';
import 'my_purchases_controller.dart';

/// The status words a buyer sees on a purchase (Q12).
List<(String, Color, Color)> purchaseFlags(MyPurchase p) => [
      if (p.voided) ('Voided', WmColors.textSecondary, WmColors.inert) else ('Recorded', WmColors.green, WmColors.greenTint),
      if (p.pendingChange) ('Waiting for the owner', WmColors.brownDeep, WmColors.brownTint),
      if (p.unitCheck) ('Needs office check', WmColors.brownDeep, WmColors.brownTint),
      if (p.noReceiptReason.isNotEmpty) ('No receipt', WmColors.danger, WmColors.dangerTint),
      if (p.unplanned) ('Unplanned', WmColors.textSecondary, WmColors.inert),
      if (p.extra) ('Extra', WmColors.textSecondary, WmColors.inert),
    ];

class MyPurchasesScreen extends StatelessWidget {
  const MyPurchasesScreen({super.key, required this.controller, required this.onOpenDraft, required this.onOpenPurchase, this.services});

  final MyPurchasesController controller;

  /// For Record payment and My cash (0102); none in screens that only list.
  final PurchasingServices? services;

  /// Continue a draft (or a refused purchase sent back to editing).
  final void Function(PurchaseDraft draft) onOpenDraft;
  final void Function(MyPurchase purchase) onOpenPurchase;

  Future<void> _openCash(BuildContext context) async {
    final s = services;
    if (s == null) return;
    await Navigator.of(context).push(MaterialPageRoute<void>(builder: (_) => MyCashScreen(services: s)));
    await controller.refresh();
  }

  /// Q6: a later payment — also with no signal; what is left counts payments still on the phone.
  Future<void> _pay(BuildContext context, MyPurchase p) async {
    final s = services;
    if (s == null) return;
    final queued = await openRecordPayment(context, s,
        purchaseId: p.id, supplier: p.supplier, supplierId: p.supplierId, left: p.pay.leftAfter(controller.view.unsentFor(p.id)));
    if (queued) await controller.refresh();
  }

  Future<void> _fix(QueuedPurchase q) async {
    final d = await controller.edit(q);
    if (d != null) onOpenDraft(d);
  }

  @override
  Widget build(BuildContext context) => ListenableBuilder(
        listenable: controller,
        builder: (context, _) {
          final c = controller;
          final v = c.view;
          return RefreshIndicator(
            onRefresh: c.refresh,
            child: ListView(padding: const EdgeInsets.all(16), children: [
              const Text('My purchases', style: TextStyle(fontWeight: FontWeight.w800, fontSize: 23)),
              const Text('Mga binili ko · last 60 days', style: TextStyle(fontSize: 13, color: WmColors.textMuted)),
              if (c.notice != null) ...[
                const SizedBox(height: 10),
                FailureNotice(english: c.notice!.english, tagalog: c.notice!.tagalog, actions: [noticeAction('Dismiss · Isara', c.dismissNotice)]),
              ],
              if (v.fromCache) ...[
                const SizedBox(height: 10),
                Text(
                  key: const Key('mine-saved-copy'),
                  'Saved copy from ${v.fetchedAt == null ? 'earlier' : '${shortDate(v.fetchedAt!)} ${clockTime(v.fetchedAt!)}'}.',
                  style: const TextStyle(color: WmColors.brownDeep, fontWeight: FontWeight.w600),
                ),
              ],
              if (services != null) ...[const SizedBox(height: 10), MyCashCard(view: c.cash, onOpen: () => _openCash(context))],
              if (v.queued.isNotEmpty || v.queuedPayments.isNotEmpty) ...[
                const SizedBox(height: 16),
                const BilingualText(Bilingual('Not sent yet', 'Hindi pa naipapadala'), style: monoLabel),
                for (final q in v.queued) _QueuedCard(q: q, onFix: () => _fix(q), onThrowAway: () => c.throwAway(q)),
                for (final q in v.queuedPayments)
                  _QueuedPaymentCard(
                    q: q,
                    supplier: v.purchases.where((p) => p.id == q.purchaseId).firstOrNull?.supplier ?? '',
                    onThrowAway: () => c.throwAwayPayment(q),
                  ),
              ],
              if (c.drafts.isNotEmpty) ...[
                const SizedBox(height: 16),
                const BilingualText(Bilingual('Drafts', 'Mga draft'), style: monoLabel),
                for (final d in c.drafts)
                  Card(
                    key: Key('draft-${d.id}'),
                    color: Colors.white,
                    child: ListTile(
                      title: Text(d.supplierName.isEmpty ? 'Purchase on ${d.purchaseDate}' : d.supplierName),
                      subtitle: Text('${d.lines.length} item${d.lines.length == 1 ? '' : 's'} · not sent'),
                      onTap: () => onOpenDraft(d),
                      trailing: IconButton(key: Key('delete-draft-${d.id}'), icon: const Icon(Icons.delete_outline), onPressed: () => c.deleteDraft(d)),
                    ),
                  ),
              ],
              const SizedBox(height: 16),
              const BilingualText(Bilingual('Recorded', 'Naitala na'), style: monoLabel),
              if (!c.loading && v.purchases.isEmpty)
                const Padding(padding: EdgeInsets.symmetric(vertical: 24), child: Text('No purchases in the last 60 days.')),
              for (final p in v.purchases)
                Card(
                  key: Key('purchase-${p.id}'),
                  color: Colors.white,
                  child: InkWell(
                    onTap: () => onOpenPurchase(p),
                    child: Padding(
                      padding: const EdgeInsets.all(14),
                      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                        Row(children: [
                          Expanded(child: Text(p.supplier.isEmpty ? 'No supplier' : p.supplier, style: const TextStyle(fontWeight: FontWeight.w800))),
                          Text(peso(p.receiptTotal), style: const TextStyle(fontWeight: FontWeight.w800)),
                        ]),
                        Text('${p.purchaseDate} · ${[...p.projects, if (p.warehouse) 'Warehouse'].join(', ')}',
                            style: const TextStyle(fontSize: 13, color: WmColors.textMuted)),
                        const SizedBox(height: 6),
                        Wrap(spacing: 6, runSpacing: 6, children: [for (final f in purchaseFlags(p)) _Flag(f)]),
                        if (p.pay.tracked || p.pay.state != 'not_tracked') _PayLine(p: p, unsent: v.unsentFor(p.id), anySent: v.sentFor(p.id), onPay: services == null ? null : () => _pay(context, p)),
                      ]),
                    ),
                  ),
                ),
              const SizedBox(height: 80),
            ]),
          );
        },
      );
}

class _Flag extends StatelessWidget {
  const _Flag(this.flag);
  final (String, Color, Color) flag;

  @override
  Widget build(BuildContext context) => Container(
        padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 3),
        decoration: BoxDecoration(color: flag.$3, borderRadius: BorderRadius.circular(20)),
        child: Text(flag.$1, style: TextStyle(fontSize: 12, fontWeight: FontWeight.w700, color: flag.$2)),
      );
}

/// How a purchase is paid (0102): the state, what is left once payments
/// still on the phone count (Q6), and Record payment.
class _PayLine extends StatelessWidget {
  const _PayLine({required this.p, required this.unsent, this.anySent = false, this.onPay});
  final MyPurchase p;
  final double unsent;
  final bool anySent;
  final VoidCallback? onPay;

  @override
  Widget build(BuildContext context) {
    final left = p.pay.leftAfter(unsent);
    final words = [
      if (p.pay.state == 'overpaid') '${peso(p.pay.unresolved)} over — the owner resolves it'
      else if (p.pay.payable && left > 0) '${peso(left)} left',
      if (unsent > 0) anySent ? '${peso(unsent)} not in this list yet' : '${peso(unsent)} waiting to send',
    ].join(' · ');
    // A phone is narrow: the state and its words on one line, the button under them.
    return Padding(
      key: Key('pay-line-${p.id}'),
      padding: const EdgeInsets.only(top: 8),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Wrap(spacing: 8, runSpacing: 4, crossAxisAlignment: WrapCrossAlignment.center, children: [
          PayPill(p.pay.state),
          if (words.isNotEmpty) Text(words, style: const TextStyle(fontSize: 12.5, color: WmColors.textSecondary)),
        ]),
        if (onPay != null && p.pay.canRecordPayment && !p.voided)
          Align(
            alignment: Alignment.centerRight,
            child: TextButton(key: Key('pay-${p.id}'), onPressed: onPay, child: Text(recordPaymentLabel.english)),
          ),
      ]),
    );
  }
}

class _QueuedPaymentCard extends StatelessWidget {
  const _QueuedPaymentCard({required this.q, required this.supplier, required this.onThrowAway});
  final QueuedCashAction q;
  final String supplier;
  final VoidCallback onThrowAway;

  @override
  Widget build(BuildContext context) {
    final attention = q.state == QueuedState.needsAttention;
    final why = attention ? purFailureCopy(q.failure ?? PurFailure.unexpected) : null;
    return Card(
      key: Key('queued-pay-${q.opId}'),
      color: attention ? WmColors.dangerTint : Colors.white,
      child: Padding(
        padding: const EdgeInsets.all(14),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Row(children: [
            Expanded(child: Text('Payment${supplier.isEmpty ? '' : ' to $supplier'}', style: const TextStyle(fontWeight: FontWeight.w800))),
            Text(peso(q.amount), style: const TextStyle(fontWeight: FontWeight.w800)),
          ]),
          Text(paySourceCopy(q.source).english, style: const TextStyle(fontSize: 13, color: WmColors.textMuted)),
          BilingualText(attention ? attentionLabel : (q.state == QueuedState.sent ? sentLabel : waitingToSendPayLabel),
              style: TextStyle(fontWeight: FontWeight.w700, color: attention ? WmColors.danger : WmColors.brownDeep)),
          if (why != null) ...[
            const SizedBox(height: 6),
            Text(why.english, style: const TextStyle(color: WmColors.danger, fontWeight: FontWeight.w600)),
            Text(why.tagalog, style: const TextStyle(color: WmColors.danger, fontSize: 12.5)),
            TextButton(key: Key('throw-pay-${q.opId}'), onPressed: onThrowAway, child: const Text('Throw away')),
          ],
        ]),
      ),
    );
  }
}

class _QueuedCard extends StatelessWidget {
  const _QueuedCard({required this.q, required this.onFix, required this.onThrowAway});
  final QueuedPurchase q;
  final VoidCallback onFix;
  final VoidCallback onThrowAway;

  @override
  Widget build(BuildContext context) {
    final d = q.draft;
    final attention = q.state == QueuedState.needsAttention;
    final why = attention ? purFailureCopy(q.failure ?? PurFailure.unexpected) : null;
    return Card(
      key: Key('queued-${d.id}'),
      color: attention ? WmColors.dangerTint : Colors.white,
      child: Padding(
        padding: const EdgeInsets.all(14),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Row(children: [
            Expanded(child: Text(d.supplierName.isEmpty ? 'Purchase on ${d.purchaseDate}' : d.supplierName, style: const TextStyle(fontWeight: FontWeight.w800))),
            Text(peso(parseMoney(d.receiptTotal) ?? 0), style: const TextStyle(fontWeight: FontWeight.w800)),
          ]),
          BilingualText(attention ? attentionLabel : (q.state == QueuedState.sent ? sentLabel : waitingLabel),
              style: TextStyle(fontWeight: FontWeight.w700, color: attention ? WmColors.danger : WmColors.brownDeep)),
          if (why != null) ...[
            const SizedBox(height: 6),
            Text(why.english, style: const TextStyle(color: WmColors.danger, fontWeight: FontWeight.w600)),
            Text(why.tagalog, style: const TextStyle(color: WmColors.danger, fontSize: 12.5)),
            Wrap(children: [
              TextButton(key: Key('fix-${d.id}'), onPressed: onFix, child: const Text('Fix and send again')),
              TextButton(key: Key('throw-${d.id}'), onPressed: onThrowAway, child: const Text('Throw away')),
            ]),
          ],
        ]),
      ),
    );
  }
}
