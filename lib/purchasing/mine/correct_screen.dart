import 'package:flutter/material.dart';

import '../../attendance/domain/work_date.dart';
import '../../attendance/ui/attendance_copy.dart' show Bilingual;
import '../../ui/failure_notice.dart';
import '../../ui/theme.dart';
import '../data/purchasing_api.dart';
import '../domain/correction.dart';
import '../domain/pur_failure.dart';
import '../domain/pur_models.dart';
import '../purchasing_services.dart';
import '../ui/purchasing_copy.dart';

Bilingual correctionProblemCopy(CorrectionProblem k) => switch (k) {
      CorrectionProblem.badDate => const Bilingual('Pick the date you bought it.', 'Piliin ang petsa ng pagbili.'),
      CorrectionProblem.badQuantity => const Bilingual('Enter a quantity above 0.', 'Ilagay ang dami na higit sa 0.'),
      CorrectionProblem.badAmount => const Bilingual('Enter the amount paid.', 'Ilagay ang halagang ibinayad.'),
      CorrectionProblem.badTotal => const Bilingual('Enter the total printed on the receipt.', 'Ilagay ang total na nakasulat sa resibo.'),
      CorrectionProblem.totalMismatch => const Bilingual('Items + fees − discounts do not match the receipt total.',
          'Hindi tugma ang items + bayad − diskwento sa total ng resibo.'),
      CorrectionProblem.reasonRequired => const Bilingual('Say why you are changing it.', 'Sabihin kung bakit mo ito binabago.'),
      CorrectionProblem.nothingChanged => const Bilingual('Nothing was changed.', 'Walang binago.'),
    };

/// Correct my own recorded purchase (Q13): date, supplier, quantities,
/// amounts, the receipt total and new receipt photos. Online only. When
/// only the owner may make the change (a completed project), it is offered
/// to the owner instead. Pops a sentence for the snack bar, or nothing.
class CorrectScreen extends StatefulWidget {
  const CorrectScreen({super.key, required this.purchase, required this.services});
  final PurchaseDetail purchase;
  final PurchasingServices services;

  @override
  State<CorrectScreen> createState() => _CorrectScreenState();
}

class _CorrectScreenState extends State<CorrectScreen> {
  late CorrectionDraft _c = CorrectionDraft.of(widget.purchase);
  late final String _opCorrect = widget.services.api.newLineKey();
  late final String _opOwner = widget.services.api.newLineKey();
  bool _tried = false;
  bool _busy = false;
  Bilingual? _notice;

  PurchaseDetail get _p => widget.purchase;
  PurchasingApi get _api => widget.services.api;

  void _set(CorrectionDraft c) => setState(() => _c = c);

  Future<void> _photo(String slot, PickReceipt pick) async {
    final path = await pick(context);
    if (path == null) return;
    final kept = await _api.keepPhoto('correction-${_p.id}', path);
    _set(_c.copyWith(photos: {..._c.photos, slot: kept}));
  }

