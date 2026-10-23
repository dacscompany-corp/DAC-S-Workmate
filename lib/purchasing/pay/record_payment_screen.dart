import 'dart:io';

import 'package:flutter/material.dart';

import '../../attendance/ui/attendance_copy.dart' show Bilingual;
import '../../ui/failure_notice.dart';
import '../../ui/theme.dart';
import '../data/purchasing_api.dart';
import '../domain/pay_models.dart';
import '../domain/pur_failure.dart';
import '../domain/purchase_draft.dart' show parseMoney;
import '../purchasing_services.dart';
import '../ui/pay_copy.dart';
import '../ui/pay_widgets.dart';
import '../ui/purchasing_copy.dart';

/// Record payment (0102, Q6): a later payment on a recorded purchase — a
/// deposit, the rest, or more. Works with no signal: it is saved on the phone
/// as "Waiting to send" and recorded once, when there is signal. True once
/// queued.
Future<bool> openRecordPayment(
  BuildContext context,
  PurchasingServices services, {
  required String purchaseId,
  required String supplier,
  String? supplierId,
  required double left,
}) async =>
    await Navigator.of(context).push<bool>(
      MaterialPageRoute(
        builder: (_) => RecordPaymentScreen(services: services, purchaseId: purchaseId, supplier: supplier, supplierId: supplierId, left: left),
      ),
    ) ==
    true;

class RecordPaymentScreen extends StatefulWidget {
  const RecordPaymentScreen({super.key, required this.services, required this.purchaseId, required this.supplier, this.supplierId, required this.left});

  final PurchasingServices services;
  final String purchaseId;
  final String supplier;
  final String? supplierId;

  /// Still to pay, payments waiting on this phone counted.
  final double left;

  @override
  State<RecordPaymentScreen> createState() => _RecordPaymentScreenState();
}

class _RecordPaymentScreenState extends State<RecordPaymentScreen> {
  PurchasingApi get _api => widget.services.api;

  late final TextEditingController _amount = TextEditingController(text: widget.left > 0 ? widget.left.toStringAsFixed(2) : '');
  final _note = TextEditingController();
  late String _paidOn = _api.today();
  String _source = 'company';
  String _method = 'cash';
  String? _credit;
  String? _proof;
  MyCashView? _cash;
  List<PayProblem> _problems = const [];
  Bilingual? _notice;
  bool _saving = false;
  bool _saved = false;

  @override
  void initState() {
    super.initState();
    _amount.addListener(() => setState(() {}));
    _loadCash();
  }

  Future<void> _loadCash() async {
    try {
      final c = await _api.myCash();
      if (!mounted) return;
      setState(() {
        _cash = c;
        // A staff buyer usually pays from the petty cash they hold.
        if (_holder) _source = 'petty_cash';
      });
    } catch (_) {
      // Offline and never read: company money, petty cash; the server decides.
    }
  }

  @override
  void dispose() {
    _amount.dispose();
    _note.dispose();
    // A proof never queued is the phone's own file: it goes.
    final p = _proof;
    // R39: a photo is the phone's own until Save hands it to the queue. While
    // a Save is under way its owner is not known yet: it is kept, never deleted.
    if (!_saved && !_saving && p != null) _api.discardPhoto(p);
    super.dispose();
  }

  bool get _holder => _cash?.cash?.holder ?? true;
  bool get _ownMoney => _holder && (_cash?.cash?.ownMoney ?? false);
  List<SupplierCredit> get _credits => _cash?.creditsFor(widget.supplierId) ?? const [];

  /// R2, Q21, Q11: what this account may pay with.
  List<String> get _sources => [if (_holder) 'petty_cash', if (_ownMoney) 'own_money', 'company', if (_credits.isNotEmpty) 'credit'];

  PaymentInput get _input =>
      PaymentInput(amount: _amount.text, paidOn: _paidOn, method: _method, source: _source, creditId: _source == 'credit' ? _credit : null, note: _note.text);

  Future<void> _photo(Future<String?> Function(BuildContext) pick) async {
    final src = await pick(context);
    if (src == null || !mounted) return;
    final kept = await _api.keepPhoto('pay-${widget.purchaseId}', src);
    final old = _proof;
    setState(() => _proof = kept);
    if (old != null) await _api.discardPhoto(old);
  }

  Future<void> _pickDate() async {
    final today = DateTime.parse(_api.today());
    final picked = await showDatePicker(context: context, initialDate: DateTime.tryParse(_paidOn) ?? today, firstDate: DateTime(2020), lastDate: today);
    if (picked != null) {
      setState(() => _paidOn = '${picked.year.toString().padLeft(4, '0')}-${picked.month.toString().padLeft(2, '0')}-${picked.day.toString().padLeft(2, '0')}');
    }
  }

