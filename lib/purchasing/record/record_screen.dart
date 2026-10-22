import 'dart:io';

import 'package:flutter/material.dart';

import '../../attendance/domain/work_date.dart';
import '../../attendance/ui/attendance_copy.dart' show Bilingual;
import '../../requests/domain/quantity.dart';
import '../../ui/failure_notice.dart';
import '../../ui/theme.dart';
import '../domain/pur_models.dart';
import '../domain/purchase_draft.dart';
import '../purchasing_services.dart';
import '../ui/purchasing_copy.dart';
import 'record_controller.dart';

/// Opens Record purchase for [lines] (picked from the shopping list), or for
/// a saved [draft], or blank (an unplanned purchase, Q11). True once queued.
Future<bool> openRecord(BuildContext context, PurchasingServices services, {List<DraftPurchaseLine>? lines, PurchaseDraft? draft}) async {
  final api = services.api;
  final d = draft ??
      api.newDraft(
        lines: lines != null && lines.isNotEmpty ? lines : [DraftPurchaseLine(key: api.newLineKey(), quantity: '1', category: 'Materials')],
      );
  final queued = await Navigator.of(context).push<bool>(
    MaterialPageRoute(builder: (_) => RecordScreen(controller: RecordController(api: api, draft: d)..load(), services: services)),
  );
  return queued == true;
}

/// Record a purchase (Q7–Q11). Works with no signal: it is saved on the phone
/// as "Waiting to send" and recorded once, when there is signal.
class RecordScreen extends StatelessWidget {
  const RecordScreen({super.key, required this.controller, required this.services});

  final RecordController controller;
  final PurchasingServices services;

  Future<void> _send(BuildContext context) async {
    if (await controller.send() && context.mounted) Navigator.of(context).pop(true);
  }