  Future<void> _save() async {
    setState(() => _tried = true);
    if (correctionProblems(_p, _c).isNotEmpty) return;
    setState(() {
      _busy = true;
      _notice = null;
    });
    try {
      final r = await _api.correct(_p, correctionBody(_p, _c), _c.reason.trim(), opId: _opCorrect, newPhotos: _c.photos);
      if (!mounted) return;
      if (r.outcome == CorrectionOutcome.saved) {
        Navigator.of(context).pop('Corrected. · Naitama na.');
        return;
      }
      final send = await showDialog<bool>(
        context: context,
        builder: (context) => AlertDialog(
          title: const Text('Send to the owner?'),
          content: Text('${purFailureCopy(PurFailure.completedProject).english}\n\nThe owner sees exactly this change and approves or rejects it.'),
          actions: [
            TextButton(onPressed: () => Navigator.of(context).pop(false), child: const Text('Cancel')),
            TextButton(key: const Key('send-owner'), onPressed: () => Navigator.of(context).pop(true), child: const Text('Send to the owner')),
          ],
        ),
      );
      if (send != true || !mounted) return;
      await _api.sendToOwner(_p, r.body, _c.reason.trim(), opId: _opOwner);
      if (mounted) Navigator.of(context).pop('Sent to the owner. · Naipadala sa may-ari.');
    } catch (e) {
      if (mounted) setState(() => _notice = purFailureCopy(PurFailure.of(e)));
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final problems = _tried ? correctionProblems(_p, _c) : const <(CorrectionProblem, int?)>[];
    Widget problem((CorrectionProblem, int?) x) {
      final b = correctionProblemCopy(x.$1);
      return Padding(
        padding: const EdgeInsets.only(top: 4),
        child: Text(key: Key('cproblem-${x.$1.name}-${x.$2 ?? 0}'), '${b.english}\n${b.tagalog}', style: const TextStyle(color: WmColors.danger)),
      );
    }

    return Scaffold(
      appBar: AppBar(title: const BilingualText(Bilingual('Correct purchase', 'Itama ang purchase'), style: TextStyle(fontWeight: FontWeight.w800))),
      body: SafeArea(
        child: ListView(key: const Key('correct-form'), padding: const EdgeInsets.all(16), children: [
          if (_notice != null) ...[FailureNotice(english: _notice!.english, tagalog: _notice!.tagalog), const SizedBox(height: 10)],
          InkWell(
            key: const Key('correct-date'),
            onTap: () async {
              final today = manilaDate(DateTime.now());
              final picked = await showDatePicker(
                context: context,
                initialDate: DateTime.tryParse(_c.purchaseDate) ?? today,
                firstDate: today.subtract(const Duration(days: 366)),
                lastDate: today,
              );
              if (picked != null) _set(_c.copyWith(purchaseDate: isoDate(picked)));
            },
            child: InputDecorator(decoration: const InputDecoration(labelText: 'Date bought'), child: Text(_c.purchaseDate)),
          ),
          const SizedBox(height: 10),
          TextFormField(
            key: const Key('correct-supplier'),
            initialValue: _c.supplier,
            decoration: const InputDecoration(labelText: 'Supplier'),
            onChanged: (v) => _set(_c.copyWith(supplier: v, supplierChanged: v.trim() != _p.supplier.trim())),
          ),
          const SizedBox(height: 14),
          for (var i = 0; i < _p.lines.length; i++) ...[
            Text('${_p.lines[i].itemName} · ${_p.lines[i].destination == 'warehouse' ? 'Warehouse' : _p.lines[i].folderName}',
                style: const TextStyle(fontWeight: FontWeight.w700)),
            Row(children: [
              Expanded(
                child: TextFormField(
                  key: Key('correct-qty-${i + 1}'),
                  initialValue: _c.quantities[i],
                  keyboardType: const TextInputType.numberWithOptions(decimal: true),
                  decoration: InputDecoration(labelText: 'Quantity', suffixText: _p.lines[i].unit),
                  onChanged: (v) => _set(_c.copyWith(quantities: [..._c.quantities]..[i] = v)),
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: TextFormField(
                  key: Key('correct-amount-${i + 1}'),
                  initialValue: _c.amounts[i],
                  keyboardType: const TextInputType.numberWithOptions(decimal: true),
                  decoration: const InputDecoration(labelText: 'Amount', prefixText: '₱ '),
                  onChanged: (v) => _set(_c.copyWith(amounts: [..._c.amounts]..[i] = v)),
                ),
              ),
            ]),
            for (final x in problems.where((x) => x.$2 == i + 1)) problem(x),
            const SizedBox(height: 10),
          ],
          if (_p.charges.isNotEmpty)
            const Text('Fees and discounts stay as recorded. If an amount changes, they are split again by amount.',
                style: TextStyle(fontSize: 12.5, color: WmColors.textMuted)),
          const SizedBox(height: 10),
          const Text('Add receipt photos', style: TextStyle(fontWeight: FontWeight.w800)),
          for (final slot in receiptSlots.where((s) => !_p.docs.containsKey(s)))
            Row(children: [
              Expanded(child: Text(receiptSlotLabels[slot]!)),
              if (_c.photos.containsKey(slot))
                const Icon(Icons.check_circle, color: WmColors.green)
              else ...[
                IconButton(key: Key('correct-camera-$slot'), onPressed: () => _photo(slot, widget.services.takePhoto), icon: const Icon(Icons.photo_camera_outlined)),
                IconButton(key: Key('correct-gallery-$slot'), onPressed: () => _photo(slot, widget.services.pickPhoto), icon: const Icon(Icons.photo_library_outlined)),
              ],
            ]),
          const SizedBox(height: 10),
          TextFormField(
            key: const Key('correct-total'),
            initialValue: _c.receiptTotal,
            keyboardType: const TextInputType.numberWithOptions(decimal: true),
            decoration: const InputDecoration(labelText: 'Total on the receipt', prefixText: '₱ '),
            onChanged: (v) => _set(_c.copyWith(receiptTotal: v)),
          ),
          Text('Items + fees − discounts: ${peso(_c.computedTotal(_p))}', style: const TextStyle(fontWeight: FontWeight.w700)),
          const SizedBox(height: 10),
          TextFormField(
            key: const Key('correct-reason'),
            initialValue: _c.reason,
            decoration: const InputDecoration(labelText: 'Why the change? (kept in the history)'),
            onChanged: (v) => _set(_c.copyWith(reason: v)),
          ),
          for (final x in problems.where((x) => x.$2 == null)) problem(x),
          const SizedBox(height: 18),
          bilingualButton(const Bilingual('Save correction', 'I-save ang pagtatama'), _busy ? null : _save, filled: true, key: const Key('correct-save')),
        ]),
      ),
    );
  }
}
