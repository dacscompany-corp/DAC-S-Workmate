import 'package:flutter/material.dart';

import '../../attendance/ui/attendance_copy.dart' show Bilingual;
import '../../purchasing/ui/purchasing_copy.dart' show BilingualText;
import '../../ui/failure_notice.dart';
import '../../ui/theme.dart';
import '../../ui/wm_chips.dart';
import '../../ui/wm_sheet.dart';
import '../data/stock_submitter.dart';
import '../domain/stock_failure.dart';
import '../domain/stock_models.dart';
import 'leftover_screen.dart';
import 'move_screen.dart';
import 'receive_sheet.dart';
import 'stock_controller.dart';
import 'stock_copy.dart';
import 'stock_widgets.dart';

enum StockPart { stock, receive, recent }

/// Opens the issue / move / return form; true when the server recorded it.
Future<bool> openMove(BuildContext context, StockController controller, StockSubmitter submitter, MovePreset preset) async {
  final done = await showWmSheet<bool>(
    context,
    builder: (_) => MoveScreen(remote: controller.remote, submitter: submitter, preset: preset, overview: controller.overview),
  );
  return done == true;
}

/// The Stock tab (Q26): quantities only — never a peso, even for an owner
/// (Q28). Records here; matching, counts, opening stock, reversals and every
/// cost decision stay on Dacs Web. A record whose answer was lost waits at
/// the top, and no new one starts until it is resolved (R101).
class StockScreen extends StatefulWidget {
  const StockScreen({super.key, required this.controller, required this.submitter, this.onRecorded});

  final StockController controller;
  final StockSubmitter submitter;

  /// After a record the server accepted (the shopping list changes too).
  final VoidCallback? onRecorded;

  @override
  State<StockScreen> createState() => _StockScreenState();
}

class _StockScreenState extends State<StockScreen> {
  StockPart _part = StockPart.stock;

  StockController get _c => widget.controller;
  StockSubmitter get _s => widget.submitter;

  Future<void> _after(Future<bool> recorded) async {
    if (await recorded) await _recorded();
  }