  Future<void> _discard(BuildContext context) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (_) => AlertDialog(
        title: const Text('Throw this purchase away?'),
        content: const Text('Nothing was sent. Its photos are deleted from the phone.'),
        actions: [
          TextButton(onPressed: () => Navigator.of(context).pop(false), child: const Text('Keep')),
          TextButton(onPressed: () => Navigator.of(context).pop(true), child: const Text('Throw away')),
        ],
      ),
    );
    if (ok == true) {
      await controller.discard();
      if (context.mounted) Navigator.of(context).pop(false);
    }
  }

  @override
  Widget build(BuildContext context) => ListenableBuilder(
        listenable: controller,
        builder: (context, _) {
          final c = controller;
          final d = c.draft;
          final problems = c.problems;
          final general = [for (final p in problems) if (p.line == null && p.charge == null) p];
          return Scaffold(
            appBar: AppBar(
              title: const BilingualText(recordLabel, style: TextStyle(fontWeight: FontWeight.w800, fontSize: 18)),
              actions: [IconButton(key: const Key('record-discard'), tooltip: 'Throw away', onPressed: () => _discard(context), icon: const Icon(Icons.delete_outline))],
            ),
            body: SafeArea(
              child: ListView(key: const Key('record-form'), padding: const EdgeInsets.all(16), children: [
                const Text('Saved on this phone as you type. It is sent when there is signal.',
                    style: TextStyle(fontSize: 13, color: WmColors.textMuted)),
                if (c.notice != null) ...[
                  const SizedBox(height: 10),
                  FailureNotice(english: c.notice!.english, tagalog: c.notice!.tagalog),
                ],
                const SizedBox(height: 14),
                _heading('1', 'The purchase'),
                _DateField(value: d.purchaseDate, onChanged: c.setDate),
                const SizedBox(height: 10),
                _SupplierField(controller: c),
                const SizedBox(height: 10),
                DropdownButtonFormField<String>(
                  key: const Key('payment'),
                  initialValue: paymentMethods.contains(d.paymentMethod) ? d.paymentMethod : 'Cash',
                  isExpanded: true,
                  decoration: const InputDecoration(labelText: 'Paid with'),
                  items: [
                    for (final m in paymentMethods)
                      DropdownMenuItem(value: m, child: Text(m.isEmpty ? 'Not yet paid / not known' : m, overflow: TextOverflow.ellipsis)),
                  ],
                  onChanged: (m) => c.setPayment(m ?? ''),
                ),
                const SizedBox(height: 18),
                _heading('2', 'What was bought'),
                for (var i = 0; i < d.lines.length; i++)
                  _LineCard(
                    key: ValueKey(d.lines[i].key),
                    index: i,
                    line: d.lines[i],
                    controller: c,
                    problems: [for (final p in problems) if (p.line == i + 1) p],
                  ),
                TextButton.icon(
                  key: const Key('add-line'),
                  onPressed: c.addLine,
                  icon: const Icon(Icons.add),
                  label: const Text('Add an item with no request'),
                ),
                const SizedBox(height: 18),
                _heading('3', 'Delivery fees and discounts'),
                const Text('Optional. Shared across the items by amount unless you adjust it.',
                    style: TextStyle(fontSize: 13, color: WmColors.textMuted)),
                for (var i = 0; i < d.charges.length; i++)
                  _ChargeCard(
                    key: ValueKey('charge-$i-${d.charges[i].kind}'),
                    index: i,
                    controller: c,
                    problems: [for (final p in problems) if (p.charge == i + 1) p],
                  ),
                Wrap(spacing: 8, children: [
                  TextButton.icon(
                      key: const Key('add-fee'), onPressed: () => c.addCharge('delivery_fee'), icon: const Icon(Icons.add), label: const Text('Delivery fee')),
                  TextButton.icon(
                      key: const Key('add-discount'), onPressed: () => c.addCharge('discount'), icon: const Icon(Icons.add), label: const Text('Discount')),
                ]),
                const SizedBox(height: 18),
                _heading('4', 'Receipt'),
                _ReceiptPhotos(controller: c, services: services),
                const SizedBox(height: 18),
                TextFormField(
                  key: const Key('notes'),
                  initialValue: d.notes,
                  maxLines: 2,
                  decoration: const InputDecoration(labelText: 'Notes (optional)'),
                  onChanged: c.setNotes,
                ),
                const SizedBox(height: 18),
                _heading('5', 'Receipt total'),
                TextFormField(
                  key: const Key('receipt-total'),
                  initialValue: d.receiptTotal,
                  keyboardType: const TextInputType.numberWithOptions(decimal: true),
                  decoration: const InputDecoration(labelText: 'Total on the receipt', prefixText: '₱ '),
                  onChanged: c.setTotal,
                ),
                const SizedBox(height: 6),
                Text(
                  key: const Key('computed-total'),
                  'Items + fees − discounts: ${peso(d.computedTotal)}',
                  style: TextStyle(
                    fontWeight: FontWeight.w700,
                    color: parseMoney(d.receiptTotal) != null && round2(parseMoney(d.receiptTotal)!) == d.computedTotal ? WmColors.green : WmColors.textSecondary,
                  ),
                ),
                for (final p in general) ...[const SizedBox(height: 8), _ProblemText(p)],
                const SizedBox(height: 20),
                bilingualButton(recordLabel, c.sending ? null : () => _send(context), filled: true, key: const Key('record-send')),
                const SizedBox(height: 24),
              ]),
            ),
          );
        },
      );

  Widget _heading(String n, String text) => Padding(
        padding: const EdgeInsets.only(bottom: 8),
        child: Row(children: [
          CircleAvatar(radius: 12, backgroundColor: WmColors.greenTint, child: Text(n, style: const TextStyle(fontSize: 12, color: WmColors.green))),
          const SizedBox(width: 8),
          Expanded(child: Text(text, style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 16))),
        ]),
      );
}

class _ProblemText extends StatelessWidget {
  const _ProblemText(this.problem);
  final PurchaseProblem problem;

  @override
  Widget build(BuildContext context) {
    final b = problemCopy(problem.kind);
    return Column(key: Key('problem-${problem.kind.name}-${problem.line ?? problem.charge ?? 0}'), crossAxisAlignment: CrossAxisAlignment.start, children: [
      Text(b.english, style: const TextStyle(color: WmColors.danger, fontWeight: FontWeight.w700, fontSize: 13)),
      Text(b.tagalog, style: const TextStyle(color: WmColors.danger, fontSize: 12)),
    ]);
  }
}

class _DateField extends StatelessWidget {
  const _DateField({required this.value, required this.onChanged});
  final String value;
  final ValueChanged<String> onChanged;

