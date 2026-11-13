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
            // Room under the last card for the shell's floating Record purchase button.
            child: ListView(padding: const EdgeInsets.fromLTRB(20, 16, 20, 110), children: [
              const Text('My purchases', style: TextStyle(fontWeight: FontWeight.w800, fontSize: 26)),
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
                const _GroupLabel(Bilingual('Not sent yet', 'Hindi pa naipapadala')),
                for (final q in v.queued) _QueuedCard(q: q, onFix: () => _fix(q), onThrowAway: () => c.throwAway(q)),
                for (final q in v.queuedPayments)
                  _QueuedPaymentCard(
                    q: q,
                    supplier: v.purchases.where((p) => p.id == q.purchaseId).firstOrNull?.supplier ?? '',
                    onThrowAway: () => c.throwAwayPayment(q),
                  ),
              ],
              if (c.drafts.isNotEmpty) ...[
                const _GroupLabel(Bilingual('Drafts', 'Mga draft')),
                for (final d in c.drafts)
                  _RowCard(
                    key: Key('draft-${d.id}'),
                    title: d.supplierName.isEmpty ? 'Purchase on ${d.purchaseDate}' : d.supplierName,
                    sub: '${d.lines.length} item${d.lines.length == 1 ? '' : 's'} · not sent',
                    onTap: () => onOpenDraft(d),
                    action: IconButton(key: Key('delete-draft-${d.id}'), icon: const Icon(Icons.delete_outline), onPressed: () => c.deleteDraft(d)),
                  ),
              ],
              const _GroupLabel(Bilingual('Recorded', 'Naitala na')),
              if (!c.loading && v.purchases.isEmpty)
                const Padding(padding: EdgeInsets.symmetric(vertical: 24), child: Text('No purchases in the last 60 days.')),
              for (final p in v.purchases)
                _RowCard(
                  key: Key('purchase-${p.id}'),
                  title: p.supplier.isEmpty ? 'No supplier' : p.supplier,
                  sub: '${p.purchaseDate} · ${[...p.projects, if (p.warehouse) 'Warehouse'].join(', ')}',
                  value: peso(p.receiptTotal),
                  onTap: () => onOpenPurchase(p),
                  below: [
                    const SizedBox(height: 8),
                    Wrap(spacing: 6, runSpacing: 6, children: [for (final f in purchaseFlags(p)) _Flag(f)]),
                    // F1 (0.8.1): a voided purchase with nothing paid already says
                    // "Voided"; only "Voided — paid, to recover" adds anything.
                    if ((p.pay.tracked || p.pay.state != 'not_tracked') && p.pay.state != 'void')
                      _PayLine(p: p, unsent: v.unsentFor(p.id), anySent: v.sentFor(p.id), onPay: services == null ? null : () => _pay(context, p)),
                  ],
                ),
            ]),
          );
        },
      );
}

/// A group's label: the English in capitals, then ` · Tagalog` (as on the shopping list).
class _GroupLabel extends StatelessWidget {
  const _GroupLabel(this.title);
  final Bilingual title;

  @override
  Widget build(BuildContext context) => Padding(
        padding: const EdgeInsets.only(top: 20),
        child: Wrap(crossAxisAlignment: WrapCrossAlignment.center, children: [
          Text(title.english.toUpperCase(), style: monoLabel),
          Text(' · ${title.tagalog}', style: monoLabel.copyWith(fontWeight: FontWeight.w400, letterSpacing: 0)),
        ]),
      );
}

/// The mockup's row card, used by all three groups: a title and a muted line on
/// the left, the amount (mono, bold) on the right, then an optional action and a
/// chevron when the card opens something; [below] holds flags, the pay line or
/// the reason and its buttons. The whole card is the tap target when [onTap] is
/// given; buttons inside it win the tap, so they never also open the card.
class _RowCard extends StatelessWidget {
  const _RowCard({super.key, required this.title, this.sub, this.value, this.onTap, this.action, this.tint, this.border, this.below = const []});
  final String title;
  final String? sub;
  final String? value;
  final VoidCallback? onTap;
  final Widget? action;
  final Color? tint;
  final Color? border;
  final List<Widget> below;