  Future<void> _save() async {
    if (_saving) return;
    setState(() {
      _saving = true;
      _notice = null;
    });
    try {
      await _api.pay(widget.purchaseId, _input, proofPhoto: _proof);
      _saved = true;
      if (mounted) Navigator.of(context).pop(true);
    } on PaymentInvalid catch (e) {
      setState(() => _problems = e.problems);
    } catch (e) {
      setState(() => _notice = purFailureCopy(PurFailure.of(e)));
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final sources = _sources;
    if (!sources.contains(_source)) _source = sources.first;
    if (_source == 'credit' && !_credits.any((c) => c.id == _credit)) _credit = _credits.first.id;
    final figures = _cash?.figures;
    final over = _source == 'petty_cash' && figures != null ? overspendBy(_amount.text, figures.held) : null;
    return PopScope(
      canPop: !_saving,
      child: Scaffold(
        appBar: AppBar(
          title: const BilingualText(recordPaymentLabel, style: TextStyle(fontWeight: FontWeight.w800, fontSize: 18)),
        ),
        body: SafeArea(
          child: ListView(
            key: const Key('pay-form'),
            padding: const EdgeInsets.all(16),
            children: [
              Text(widget.supplier.isEmpty ? 'No supplier' : widget.supplier, style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 18)),
              Text(
                widget.left > 0 ? '${peso(widget.left)} left to pay' : 'Nothing left to pay — a payment now is over the receipt.',
                style: const TextStyle(color: WmColors.textMuted),
              ),
              const Text(
                'Saved on this phone. It is sent when there is signal. A payment never changes Spent.',
                style: TextStyle(fontSize: 12.5, color: WmColors.textMeta),
              ),
              if (_notice != null) ...[const SizedBox(height: 10), FailureNotice(english: _notice!.english, tagalog: _notice!.tagalog)],
              const SizedBox(height: 14),
              TextField(
                key: const Key('pay-amount'),
                controller: _amount,
                keyboardType: const TextInputType.numberWithOptions(decimal: true),
                decoration: const InputDecoration(labelText: 'Amount', prefixText: '₱ '),
              ),
              if (_problems.contains(PayProblem.badAmount)) _problem(PayProblem.badAmount),
              const SizedBox(height: 10),
              InkWell(
                key: const Key('pay-date'),
                onTap: _pickDate,
                child: InputDecorator(
                  decoration: const InputDecoration(labelText: 'Paid on'),
                  child: Text(_paidOn),
                ),
              ),
              if (_problems.contains(PayProblem.badDate)) _problem(PayProblem.badDate),
              const SizedBox(height: 10),
              DropdownButtonFormField<String>(
                key: ValueKey('pay-source-${sources.join(',')}'),
                initialValue: _source,
                isExpanded: true,
                decoration: InputDecoration(labelText: '${paidFromLabel.english} · ${paidFromLabel.tagalog}'),
                items: [
                  for (final s in sources)
                    DropdownMenuItem(
                      value: s,
                      child: Text(paySourceCopy(s).english, overflow: TextOverflow.ellipsis),
                    ),
                ],
                onChanged: (s) => setState(() => _source = s ?? 'company'),
              ),
              const SizedBox(height: 10),
              if (_source == 'credit')
                DropdownButtonFormField<String>(
                  key: const Key('pay-credit'),
                  initialValue: _credit,
                  isExpanded: true,
                  decoration: const InputDecoration(labelText: 'Credit to use'),
                  items: [
                    for (final c in _credits)
                      DropdownMenuItem(
                        value: c.id,
                        child: Text('${c.supplier} — ${peso(c.left)} left', overflow: TextOverflow.ellipsis),
                      ),
                  ],
                  onChanged: (id) => setState(() => _credit = id),
                )
              else
                DropdownButtonFormField<String>(
                  key: const Key('pay-method'),
                  initialValue: _method,
                  isExpanded: true,
                  decoration: const InputDecoration(labelText: 'How'),
                  items: [for (final m in payMethods) DropdownMenuItem(value: m, child: Text(payMethodLabel(m)))],
                  onChanged: (m) => setState(() => _method = m ?? 'cash'),
                ),
              for (final p in _problems.where((p) => p == PayProblem.creditRequired || p == PayProblem.overCredit)) _problem(p),
              if (over != null) ...[
                const SizedBox(height: 10),
                PayWarning(key: const Key('pay-overspend'), text: overspendCopy(peso(figures!.held), peso(parseMoney(_amount.text) ?? 0))),
              ],
              const SizedBox(height: 10),
              TextField(
                key: const Key('pay-note'),
                controller: _note,
                decoration: const InputDecoration(labelText: 'Note (optional)'),
              ),
              const SizedBox(height: 14),
              const Text('Proof (optional) — GCash screenshot, deposit slip', style: TextStyle(fontWeight: FontWeight.w700)),
              const SizedBox(height: 6),
              if (_proof != null)
                ClipRRect(
                  borderRadius: BorderRadius.circular(10),
                  child: Image.file(
                    File(_proof!),
                    key: const Key('pay-proof'),
                    height: 120,
                    fit: BoxFit.cover,
                    errorBuilder: (_, _, _) => const Icon(Icons.image),
                  ),
                ),
              Wrap(
                spacing: 8,
                children: [
                  TextButton.icon(
                    key: const Key('pay-proof-camera'),
                    onPressed: () => _photo(widget.services.takePhoto),
                    icon: const Icon(Icons.photo_camera_outlined),
                    label: const Text('Camera'),
                  ),
                  TextButton.icon(
                    key: const Key('pay-proof-gallery'),
                    onPressed: () => _photo(widget.services.pickPhoto),
                    icon: const Icon(Icons.photo_library_outlined),
                    label: const Text('Gallery'),
                  ),
                ],
              ),
              const SizedBox(height: 20),
              bilingualButton(recordPaymentLabel, _saving ? null : _save, filled: true, key: const Key('pay-save')),
            ],
          ),
        ),
      ),
    );
  }

  Widget _problem(PayProblem p) {
    final b = payProblemCopy(p);
    return Padding(
      key: Key('pay-problem-${p.name}'),
      padding: const EdgeInsets.only(top: 4),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            b.english,
            style: const TextStyle(color: WmColors.danger, fontWeight: FontWeight.w700, fontSize: 13),
          ),
          Text(b.tagalog, style: const TextStyle(color: WmColors.danger, fontSize: 12)),
        ],
      ),
    );
  }
}