  @override
  Widget build(BuildContext context) => InkWell(
        key: const Key('purchase-date'),
        onTap: () async {
          final today = manilaDate(DateTime.now());
          final current = DateTime.tryParse(value) ?? today;
          final picked = await showDatePicker(
            context: context,
            initialDate: current.isAfter(today) ? today : current,
            firstDate: today.subtract(const Duration(days: 365)),
            lastDate: today,
          );
          if (picked != null) onChanged(isoDate(picked));
        },
        child: InputDecorator(
          decoration: const InputDecoration(labelText: 'Date bought (the date on the receipt)'),
          child: Text(value, style: const TextStyle(fontSize: 16)),
        ),
      );
}

class _SupplierField extends StatelessWidget {
  const _SupplierField({required this.controller});
  final RecordController controller;

  @override
  Widget build(BuildContext context) {
    final c = controller;
    final d = c.draft;
    final list = c.suppliers;
    final typed = d.supplierId == null;
    return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      DropdownButtonFormField<String?>(
        key: const Key('supplier'),
        initialValue: list.any((s) => s.id == d.supplierId) ? d.supplierId : null,
        isExpanded: true,
        decoration: const InputDecoration(labelText: 'Supplier'),
        items: [
          const DropdownMenuItem<String?>(value: null, child: Text('Not on the list — type the name', overflow: TextOverflow.ellipsis)),
          for (final s in list) DropdownMenuItem<String?>(value: s.id, child: Text(s.label, overflow: TextOverflow.ellipsis)),
        ],
        onChanged: (id) => c.setSupplier(id == null ? null : list.firstWhere((s) => s.id == id)),
      ),
      if (typed) ...[
        const SizedBox(height: 8),
        TextFormField(
          key: const Key('supplier-name'),
          initialValue: d.supplierName,
          decoration: const InputDecoration(labelText: 'Supplier name'),
          onChanged: c.setSupplierName,
        ),
      ],
    ]);
  }
}

class _LineCard extends StatelessWidget {
  const _LineCard({super.key, required this.index, required this.line, required this.controller, required this.problems});
  final int index;
  final DraftPurchaseLine line;
  final RecordController controller;
  final List<PurchaseProblem> problems;

  void _update(DraftPurchaseLine l) => controller.updateLine(index, l);

