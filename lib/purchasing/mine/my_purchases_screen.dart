import 'package:flutter/material.dart';

import '../../attendance/ui/attendance_copy.dart' show Bilingual;
import '../../attendance/ui/formats.dart';
import '../../ui/failure_notice.dart';
import '../../ui/theme.dart';
import '../data/purchasing_api.dart';
import '../domain/pur_failure.dart';
import '../domain/pur_models.dart';
import '../domain/purchase_draft.dart';
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
  const MyPurchasesScreen({super.key, required this.controller, required this.onOpenDraft, required this.onOpenPurchase});

  final MyPurchasesController controller;

  /// Continue a draft (or a refused purchase sent back to editing).
  final void Function(PurchaseDraft draft) onOpenDraft;
  final void Function(MyPurchase purchase) onOpenPurchase;

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
              if (v.queued.isNotEmpty) ...[
                const SizedBox(height: 16),
                const BilingualText(Bilingual('Not sent yet', 'Hindi pa naipapadala'), style: monoLabel),
                for (final q in v.queued) _QueuedCard(q: q, onFix: () => _fix(q), onThrowAway: () => c.throwAway(q)),
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
          BilingualText(attention ? attentionLabel : waitingLabel,
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