  @override
  Widget build(BuildContext context) {
    final body = Padding(
      padding: const EdgeInsets.all(14),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Row(crossAxisAlignment: CrossAxisAlignment.center, children: [
          Expanded(
            flex: 3,
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text(title, style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 16)),
              if (sub != null) Padding(padding: const EdgeInsets.only(top: 2), child: Text(sub!, style: const TextStyle(fontSize: 13, color: WmColors.textMuted))),
            ]),
          ),
          if (value != null) ...[
            const SizedBox(width: 10),
            // The name wraps; the amount keeps its place (it shrinks only when it truly cannot fit).
            Flexible(
              flex: 2,
              child: FittedBox(
                fit: BoxFit.scaleDown,
                alignment: Alignment.centerRight,
                child: Text(value!, style: const TextStyle(fontFamily: 'IBM Plex Mono', fontWeight: FontWeight.w700, fontSize: 15)),
              ),
            ),
          ],
          if (action != null) ...[const SizedBox(width: 4), action!],
          if (onTap != null) ...[const SizedBox(width: 4), const Icon(Icons.chevron_right, size: 22, color: WmColors.textMuted)],
        ]),
        ...below,
      ]),
    );
    return Container(
      margin: const EdgeInsets.only(top: 8),
      decoration: BoxDecoration(color: tint ?? Colors.white, borderRadius: BorderRadius.circular(16), border: Border.all(color: border ?? WmColors.border)),
      child: Material(
        type: MaterialType.transparency,
        child: onTap == null ? body : InkWell(borderRadius: BorderRadius.circular(16), onTap: onTap, child: body),
      ),
    );
  }
}

/// A status as a pill, its Tagalog beside it.
class _StatusPill extends StatelessWidget {
  const _StatusPill(this.label, {required this.color, required this.tint});
  final Bilingual label;
  final Color color;
  final Color tint;

  @override
  Widget build(BuildContext context) => Padding(
        padding: const EdgeInsets.only(top: 8),
        child: Wrap(spacing: 8, runSpacing: 4, crossAxisAlignment: WrapCrossAlignment.center, children: [
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
            decoration: BoxDecoration(color: tint, borderRadius: BorderRadius.circular(999)),
            child: Text(label.english, style: TextStyle(fontSize: 12.5, fontWeight: FontWeight.w800, color: color)),
          ),
          Text(label.tagalog, style: const TextStyle(fontSize: 11.5, color: WmColors.textMuted)),
        ]),
      );
}

class _Flag extends StatelessWidget {
  const _Flag(this.flag);
  final (String, Color, Color) flag;

  @override
  Widget build(BuildContext context) => Container(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
        decoration: BoxDecoration(color: flag.$3, borderRadius: BorderRadius.circular(999)),
        child: Text(flag.$1, style: TextStyle(fontSize: 12.5, fontWeight: FontWeight.w800, color: flag.$2)),
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
    return _RowCard(
      key: Key('queued-pay-${q.opId}'),
      title: 'Payment${supplier.isEmpty ? '' : ' to $supplier'}',
      sub: paySourceCopy(q.source).english,
      value: peso(q.amount),
      tint: attention ? WmColors.dangerTint : null,
      border: attention ? WmColors.dangerBorder : null,
      below: [
        _StatusPill(attention ? attentionLabel : (q.state == QueuedState.sent ? sentLabel : waitingToSendPayLabel),
            color: attention ? WmColors.danger : WmColors.brownDeep, tint: attention ? WmColors.dangerTint : WmColors.brownTint),
        if (why != null) ...[
          const SizedBox(height: 6),
          Text(why.english, style: const TextStyle(color: WmColors.danger, fontWeight: FontWeight.w600)),
          Text(why.tagalog, style: const TextStyle(color: WmColors.danger, fontSize: 12.5)),
          TextButton(key: Key('throw-pay-${q.opId}'), onPressed: onThrowAway, child: const Text('Throw away')),
        ],
      ],
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
    return _RowCard(
      key: Key('queued-${d.id}'),
      title: d.supplierName.isEmpty ? 'Purchase on ${d.purchaseDate}' : d.supplierName,
      value: peso(parseMoney(d.receiptTotal) ?? 0),
      tint: attention ? WmColors.dangerTint : null,
      border: attention ? WmColors.dangerBorder : null,
      below: [
        _StatusPill(attention ? attentionLabel : (q.state == QueuedState.sent ? sentLabel : waitingLabel),
            color: attention ? WmColors.danger : WmColors.brownDeep, tint: attention ? WmColors.dangerTint : WmColors.brownTint),
        if (why != null) ...[
          const SizedBox(height: 6),
          Text(why.english, style: const TextStyle(color: WmColors.danger, fontWeight: FontWeight.w600)),
          Text(why.tagalog, style: const TextStyle(color: WmColors.danger, fontSize: 12.5)),
          Wrap(children: [
            TextButton(key: Key('fix-${d.id}'), onPressed: onFix, child: const Text('Fix and send again')),
            TextButton(key: Key('throw-${d.id}'), onPressed: onThrowAway, child: const Text('Throw away')),
          ]),
        ],
      ],
    );
  }
}
