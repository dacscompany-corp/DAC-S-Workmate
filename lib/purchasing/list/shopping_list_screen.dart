import 'package:flutter/material.dart';

import '../../attendance/ui/attendance_copy.dart' show Bilingual;
import '../../attendance/ui/formats.dart';
import '../../requests/domain/quantity.dart';
import '../../stock/ui/stock_copy.dart' show fromStockLabel, issueFromStockLabel;
import '../../ui/failure_notice.dart';
import '../../ui/theme.dart';
import '../../ui/wm_chips.dart';
import '../../ui/wm_sheet.dart';
import '../domain/purchase_draft.dart';
import '../ui/purchasing_copy.dart';
import 'shopping_controller.dart';

/// The shopping list on the phone (Q4–Q6). Quantities and names only: the
/// prices of earlier purchases are never shown here.
class ShoppingListScreen extends StatelessWidget {
  const ShoppingListScreen({super.key, required this.controller, this.onRecord, this.onIssueFromStock});

  final ShoppingController controller;

  /// Opens Record purchase with these lines; null hides the picking.
  final void Function(List<DraftPurchaseLine> lines)? onRecord;

  /// 2B-b: opens Issue from stock for this line; null (stock off, or this
  /// account may not record stock) hides the button.
  final void Function(ShoppingEntry entry)? onIssueFromStock;

  @override
  Widget build(BuildContext context) => ListenableBuilder(
        listenable: controller,
        builder: (context, _) {
          final c = controller;
          final s = c.sections;
          final batch = c.currentBatch;
          final picking = onRecord != null && c.selected.isNotEmpty;
          final projectName = c.projects.where((p) => p.$1 == c.project).map((p) => p.$2).firstOrNull;
          return Stack(children: [
            RefreshIndicator(
              onRefresh: c.refresh,
              // Room under the last card for the floating bar and the shell's
              // floating Record purchase button.
              child: ListView(padding: const EdgeInsets.fromLTRB(20, 16, 20, 150), children: [
                const Text('Shopping list', style: TextStyle(fontWeight: FontWeight.w800, fontSize: 26)),
                const Text('Mga bibilhin', style: TextStyle(fontSize: 13, color: WmColors.textMuted)),
                const SizedBox(height: 14),
                WmChipRow(children: [
                  WmChoiceChip(
                    key: const Key('scope-week'),
                    label: batch == null ? 'This week' : 'This week · cutoff ${shortDate(batch.cutoffAt)}',
                    selected: c.scope == BatchScope.thisWeek,
                    onTap: () => c.setScope(BatchScope.thisWeek),
                  ),
                  WmChoiceChip(
                    key: const Key('scope-all'),
                    label: 'All weeks',
                    selected: c.scope == BatchScope.all,
                    onTap: () => c.setScope(BatchScope.all),
                  ),
                  _ProjectPill(name: projectName, projects: c.projects, onChosen: c.setProject),
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
              ]),
            ),
            if (picking)
              Positioned(
                left: 16,
                right: 16,
                bottom: 12,
                child: Semantics(
                  button: true,
                  child: Material(
                  key: const Key('record-selected'),
                  color: WmColors.green,
                  elevation: 6,
                  shadowColor: const Color(0x5912482D),
                  borderRadius: BorderRadius.circular(16),
                  child: InkWell(
                    borderRadius: BorderRadius.circular(16),
                    onTap: () {
                      final lines = c.linesForSelected();
                      c.clearSelection();
                      onRecord!(lines);
                    },
                    child: Container(
                      constraints: const BoxConstraints(minHeight: 58),
                      padding: const EdgeInsets.symmetric(vertical: 6, horizontal: 12),
                      child: Column(mainAxisSize: MainAxisSize.min, mainAxisAlignment: MainAxisAlignment.center, children: [
                        Text('${recordLabel.english} (${c.selected.length})',
                            textAlign: TextAlign.center, style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w800, color: Colors.white)),
                        Text(recordLabel.tagalog, style: const TextStyle(fontSize: 11.5, color: Color(0xBFFFFFFF))),
                      ]),
                    ),
                  ),
                ),
                ),
              ),
          ]);
        },
      );

  Widget _section(BuildContext context, Bilingual title, List<ShoppingEntry> entries, _Kind kind) {
    if (entries.isEmpty) return const SizedBox.shrink();
    return Padding(
      padding: const EdgeInsets.only(top: 20),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Wrap(crossAxisAlignment: WrapCrossAlignment.center, children: [
          Text(title.english.toUpperCase(), style: monoLabel),
          Text(' · ${title.tagalog}', style: monoLabel.copyWith(fontWeight: FontWeight.w400, letterSpacing: 0)),
        ]),
        for (final e in entries)
          _EntryCard(entry: e, kind: kind, controller: controller, canPick: onRecord != null, onIssueFromStock: onIssueFromStock),
      ]),
    );
  }
}