  @override
  Widget build(BuildContext context) {
    final l = line;
    final c = controller;
    final n = index + 1;
    final places = c.places;
    final placeIndex = l.destination == 'warehouse' ? places.indexWhere((p) => p.warehouse) : places.indexWhere((p) => p.folderId == l.folderId);
    return Card(
      key: Key('line-$n'),
      color: Colors.white,
      margin: const EdgeInsets.only(bottom: 12),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16), side: const BorderSide(color: WmColors.border)),
      child: Padding(
        padding: const EdgeInsets.all(14),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Row(children: [
            Expanded(child: Text('Item $n', style: monoLabel)),
            if (c.draft.lines.length > 1)
              IconButton(key: Key('remove-line-$n'), onPressed: () => c.removeLine(index), icon: const Icon(Icons.close), tooltip: 'Remove'),
          ]),
          if (l.linked) ...[
            Text('For the request: ${l.requestName} · ${l.folderLabel}', style: const TextStyle(fontWeight: FontWeight.w700)),
            Text('${stillToBuyLabel.english} on the picked part: ${qtyUnit(l.pickedStill, l.requestUnit)}',
                style: const TextStyle(fontSize: 13, color: WmColors.textMuted)),
            const SizedBox(height: 8),
          ],
          TextFormField(
            key: Key('item-$n'),
            initialValue: l.itemName,
            decoration: const InputDecoration(labelText: 'Item'),
            onChanged: (v) => _update(l.copyWith(itemName: v)),
          ),
          const SizedBox(height: 8),
          Row(children: [
            Expanded(
              child: TextFormField(
                key: Key('qty-$n'),
                initialValue: l.quantity,
                keyboardType: const TextInputType.numberWithOptions(decimal: true),
                decoration: const InputDecoration(labelText: 'Quantity'),
                onChanged: (v) => _update(l.copyWith(quantity: v)),
              ),
            ),
            const SizedBox(width: 8),
            Expanded(
              child: TextFormField(
                key: Key('unit-$n'),
                initialValue: l.unit,
                decoration: const InputDecoration(labelText: 'Unit'),
                onChanged: (v) => _update(l.copyWith(unit: v)),
              ),
            ),
          ]),
          const SizedBox(height: 8),
          Row(children: [
            Expanded(
              child: TextFormField(
                key: Key('amount-$n'),
                initialValue: l.amount,
                keyboardType: const TextInputType.numberWithOptions(decimal: true),
                decoration: const InputDecoration(labelText: 'Amount paid', prefixText: '₱ '),
                onChanged: (v) => _update(l.copyWith(amount: v)),
              ),
            ),
            const SizedBox(width: 8),
            Expanded(
              child: TextFormField(
                key: Key('category-$n'),
                initialValue: l.category,
                decoration: const InputDecoration(labelText: 'Category'),
                onChanged: (v) => _update(l.copyWith(category: v)),
              ),
            ),
          ]),
          const SizedBox(height: 8),
          if (!l.linked) ...[
            DropdownButtonFormField<int>(
              key: Key('place-$n'),
              initialValue: placeIndex < 0 ? null : placeIndex,
              isExpanded: true,
              decoration: const InputDecoration(labelText: 'For (project, job or warehouse)'),
              items: [for (var i = 0; i < places.length; i++) DropdownMenuItem(value: i, child: Text(places[i].label, overflow: TextOverflow.ellipsis))],
              onChanged: (i) => i == null ? null : c.setPlace(index, places[i]),
            ),
            const SizedBox(height: 8),
            TextFormField(
              key: Key('unplanned-$n'),
              initialValue: l.unplannedReason,
              decoration: const InputDecoration(labelText: 'No request: why was it bought?'),
              onChanged: (v) => _update(l.copyWith(unplannedReason: v)),
            ),
          ] else ...[
            const BilingualText(Bilingual('Is this the same item?', 'Ito ba ang parehong item?')),
            const SizedBox(height: 6),
            SegmentedButton<LineMatch>(
              key: Key('match-$n'),
              segments: const [
                ButtonSegment(value: LineMatch.same, label: Text('Same')),
                ButtonSegment(value: LineMatch.otherWords, label: Text('Other words')),
                ButtonSegment(value: LineMatch.substitute, label: Text('Substitute')),
              ],
              selected: {l.match},
              onSelectionChanged: (s) => _update(l.copyWith(match: s.first)),
            ),
            if (l.match == LineMatch.substitute) ...[
              const SizedBox(height: 8),
              TextFormField(
                key: Key('substitute-$n'),
                initialValue: l.substituteReason,
                decoration: const InputDecoration(labelText: 'Why a substitute? (the office checks it)'),
                onChanged: (v) => _update(l.copyWith(substituteReason: v)),
              ),
            ],
            if (l.differentUnit && l.match != LineMatch.substitute) ...[
              const SizedBox(height: 8),
              Text('A different unit from the request (${l.requestUnit}): it counts after the office checks it.',
                  style: const TextStyle(fontSize: 13, color: WmColors.brownDeep)),
              TextFormField(
                key: Key('unit-note-$n'),
                initialValue: l.unitNote,
                decoration: const InputDecoration(labelText: 'How much does it cover? (e.g. 1 box = 12 pc)'),
                onChanged: (v) => _update(l.copyWith(unitNote: v)),
              ),
            ],
            if (l.extraQuantity > 0) ...[
              const SizedBox(height: 8),
              Text('${formatQuantity(l.extraQuantity)} ${l.unit} more than still needed: an extra.',
                  style: const TextStyle(fontSize: 13, color: WmColors.brownDeep)),
              TextFormField(
                key: Key('extra-$n'),
                initialValue: l.extraReason,
                decoration: const InputDecoration(labelText: 'Why the extra?'),
                onChanged: (v) => _update(l.copyWith(extraReason: v)),
              ),
              const SizedBox(height: 6),
              SegmentedButton<String>(
                key: Key('extra-location-$n'),
                emptySelectionAllowed: true,
                segments: const [
                  ButtonSegment(value: 'project', label: Text('Stays on the project')),
                  ButtonSegment(value: 'warehouse', label: Text('To the warehouse')),
                ],
                selected: {?l.extraLocation},
                onSelectionChanged: (s) => _update(l.copyWith(extraLocation: s.isEmpty ? null : s.first)),
              ),
            ],
          ],
          for (final p in problems) ...[const SizedBox(height: 6), _ProblemText(p)],
        ]),
      ),
    );
  }
}

