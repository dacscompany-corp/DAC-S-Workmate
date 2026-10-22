import 'package:flutter/material.dart';

import '../../attendance/ui/attendance_copy.dart' show Bilingual;
import '../../attendance/ui/formats.dart';
import '../../requests/domain/quantity.dart';
import '../../ui/failure_notice.dart';
import '../../ui/theme.dart';
import '../domain/purchase_draft.dart';
import '../ui/purchasing_copy.dart';
import 'shopping_controller.dart';

/// The shopping list on the phone (Q4–Q6). Quantities and names only: the
/// prices of earlier purchases are never shown here.
class ShoppingListScreen extends StatelessWidget {
  const ShoppingListScreen({super.key, required this.controller, this.onRecord});

  final ShoppingController controller;

  /// Opens Record purchase with these lines; null hides the picking.
  final void Function(List<DraftPurchaseLine> lines)? onRecord;

  @override
  Widget build(BuildContext context) => ListenableBuilder(
        listenable: controller,
        builder: (context, _) {
          final c = controller;
          final s = c.sections;
          final batch = c.currentBatch;
          final picking = onRecord != null && c.selected.isNotEmpty;
          return Column(children: [
            Expanded(
              child: RefreshIndicator(
                onRefresh: c.refresh,
                child: ListView(padding: const EdgeInsets.all(16), children: [
                  const Text('Shopping list', style: TextStyle(fontWeight: FontWeight.w800, fontSize: 23)),
                  const Text('Mga bibilhin', style: TextStyle(fontSize: 13, color: WmColors.textMuted)),
                  const SizedBox(height: 12),
                  Wrap(spacing: 8, runSpacing: 8, crossAxisAlignment: WrapCrossAlignment.center, children: [
                    ChoiceChip(
                      key: const Key('scope-week'),
                      label: Text(batch == null ? 'This week' : 'This week · cutoff ${shortDate(batch.cutoffAt)}'),
                      selected: c.scope == BatchScope.thisWeek,
                      onSelected: (_) => c.setScope(BatchScope.thisWeek),
                    ),
                    ChoiceChip(
                      key: const Key('scope-all'),
                      label: const Text('All weeks'),
                      selected: c.scope == BatchScope.all,
                      onSelected: (_) => c.setScope(BatchScope.all),
                    ),
                    DropdownButton<String?>(
                      key: const Key('project-filter'),
                      value: c.project,
                      hint: const Text('All projects'),
                      items: [
                        const DropdownMenuItem<String?>(value: null, child: Text('All projects')),
                        for (final (id, name) in c.projects) DropdownMenuItem<String?>(value: id, child: Text(name)),
                      ],
                      onChanged: c.setProject,
                    ),
                  ]),
                  if (c.view.fromCache) ...[
                    const SizedBox(height: 10),
                    _Banner(
                      key: const Key('shopping-saved-copy'),
                      text: Bilingual(
                        'Saved copy from ${c.view.fetchedAt == null ? 'earlier' : '${shortDate(c.view.fetchedAt!)} ${clockTime(c.view.fetchedAt!)}'}. '
                            'Claiming needs signal.',
                        'Lumang kopya. Kailangan ng signal para kumuha ng bibilhin.',
                      ),
                    ),
                  ],
                  if (c.notice != null) ...[
                    const SizedBox(height: 10),
                    FailureNotice(
                      english: c.notice!.english,
                      tagalog: c.notice!.tagalog,
                      actions: [noticeAction('Dismiss · Isara', c.dismissNotice)],
                    ),
                  ],
                  if (c.loading && c.view.lines.isEmpty) const Padding(padding: EdgeInsets.all(32), child: Center(child: CircularProgressIndicator())),
                  if (!c.loading && s.isEmpty)
                    const Padding(
                      padding: EdgeInsets.symmetric(vertical: 40),
                      child: BilingualText(Bilingual('Nothing left to buy here.', 'Wala nang bibilhin dito.'), align: CrossAxisAlignment.center),
                    ),
                  _section(context, mineLabel, s.mine, _Kind.mine),
                  _section(context, unassignedLabel, s.unassigned, _Kind.unassigned),
                  _section(context, othersLabel, s.others, _Kind.others),
                  // Room under the last card for the round Record purchase button.
                  const SizedBox(height: 88),
                ]),
              ),
            ),
            if (picking)
              SafeArea(
                top: false,
                child: Padding(
                  padding: const EdgeInsets.fromLTRB(16, 8, 16, 12),
                  child: bilingualButton(
                    Bilingual('${recordLabel.english} (${c.selected.length})', recordLabel.tagalog),
                    () {
                      final lines = c.linesForSelected();
                      c.clearSelection();
                      onRecord!(lines);
                    },
                    filled: true,
                    key: const Key('record-selected'),
                  ),
                ),
              ),
          ]);
        },
      );