  Future<void> _recorded() async {
    widget.onRecorded?.call();
    await _c.refresh();
    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
        key: Key('stock-recorded'),
        content: Text('Recorded. · Naitala na.'),
      ));
    }
  }

  void _issue() => _after(openMove(context, _c, _s, const MovePreset()));

  void _leftovers() => _after(Navigator.of(context)
      .push<bool>(MaterialPageRoute(builder: (_) => LeftoverScreen(remote: _c.remote, submitter: _s)))
      .then((v) => v == true));

  void _receive(StockLine line) => _after(showWmSheet<bool>(
        context,
        builder: (_) => ReceiveSheet(submitter: _s, line: line),
      ).then((v) => v == true));

  void _return(StockRecord r) => _after(openMove(
        context,
        _c,
        _s,
        MovePreset(itemId: r.itemId, returnsRecord: r.id, returnFrom: r.toName, quantity: r.returnable),
      ));

  void _refused(StockFailure f) {
    final copy = stockFailureCopy(f);
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(key: const Key('stock-refused'), content: Text('${copy.english}\n${copy.tagalog}')));
  }

  @override
  Widget build(BuildContext context) => ListenableBuilder(
        listenable: Listenable.merge([_c, _s]),
        builder: (context, _) {
          // Nothing new while one is unresolved (R101).
          final can = _c.status.canRecord && !_s.blocked;
          final ov = _c.overview;
          return RefreshIndicator(
            onRefresh: _c.refresh,
            child: ListView(padding: const EdgeInsets.fromLTRB(20, 16, 20, 28), children: [
              const Text('Stock', style: TextStyle(fontWeight: FontWeight.w800, fontSize: 26)),
              Text(stockTitle.tagalog, style: const TextStyle(fontSize: 13, color: WmColors.textMuted)),
              const SizedBox(height: 14),
              WmSegmented<StockPart>(
                key: const Key('stock-parts'),
                segments: [
                  (StockPart.stock, 'Stock', const Key('stock-part-stock')),
                  (StockPart.receive, 'To receive (${ov.awaiting.length})', const Key('stock-part-receive')),
                  (StockPart.recent, 'Recent', const Key('stock-part-recent')),
                ],
                selected: _part,
                onChanged: (p) => setState(() => _part = p),
              ),
              if (_c.failure != null) ...[
                const SizedBox(height: 10),
                FailureNotice(
                  key: const Key('stock-signal'),
                  english: _c.failure == StockFailure.noConnection ? stockNeedsSignal.english : stockFailureCopy(_c.failure!).english,
                  tagalog: _c.failure == StockFailure.noConnection ? stockNeedsSignal.tagalog : stockFailureCopy(_c.failure!).tagalog,
                  actions: [noticeAction('Try again · Subukan ulit', _c.refresh)],
                ),
              ],
              for (final u in _s.unresolved)
                Padding(
                  padding: const EdgeInsets.only(top: 10),
                  child: UnresolvedBox(submitter: _s, opId: u.opId, onRecorded: _recorded, onSettledNotRecorded: _refused),
                ),
              for (final u in _s.unreadable)
                Padding(
                  padding: const EdgeInsets.only(top: 10),
                  child: UnreadableBox(submitter: _s, opId: u.opId!, onRecorded: _recorded, onSettledNotRecorded: _refused),
                ),
              if (_s.recoveryNeeded)
                Padding(
                  padding: const EdgeInsets.only(top: 10),
                  child: FailureNotice(key: const Key('stock-recovery'), english: recoveryLabel.english, tagalog: recoveryLabel.tagalog),
                ),
              if (_s.blocked && _c.status.canRecord && !_s.recoveryNeeded) ...[
                const SizedBox(height: 8),
                const BilingualText(finishFirst, key: Key('stock-finish-first'), style: TextStyle(fontSize: 13, color: WmColors.textMuted)),
              ],
              if (_c.loaded && !_c.enabled) ...[
                const SizedBox(height: 10),
                const BilingualText(stockOffNow, style: TextStyle(fontSize: 13, color: WmColors.textMuted)),
              ],
              if (_c.loading && !_c.loaded) const Padding(padding: EdgeInsets.all(32), child: Center(child: CircularProgressIndicator())),
              if (can && _part == StockPart.stock) ...[
                const SizedBox(height: 14),
                Row(children: [
                  Expanded(child: _ActionButton(issueMoveLabel, _issue, filled: true, key: const Key('stock-issue'))),
                  const SizedBox(width: 8),
                  Expanded(child: _ActionButton(leftoversLabel, _leftovers, key: const Key('stock-leftovers'))),
                ]),
              ],
              ...switch (_part) {
                StockPart.stock => _stock(ov),
                StockPart.receive => _toReceive(ov, can),
                StockPart.recent => _recent(ov, can),
              },
              const SizedBox(height: 16),
              const BilingualText(undoOnWeb, style: TextStyle(fontSize: 12.5, color: WmColors.textMuted)),
            ]),
          );
        },
      );

  Widget _empty(String text) => Padding(
        padding: const EdgeInsets.symmetric(vertical: 32),
        child: Center(child: Text(text, style: const TextStyle(color: WmColors.textMuted))),
      );

  List<Widget> _stock(StockOverview ov) {
    if (_c.loaded && ov.items.isEmpty) return [_empty('No goods in stock yet.')];
    return [
      for (final i in ov.items)
        _Card(
          key: Key('stock-item-${i.itemId}'),
          children: [
            Row(crossAxisAlignment: CrossAxisAlignment.baseline, textBaseline: TextBaseline.alphabetic, children: [
              Expanded(
                child: Text(i.spec.trim().isEmpty ? i.name : '${i.name} · ${i.spec}', style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 16)),
              ),
              const SizedBox(width: 8),
              Text(stockQty(i.total, i.unit), style: _mono(15)),
            ]),
            const SizedBox(height: 2),
            for (final p in i.places)
              Padding(
                padding: const EdgeInsets.only(top: 6),
                child: Row(children: [
                  Icon(p.isWarehouse ? Icons.warehouse_outlined : Icons.construction_outlined, size: 17, color: WmColors.textMuted),
                  const SizedBox(width: 8),
                  Expanded(child: Text(p.name, style: const TextStyle(fontSize: 14, color: WmColors.textSecondary))),
                  const SizedBox(width: 8),
                  Text(stockQty(p.quantity, i.unit), style: _mono(14)),
                ]),
              ),
          ],
        ),
    ];
  }

  List<Widget> _toReceive(StockOverview ov, bool can) {
    if (_c.loaded && ov.awaiting.isEmpty) return [_empty('Nothing waiting to arrive.')];
    return [
      for (final l in ov.awaiting)
        _Card(
          key: Key('awaiting-${l.key}'),
          children: [
            Text(l.itemName, style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 16)),
            const SizedBox(height: 2),
            Text('Bought ${l.purchaseDate} by ${l.boughtByName} · ${stockQty(l.quantity, l.unit)}',
                style: const TextStyle(fontSize: 13, color: WmColors.textMuted)),
            const SizedBox(height: 6),
            Text('Received ${stockQty(l.received, l.unit)} · still awaited ${stockQty(l.awaiting, l.unit)}',
                style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 14)),
            if (l.match == null) ...[
              const SizedBox(height: 2),
              const Text('Not matched yet', style: TextStyle(fontSize: 12.5, color: WmColors.brownDeep)),
            ],
            if (can) ...[
              const SizedBox(height: 10),
              SizedBox(width: double.infinity, child: _ActionButton(receivedLabel, () => _receive(l), height: 50, key: Key('receive-${l.key}'))),
            ],
          ],
        ),
    ];
  }

  List<Widget> _recent(StockOverview ov, bool can) {
    if (_c.loaded && ov.recent.isEmpty) return [_empty('Nothing recorded yet.')];
    return [
      for (final r in ov.recent)
        _Card(
          key: Key('record-${r.id}'),
          children: [
            Row(children: [
              Expanded(child: Text(recordKind(r), style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 15))),
              Text(r.on, style: const TextStyle(fontSize: 12.5, color: WmColors.textMuted)),
            ]),
            Padding(padding: const EdgeInsets.only(top: 4), child: Text(recordLine(r), style: const TextStyle(fontSize: 14))),
            if (r.requestDescription.isNotEmpty)
              Text('For: ${r.requestDescription}', style: const TextStyle(fontSize: 13, color: WmColors.textMuted)),
            if (r.unplannedReason.isNotEmpty)
              Text('Unplanned: ${r.unplannedReason}', style: const TextStyle(fontSize: 13, color: WmColors.textMuted)),
            Text('By ${r.recordedByName}', style: const TextStyle(fontSize: 12.5, color: WmColors.textMeta)),
            if (recordState(r) != null) Text(recordState(r)!, style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w700, color: WmColors.brownDeep)),
            // The cost's state only — its value is the main owner's, on the web.
            for (final c in r.costs) Text(costState(c), style: const TextStyle(fontSize: 12.5, color: WmColors.textSecondary)),
            if (can && r.canReturn) ...[
              const SizedBox(height: 8),
              _ActionButton(returnLabel, () => _return(r), height: 44, key: Key('return-${r.id}')),
            ],
          ],
        ),
    ];
  }
}