enum _Kind { mine, unassigned, others }

/// The project filter: a white pill that opens a menu of the same choices the
/// old dropdown had. "All projects" is the empty id (a menu cannot return null).
class _ProjectPill extends StatelessWidget {
  const _ProjectPill({required this.name, required this.projects, required this.onChosen});
  final String? name;
  final List<(String, String)> projects;
  final void Function(String? id) onChosen;

  @override
  Widget build(BuildContext context) => PopupMenuButton<String>(
        key: const Key('project-filter'),
        tooltip: 'Project',
        position: PopupMenuPosition.under,
        onSelected: (id) => onChosen(id.isEmpty ? null : id),
        itemBuilder: (_) => [
          const PopupMenuItem<String>(value: '', child: Text('All projects')),
          for (final (id, label) in projects) PopupMenuItem<String>(value: id, child: Text(label)),
        ],
        child: Container(
          height: 38,
          constraints: const BoxConstraints(maxWidth: 240),
          padding: const EdgeInsets.fromLTRB(16, 0, 10, 0),
          decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(999), border: Border.all(color: WmColors.border)),
          child: Row(mainAxisSize: MainAxisSize.min, children: [
            Flexible(
              child: Text(name ?? 'All projects',
                  maxLines: 1, overflow: TextOverflow.ellipsis, style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w700, color: WmColors.textSecondary)),
            ),
            const SizedBox(width: 4),
            const Icon(Icons.arrow_drop_down, size: 20, color: WmColors.textSecondary),
          ]),
        ),
      );
}

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
  const _EntryCard({required this.entry, required this.kind, required this.controller, required this.canPick, this.onIssueFromStock});
  final ShoppingEntry entry;
  final _Kind kind;
  final ShoppingController controller;
  final bool canPick;
  final void Function(ShoppingEntry entry)? onIssueFromStock;

  Future<void> _claim(BuildContext context) async {
    final p = entry.portion;
    final qty = await showWmSheet<double>(
      context,
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
    return Container(
      key: Key('entry-${p.id}'),
      margin: const EdgeInsets.only(top: 8),
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: picked ? WmColors.green : WmColors.border),
      ),
      child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
        if (kind == _Kind.mine && canPick) ...[
          _TickBox(key: Key('pick-${p.id}'), picked: picked, enabled: !busy, onTap: () => controller.toggle(entry)),
          const SizedBox(width: 4),
        ],
        Expanded(
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Padding(
              padding: const EdgeInsets.only(top: 1),
              child: Text(title, style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 16)),
            ),
            const SizedBox(height: 2),
            Text('${l.placeLabel} · for ${l.requesterName}', style: const TextStyle(fontSize: 13, color: WmColors.textMuted)),
            const SizedBox(height: 8),
            // Still to buy first and bold; the others follow.
            Wrap(spacing: 16, runSpacing: 8, children: [
              _Number(label: stillToBuyLabel, value: qtyUnit(p.stillToBuy, l.unit), strong: true),
              _Number(label: neededLabel, value: qtyUnit(l.needed, l.unit)),
              _Number(label: boughtLabel, value: qtyUnit(l.bought, l.unit)),
              if (l.fromStock > 0) _Number(key: Key('from-stock-${p.id}'), label: fromStockLabel, value: qtyUnit(l.fromStock, l.unit)),
            ]),
            if (l.urgent || l.neededBy != null || p.changed || p.arranged || kind == _Kind.others) ...[
              const SizedBox(height: 8),
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
            ],
            // A hint, not a reservation (Q9): someone may issue it first.
            if (l.inWarehouse > 0) ...[
              const SizedBox(height: 6),
              Text('In warehouse: ${qtyUnit(l.inWarehouse, l.inWarehouseUnit)}',
                  key: Key('in-warehouse-${p.id}'), style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w700, color: WmColors.green)),
            ],
            if (l.notes.trim().isNotEmpty) ...[
              const SizedBox(height: 6),
              Text(l.notes, style: const TextStyle(fontSize: 13, color: WmColors.textSecondary)),
            ],
            if (kind != _Kind.others && onIssueFromStock != null && l.inWarehouse > 0 && l.catalogItemId != null && !busy) ...[
              const SizedBox(height: 10),
              _CardButton(issueFromStockLabel, () => onIssueFromStock!(entry), key: Key('issue-stock-${p.id}')),
            ],
            if (kind != _Kind.others) ...[
              const SizedBox(height: 10),
              if (busy)
                const LinearProgressIndicator()
              else if (kind == _Kind.unassigned)
                _CardButton(claimLabel, () => _claim(context), key: Key('claim-${p.id}'))
              else
                Row(children: [
                  Expanded(child: _CardButton(releaseLabel, () => controller.release(entry), key: Key('release-${p.id}'))),
                  const SizedBox(width: 8),
                  Expanded(
                    child: _CardButton(p.arranged ? notArrangedLabel : arrangedLabel, () => controller.setArranged(entry, !p.arranged),
                        key: Key('arranged-${p.id}')),
                  ),
                ]),
            ],
          ]),
        ),
      ]),
    );
  }
}