class _ChargeCard extends StatelessWidget {
  const _ChargeCard({super.key, required this.index, required this.controller, required this.problems});
  final int index;
  final RecordController controller;
  final List<PurchaseProblem> problems;

  @override
  Widget build(BuildContext context) {
    final c = controller;
    final ch = c.draft.charges[index];
    final n = index + 1;
    final shares = ch.shares;
    return Card(
      key: Key('charge-$n'),
      color: Colors.white,
      margin: const EdgeInsets.only(top: 10),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16), side: const BorderSide(color: WmColors.border)),
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Row(children: [
            Expanded(
              child: TextFormField(
                key: Key('charge-amount-$n'),
                initialValue: ch.amount,
                keyboardType: const TextInputType.numberWithOptions(decimal: true),
                decoration: InputDecoration(labelText: ch.isFee ? 'Delivery fee' : 'Discount', prefixText: '₱ '),
                onChanged: (v) => c.updateCharge(index, ch.copyWith(amount: v)),
              ),
            ),
            IconButton(key: Key('remove-charge-$n'), onPressed: () => c.removeCharge(index), icon: const Icon(Icons.close)),
          ]),
          SwitchListTile(
            key: Key('adjust-$n'),
            contentPadding: EdgeInsets.zero,
            title: const Text('Adjust the split'),
            value: shares != null,
            onChanged: (on) => c.adjustSplit(index, on),
          ),
          if (shares != null)
            for (var i = 0; i < shares.length && i < c.draft.lines.length; i++)
              TextFormField(
                key: Key('share-$n-${i + 1}'),
                initialValue: shares[i],
                keyboardType: const TextInputType.numberWithOptions(decimal: true),
                decoration: InputDecoration(labelText: 'Item ${i + 1}: ${c.draft.lines[i].itemName}', prefixText: '₱ '),
                onChanged: (v) => c.updateCharge(index, ch.copyWith(shares: [...shares]..[i] = v)),
              ),
          for (final p in problems) ...[const SizedBox(height: 6), _ProblemText(p)],
        ]),
      ),
    );
  }
}

class _ReceiptPhotos extends StatelessWidget {
  const _ReceiptPhotos({required this.controller, required this.services});
  final RecordController controller;
  final PurchasingServices services;

  Future<void> _add(BuildContext context, String slot, PickReceipt pick) async {
    final path = await pick(context);
    if (path != null) await controller.addPhoto(slot, path);
  }

  @override
  Widget build(BuildContext context) {
    final c = controller;
    final d = c.draft;
    return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      if (!d.noReceipt)
        for (final slot in receiptSlots)
          Padding(
            padding: const EdgeInsets.only(bottom: 8),
            child: Row(children: [
              Expanded(child: Text(receiptSlotLabels[slot]!, style: const TextStyle(fontWeight: FontWeight.w600))),
              if (d.photos[slot] case final path?) ...[
                ClipRRect(
                  borderRadius: BorderRadius.circular(8),
                  child: Image.file(File(path), key: Key('photo-$slot'), width: 52, height: 52, fit: BoxFit.cover,
                      errorBuilder: (_, _, _) => const Icon(Icons.receipt_long, size: 40)),
                ),
                IconButton(key: Key('remove-photo-$slot'), onPressed: () => c.removePhoto(slot), icon: const Icon(Icons.close)),
              ] else ...[
                IconButton(
                    key: Key('camera-$slot'), tooltip: 'Camera', onPressed: () => _add(context, slot, services.takePhoto), icon: const Icon(Icons.photo_camera_outlined)),
                IconButton(
                    key: Key('gallery-$slot'), tooltip: 'Gallery', onPressed: () => _add(context, slot, services.pickPhoto), icon: const Icon(Icons.photo_library_outlined)),
              ],
            ]),
          ),
      CheckboxListTile(
        key: const Key('no-receipt'),
        contentPadding: EdgeInsets.zero,
        value: d.noReceipt,
        onChanged: (v) => c.setNoReceipt(v == true),
        title: const BilingualText(noReceiptLabel),
      ),
      if (d.noReceipt)
        TextFormField(
          key: const Key('no-receipt-reason'),
          initialValue: d.noReceiptReason,
          decoration: const InputDecoration(labelText: 'Why is there no receipt?'),
          onChanged: c.setNoReceiptReason,
        ),
    ]);
  }
}