TextStyle _mono(double size) => TextStyle(fontFamily: 'IBM Plex Mono', fontWeight: FontWeight.w700, fontSize: size);

/// One card: white, 1-px border, radius 16, padding 14, 10 px from the next.
class _Card extends StatelessWidget {
  const _Card({super.key, required this.children});
  final List<Widget> children;

  @override
  Widget build(BuildContext context) => Container(
        margin: const EdgeInsets.only(top: 10),
        padding: const EdgeInsets.all(14),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(16),
          border: Border.all(color: WmColors.border),
        ),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: children),
      );
}

/// A two-language button, radius 14: filled green (Issue / move) or white with
/// an outline (the rest). [height] is its minimum height.
class _ActionButton extends StatelessWidget {
  const _ActionButton(this.label, this.onPressed, {super.key, this.filled = false, this.height = 54});
  final Bilingual label;
  final VoidCallback onPressed;
  final bool filled;
  final double height;

  @override
  Widget build(BuildContext context) {
    final shape = RoundedRectangleBorder(borderRadius: BorderRadius.circular(14));
    const pad = EdgeInsets.symmetric(horizontal: 12, vertical: 4);
    final child = Column(mainAxisSize: MainAxisSize.min, children: [
      Text(label.english, textAlign: TextAlign.center, style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w800, height: 1.15)),
      Text(label.tagalog,
          textAlign: TextAlign.center,
          style: TextStyle(fontSize: 11, fontWeight: FontWeight.w400, height: 1.15, color: filled ? const Color(0xBFFFFFFF) : WmColors.textMuted)),
    ]);
    return filled
        ? FilledButton(
            onPressed: onPressed,
            style: FilledButton.styleFrom(
                minimumSize: Size(0, height), padding: pad, backgroundColor: WmColors.green, foregroundColor: Colors.white, shape: shape),
            child: child)
        : OutlinedButton(
            onPressed: onPressed,
            style: OutlinedButton.styleFrom(
                minimumSize: Size(0, height),
                padding: pad,
                backgroundColor: Colors.white,
                foregroundColor: WmColors.green,
                side: BorderSide(color: height == 54 ? WmColors.border : WmColors.green),
                shape: shape),
            child: child);
  }
}