/// The mockup's tick box: 26 px, radius 8, a 2-px border; ticked = green with
/// a white check. A 44-px area to hit, announced as a checkbox.
class _TickBox extends StatelessWidget {
  const _TickBox({super.key, required this.picked, required this.enabled, required this.onTap});
  final bool picked;
  final bool enabled;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) => Semantics(
        container: true,
        checked: picked,
        enabled: enabled,
        label: 'Pick for Record purchase',
        onTap: enabled ? onTap : null,
        excludeSemantics: true,
        child: InkWell(
          customBorder: const CircleBorder(),
          onTap: enabled ? onTap : null,
          child: SizedBox(
            width: 44,
            height: 44,
            child: Center(
              child: AnimatedContainer(
                duration: const Duration(milliseconds: 150),
                width: 26,
                height: 26,
                decoration: BoxDecoration(
                  color: picked ? WmColors.green : Colors.white,
                  borderRadius: BorderRadius.circular(8),
                  border: Border.all(color: picked ? WmColors.green : (enabled ? WmColors.textDisabled : WmColors.textFaint), width: 2),
                ),
                child: picked ? const Icon(Icons.check, size: 18, color: Colors.white) : null,
              ),
            ),
          ),
        ),
      );
}

/// A 44-px outlined green button with its Tagalog line under it.
class _CardButton extends StatelessWidget {
  const _CardButton(this.label, this.onPressed, {super.key});
  final Bilingual label;
  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) => OutlinedButton(
        onPressed: onPressed,
        style: OutlinedButton.styleFrom(
          minimumSize: const Size(0, 44),
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 2),
          foregroundColor: WmColors.green,
          side: const BorderSide(color: WmColors.green),
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
        ),
        child: Column(mainAxisSize: MainAxisSize.min, children: [
          Text(label.english, textAlign: TextAlign.center, style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w800, height: 1.15)),
          Text(label.tagalog,
              textAlign: TextAlign.center, style: const TextStyle(fontSize: 11, fontWeight: FontWeight.w400, color: WmColors.textMuted, height: 1.15)),
        ]),
      );
}

class _Pill extends StatelessWidget {
  const _Pill({super.key, required this.text, required this.color, required this.tint});
  final String text;
  final Color color;
  final Color tint;

  @override
  Widget build(BuildContext context) => Container(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
        decoration: BoxDecoration(color: tint, borderRadius: BorderRadius.circular(999)),
        child: Text(text, style: TextStyle(fontSize: 12.5, fontWeight: FontWeight.w800, color: color)),
      );
}

class _Number extends StatelessWidget {
  const _Number({super.key, required this.label, required this.value, this.strong = false});
  final Bilingual label;
  final String value;
  final bool strong;

  @override
  Widget build(BuildContext context) => Column(crossAxisAlignment: CrossAxisAlignment.start, mainAxisSize: MainAxisSize.min, children: [
        Text(label.english, style: const TextStyle(fontSize: 11.5, color: WmColors.textMuted)),
        Text(label.tagalog, style: const TextStyle(fontSize: 10.5, color: WmColors.textMeta)),
        const SizedBox(height: 2),
        Text(value,
            style: TextStyle(fontFamily: 'IBM Plex Mono', fontWeight: strong ? FontWeight.w700 : FontWeight.w500, fontSize: strong ? 16 : 14.5)),
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
  Widget build(BuildContext context) => WmSheetFrame(
        title: claimLabel.english,
        subtitle: claimLabel.tagalog,
        footer: WmSheetButton(key: const Key('claim-confirm'), label: 'Claim', icon: Icons.check, onPressed: _done),
        children: [
          Text('${stillToBuyLabel.english}: ${qtyUnit(widget.still, widget.unit)}. Take all of it, or part.',
              style: const TextStyle(color: WmColors.textMuted)),
          const SizedBox(height: 12),
          TextField(
            key: const Key('claim-qty'),
            controller: _qty,
            keyboardType: const TextInputType.numberWithOptions(decimal: true),
            decoration: InputDecoration(labelText: 'How much will you buy?', suffixText: widget.unit, errorText: _error),
          ),
        ],
      );
}
