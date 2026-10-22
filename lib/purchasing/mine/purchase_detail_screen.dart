import 'package:flutter/material.dart';

import '../../attendance/ui/attendance_copy.dart' show Bilingual;
import '../../requests/domain/quantity.dart';
import '../../ui/failure_notice.dart';
import '../../ui/theme.dart';
import '../domain/pur_failure.dart';
import '../domain/pur_models.dart';
import '../purchasing_services.dart';
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