  Widget _section(BuildContext context, Bilingual title, List<ShoppingEntry> entries, _Kind kind) {
    if (entries.isEmpty) return const SizedBox.shrink();
    return Padding(
      padding: const EdgeInsets.only(top: 18),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        BilingualText(title, style: monoLabel),
        const SizedBox(height: 6),
        for (final e in entries) _EntryCard(entry: e, kind: kind, controller: controller, canPick: onRecord != null),
      ]),
    );
  }
}

enum _Kind { mine, unassigned, others }

class _Banner extends StatelessWidget {
  const _Banner({super.key, required this.text});
  final Bilingual text;

  @override
  Widget build(BuildContext context) => Container(
        width: double.infinity,
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(color: WmColors.brownTint, borderRadius: BorderRadius.circular(14)),
        child: BilingualText(text, style: const TextStyle(fontSize: 13.5, fontWeight: FontWeight.w600, color: WmColors.brownDeep)),
      );
}

class _EntryCard extends StatelessWidget {
  const _EntryCard({required this.entry, required this.kind, required this.controller, required this.canPick});
  final ShoppingEntry entry;
  final _Kind kind;
  final ShoppingController controller;
  final bool canPick;

  Future<void> _claim(BuildContext context) async {
    final p = entry.portion;
    final qty = await showModalBottomSheet<double>(
      context: context,
      isScrollControlled: true,
      showDragHandle: true,
      builder: (_) => _ClaimSheet(still: p.stillToBuy, unit: entry.line.unit),
    );
    if (qty != null) await controller.claim(entry, quantity: qty);
  }

  @override
  Widget build(BuildContext context) {
    final l = entry.line;
    final p = entry.portion;
    final busy = controller.busy.contains(p.id);
    final picked = controller.selected.contains(p.id);
    final title = l.spec.trim().isEmpty ? l.description : '${l.description} · ${l.spec}';
    return Card(
      key: Key('entry-${p.id}'),
      margin: const EdgeInsets.only(bottom: 10),
      color: Colors.white,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16), side: const BorderSide(color: WmColors.border)),
      child: Padding(
        padding: const EdgeInsets.all(14),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
            if (kind == _Kind.mine && canPick)
              Checkbox(key: Key('pick-${p.id}'), value: picked, onChanged: busy ? null : (_) => controller.toggle(entry)),
            Expanded(
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Text(title, style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 16)),
                Text('${l.placeLabel} · for ${l.requesterName}', style: const TextStyle(fontSize: 13, color: WmColors.textMuted)),
              ]),
            ),
          ]),
          const SizedBox(height: 6),
          Wrap(spacing: 6, runSpacing: 6, children: [
            if (l.urgent)
              _Pill(
                  key: Key('urgent-${p.id}'),
                  text: l.neededBy == null ? 'Urgent' : 'Urgent · needed by ${l.neededBy}',
                  color: WmColors.danger,
                  tint: WmColors.dangerTint),
            if (!l.urgent && l.neededBy != null) _Pill(text: 'Needed by ${l.neededBy}', color: WmColors.brownDeep, tint: WmColors.brownTint),
            if (p.changed)
              _Pill(key: Key('changed-${p.id}'), text: 'Quantity changed', color: WmColors.brownDeep, tint: WmColors.brownTint),
            if (p.arranged) const _Pill(text: 'Arranged', color: WmColors.green, tint: WmColors.greenTint),
            if (kind == _Kind.others) _Pill(text: 'Buying: ${p.buyerName ?? 'another buyer'}', color: WmColors.textSecondary, tint: WmColors.inert),
          ]),
          const SizedBox(height: 8),
          Row(children: [
            Expanded(child: _Number(label: neededLabel, value: qtyUnit(l.needed, l.unit))),
            Expanded(child: _Number(label: boughtLabel, value: qtyUnit(l.bought, l.unit))),
            Expanded(child: _Number(label: stillToBuyLabel, value: qtyUnit(p.stillToBuy, l.unit), strong: true)),
          ]),
          if (l.notes.trim().isNotEmpty) ...[
            const SizedBox(height: 6),
            Text(l.notes, style: const TextStyle(fontSize: 13, color: WmColors.textSecondary)),
          ],
          if (kind != _Kind.others) ...[
            const SizedBox(height: 10),
            if (busy)
              const LinearProgressIndicator()
            else if (kind == _Kind.unassigned)
              bilingualButton(claimLabel, () => _claim(context), key: Key('claim-${p.id}'))
            else
              Row(children: [
                Expanded(child: bilingualButton(releaseLabel, () => controller.release(entry), key: Key('release-${p.id}'))),
                const SizedBox(width: 8),
                Expanded(
                  child: bilingualButton(p.arranged ? notArrangedLabel : arrangedLabel, () => controller.setArranged(entry, !p.arranged),
                      key: Key('arranged-${p.id}')),
                ),
              ]),
          ],
        ]),
      ),
    );
  }
}

