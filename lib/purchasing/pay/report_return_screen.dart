import 'dart:io';

import 'package:flutter/material.dart';

import '../../attendance/ui/attendance_copy.dart' show Bilingual;
import '../../ui/failure_notice.dart';
import '../../ui/theme.dart';
import '../data/purchasing_api.dart';
import '../domain/pay_models.dart';
import '../domain/pur_failure.dart';
import '../purchasing_services.dart';
import '../ui/pay_copy.dart';
import '../ui/purchasing_copy.dart';

/// Report a return (0102, Q17): petty cash handed back to the owner. It waits
/// for the owner's confirmation, which alone lowers cash held — on the day
/// the owner confirms (Q18). Saved on the phone and sent once (Q6). Its
/// optional photo is filed in the private pettyCash/ folder: only the owner
/// and this buyer can open it (R13). True once queued.
class ReportReturnScreen extends StatefulWidget {
  const ReportReturnScreen({super.key, required this.services, this.held});
  final PurchasingServices services;

  /// Cash held as shown, for the hint only: a return is never capped (R11).
  final double? held;

  @override
  State<ReportReturnScreen> createState() => _ReportReturnScreenState();
}

class _ReportReturnScreenState extends State<ReportReturnScreen> {
  PurchasingApi get _api => widget.services.api;

  final _amount = TextEditingController();
  final _to = TextEditingController();
  final _note = TextEditingController();
  late String _handedOn = _api.today();
  String? _photo;
  List<ReturnProblem> _problems = const [];
  Bilingual? _notice;
  bool _saving = false;
  bool _saved = false;

  @override
  void dispose() {
    _amount.dispose();
    _to.dispose();
    _note.dispose();
    final p = _photo;
    // R39: a photo is the phone's own until Save hands it to the queue. While
    // a Save is under way its owner is not known yet: it is kept, never deleted.
    if (!_saved && !_saving && p != null) _api.discardPhoto(p);
    super.dispose();
  }

  Future<void> _takePhoto(Future<String?> Function(BuildContext) pick) async {
    final src = await pick(context);
    if (src == null || !mounted) return;
    final kept = await _api.keepPhoto('return', src);
    final old = _photo;
    setState(() => _photo = kept);
    if (old != null) await _api.discardPhoto(old);
  }

  Future<void> _pickDate() async {
    final today = DateTime.parse(_api.today());
    final picked = await showDatePicker(context: context, initialDate: DateTime.tryParse(_handedOn) ?? today, firstDate: DateTime(2020), lastDate: today);
    if (picked != null) {
      setState(
        () => _handedOn = '${picked.year.toString().padLeft(4, '0')}-${picked.month.toString().padLeft(2, '0')}-${picked.day.toString().padLeft(2, '0')}',
      );
    }
  }

  Future<void> _save() async {
    if (_saving) return;
    setState(() {
      _saving = true;
      _notice = null;
    });
    try {
      await _api.reportReturn(
        ReturnInput(amount: _amount.text, handedOn: _handedOn, handedTo: _to.text, note: _note.text),
        photo: _photo,
      );
      _saved = true;
      if (mounted) Navigator.of(context).pop(true);
    } on ReturnInvalid catch (e) {
      setState(() => _problems = e.problems);
    } catch (e) {
      setState(() => _notice = purFailureCopy(PurFailure.of(e)));
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  Widget _problem(Bilingual b, String key) => Padding(
    key: Key(key),
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

  @override
  Widget build(BuildContext context) => PopScope(
    canPop: !_saving,
    child: Scaffold(
      appBar: AppBar(
        title: const BilingualText(reportReturnLabel, style: TextStyle(fontWeight: FontWeight.w800, fontSize: 18)),
      ),
      body: SafeArea(
        child: ListView(
          padding: const EdgeInsets.all(16),
          children: [
            const BilingualText(
              Bilingual(
                'It waits for the owner. Only the owner\'s confirmation lowers your cash held.',
                'Hihintayin ang may-ari. Ang kumpirmasyon lang ng may-ari ang magbabawas sa hawak mong pera.',
              ),
              style: TextStyle(fontSize: 13, color: WmColors.textSecondary),
            ),
            if (widget.held != null) Text('You hold ${peso(widget.held!)} on record.', style: const TextStyle(color: WmColors.textMuted)),
            if (_notice != null) ...[const SizedBox(height: 10), FailureNotice(english: _notice!.english, tagalog: _notice!.tagalog)],
            const SizedBox(height: 14),
            TextField(
              key: const Key('return-amount'),
              controller: _amount,
              keyboardType: const TextInputType.numberWithOptions(decimal: true),
              decoration: const InputDecoration(labelText: 'Amount handed back', prefixText: '₱ '),
            ),
            if (_problems.contains(ReturnProblem.badAmount))
              _problem(const Bilingual('Enter the amount handed back.', 'Ilagay ang halagang ibinalik.'), 'return-problem-amount'),
            const SizedBox(height: 10),
            InkWell(
              key: const Key('return-date'),
              onTap: _pickDate,
              child: InputDecorator(
                decoration: const InputDecoration(labelText: 'Handed over on'),
                child: Text(_handedOn),
              ),
            ),
            if (_problems.contains(ReturnProblem.badDate))
              _problem(
                const Bilingual('Pick the day you handed it over (not in the future).', 'Piliin ang araw na ibinigay mo (hindi sa hinaharap).'),
                'return-problem-date',
              ),
            const SizedBox(height: 10),
            TextField(
              key: const Key('return-to'),
              controller: _to,
              decoration: const InputDecoration(labelText: 'Handed to (optional)'),
            ),
            const SizedBox(height: 10),
            TextField(
              key: const Key('return-note'),
              controller: _note,
              decoration: const InputDecoration(labelText: 'Note (optional)'),
            ),
            const SizedBox(height: 14),
            const Text('Photo (optional)', style: TextStyle(fontWeight: FontWeight.w700)),
            const Text('Only you and the owner can open it.', style: TextStyle(fontSize: 12.5, color: WmColors.textMeta)),
            const SizedBox(height: 6),
            if (_photo != null)
              ClipRRect(
                borderRadius: BorderRadius.circular(10),
                child: Image.file(
                  File(_photo!),
                  key: const Key('return-photo'),
                  height: 120,
                  fit: BoxFit.cover,
                  errorBuilder: (_, _, _) => const Icon(Icons.image),
                ),
              ),
            Wrap(
              spacing: 8,
              children: [
                TextButton.icon(
                  key: const Key('return-photo-camera'),
                  onPressed: () => _takePhoto(widget.services.takePhoto),
                  icon: const Icon(Icons.photo_camera_outlined),
                  label: const Text('Camera'),
                ),
                TextButton.icon(
                  key: const Key('return-photo-gallery'),
                  onPressed: () => _takePhoto(widget.services.pickPhoto),
                  icon: const Icon(Icons.photo_library_outlined),
                  label: const Text('Gallery'),
                ),
              ],
            ),
            const SizedBox(height: 20),
            bilingualButton(reportReturnLabel, _saving ? null : _save, filled: true, key: const Key('return-save')),
          ],
        ),
      ),
    ),
  );
}