class _Pill extends StatelessWidget {
  const _Pill({super.key, required this.text, required this.color, required this.tint});
  final String text;
  final Color color;
  final Color tint;

  @override
  Widget build(BuildContext context) => Container(
        padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 3),
        decoration: BoxDecoration(color: tint, borderRadius: BorderRadius.circular(20)),
        child: Text(text, style: TextStyle(fontSize: 12, fontWeight: FontWeight.w700, color: color)),
      );
}

class _Number extends StatelessWidget {
  const _Number({required this.label, required this.value, this.strong = false});
  final Bilingual label;
  final String value;
  final bool strong;

  @override
  Widget build(BuildContext context) => Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Text(value, style: TextStyle(fontWeight: strong ? FontWeight.w800 : FontWeight.w600, fontSize: strong ? 16 : 14.5)),
        Text(label.english, style: const TextStyle(fontSize: 11.5, color: WmColors.textMuted)),
        Text(label.tagalog, style: const TextStyle(fontSize: 10.5, color: WmColors.textMeta)),
      ]);
}

/// How much to claim (Q5): all of it by default, or part (e.g. 4 of 10).
class _ClaimSheet extends StatefulWidget {
  const _ClaimSheet({required this.still, required this.unit});
  final double still;
  final String unit;

  @override
  State<_ClaimSheet> createState() => _ClaimSheetState();
}

class _ClaimSheetState extends State<_ClaimSheet> {
  late final _qty = TextEditingController(text: formatQuantity(widget.still).replaceAll(',', ''));
  String? _error;

  @override
  void dispose() {
    _qty.dispose();
    super.dispose();
  }

  void _done() {
    final q = parseQuantity(_qty.text);
    if (q == null || q > widget.still) {
      setState(() => _error = 'Enter up to ${qtyUnit(widget.still, widget.unit)}.');
      return;
    }
    Navigator.of(context).pop(q);
  }

  @override
  Widget build(BuildContext context) => Padding(
        padding: EdgeInsets.fromLTRB(20, 0, 20, 20 + MediaQuery.of(context).viewInsets.bottom),
        child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.start, children: [
          const BilingualText(claimLabel, style: TextStyle(fontWeight: FontWeight.w800, fontSize: 19)),
          const SizedBox(height: 6),
          Text('${stillToBuyLabel.english}: ${qtyUnit(widget.still, widget.unit)}. Take all of it, or part.',
              style: const TextStyle(color: WmColors.textMuted)),
          const SizedBox(height: 12),
          TextField(
            key: const Key('claim-qty'),
            controller: _qty,
            keyboardType: const TextInputType.numberWithOptions(decimal: true),
            decoration: InputDecoration(labelText: 'How much will you buy?', suffixText: widget.unit, errorText: _error),
          ),
          const SizedBox(height: 14),
          FilledButton(key: const Key('claim-confirm'), onPressed: _done, child: const Text('CLAIM')),
        ]),
      );
}
