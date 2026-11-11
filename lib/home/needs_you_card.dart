import 'package:flutter/material.dart';

import '../requests/domain/request_status.dart' show calendarDay;
import '../ui/theme.dart';
import 'needs_you.dart';

/// Rows shown before "Show N more" (owner decision, 11 Nov 2026).
const needsYouShown = 5;

/// Home's "Needs you" (redesign spec §5): one row per thing to do, each with
/// its own button. Off Home while nothing is known; "all caught up" only
/// once every source was read.
class NeedsYouCard extends StatefulWidget {
  const NeedsYouCard({super.key, required this.needs, required this.onOpen});

  final NeedsYou needs;
  final void Function(NeedsRow row) onOpen;

  @override
  State<NeedsYouCard> createState() => _NeedsYouCardState();
}

class _NeedsYouCardState extends State<NeedsYouCard> {
  bool _all = false;

  void _open(NeedsRow row) {
    setState(() => _all = false);
    widget.onOpen(row);
  }

  @override
  Widget build(BuildContext context) {
    final n = widget.needs;
    if (n.hidden) return const SizedBox.shrink();
    final rows = n.rows;
    final more = rows.length > needsYouShown;
    final shown = _all || !more ? rows : rows.take(needsYouShown).toList();
    final items = <Widget>[
      if (n.caughtUp) const _CaughtUp(),
      for (final r in shown) _NeedsRowView(key: Key('needs-${r.id}'), row: r, onTap: () => _open(r)),
      if (more)
        _MoreRow(
          key: const Key('needs-more'),
          label: _all ? 'Show fewer' : 'Show ${rows.length - needsYouShown} more',
          open: _all,
          onTap: () => setState(() => _all = !_all),
        ),
    ];
    return Padding(
      padding: const EdgeInsets.only(top: 24),
      child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        Row(children: [
          const Text('NEEDS YOU', style: monoLabel),
          if (rows.isNotEmpty) ...[const SizedBox(width: 8), _Count(rows.length)],
        ]),
        const SizedBox(height: 9),
        Material(
          color: Colors.white,
          clipBehavior: Clip.antiAlias,
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20), side: const BorderSide(color: WmColors.border)),
          child: Column(children: [
            for (var i = 0; i < items.length; i++) ...[
              if (i > 0) const Divider(height: 1, thickness: 1, color: WmColors.hairline),
              items[i],
            ],
          ]),
        ),
      ]),
    );
  }
}

class _Count extends StatelessWidget {
  const _Count(this.n);
  final int n;

  @override
  Widget build(BuildContext context) => Container(
        key: const Key('needs-count'),
        constraints: const BoxConstraints(minWidth: 20, minHeight: 20),
        padding: const EdgeInsets.symmetric(horizontal: 6),
        alignment: Alignment.center,
        decoration: BoxDecoration(color: WmColors.danger, borderRadius: BorderRadius.circular(10)),
        child: Text('$n', style: const TextStyle(color: Colors.white, fontSize: 12, fontWeight: FontWeight.w800, height: 1)),
      );
}

class _NeedsRowView extends StatelessWidget {
  const _NeedsRowView({super.key, required this.row, required this.onTap});

  final NeedsRow row;
  final VoidCallback onTap;

  static IconData _icon(NeedsKind k) => switch (k) {
        NeedsKind.read => Icons.fiber_new_outlined,
        NeedsKind.check => Icons.fact_check_outlined,
        NeedsKind.finishDraft => Icons.edit_note,
        NeedsKind.notAccepted || NeedsKind.fixRequest || NeedsKind.toolUnresolved || NeedsKind.toolRecords => Icons.report_outlined,
      };

  @override
  Widget build(BuildContext context) {
    final fg = row.quiet ? WmColors.textSecondary : WmColors.danger;
    final tint = row.quiet ? WmColors.inert : WmColors.dangerTint;
    return InkWell(
      onTap: onTap,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(16, 14, 14, 14),
        child: Row(children: [
          Container(
            width: 38,
            height: 38,
            decoration: BoxDecoration(color: tint, shape: BoxShape.circle),
            child: Icon(_icon(row.kind), size: 20, color: fg),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text(row.title,
                  maxLines: 2, overflow: TextOverflow.ellipsis, style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 15, height: 1.25)),
              const SizedBox(height: 2),
              Text(row.line, style: TextStyle(fontSize: 13, fontWeight: FontWeight.w600, color: fg)),
            ]),
          ),
          const SizedBox(width: 12),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
            decoration: BoxDecoration(color: WmColors.green, borderRadius: BorderRadius.circular(999)),
            child: Text(row.action, style: const TextStyle(color: Colors.white, fontSize: 13.5, fontWeight: FontWeight.w800)),
          ),
        ]),
      ),
    );
  }
}

class _CaughtUp extends StatelessWidget {
  const _CaughtUp();

  @override
  Widget build(BuildContext context) => Padding(
        key: const Key('needs-caught-up'),
        padding: const EdgeInsets.all(16),
        child: Row(children: [
          Container(
            width: 38,
            height: 38,
            decoration: const BoxDecoration(color: WmColors.greenTint, shape: BoxShape.circle),
            child: const Icon(Icons.done_all, size: 20, color: WmColors.green),
          ),
          const SizedBox(width: 12),
          const Expanded(
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text('You are all caught up', style: TextStyle(fontWeight: FontWeight.w800, fontSize: 15)),
              Text('Nothing needs you right now.', style: TextStyle(fontSize: 13, color: WmColors.textMuted)),
            ]),
          ),
        ]),
      );
}

class _MoreRow extends StatelessWidget {
  const _MoreRow({super.key, required this.label, required this.open, required this.onTap});

  final String label;
  final bool open;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) => InkWell(
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
          child: Row(children: [
            Expanded(child: Text(label, style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w700, color: WmColors.green))),
            Icon(open ? Icons.expand_less : Icons.expand_more, color: WmColors.green),
          ]),
        ),
      );
}

/// The quiet line under "Needs you" (owner decision: kept on Home).
class NextDeliveryLine extends StatelessWidget {
  const NextDeliveryLine({super.key, required this.iso});

  /// "2026-10-14".
  final String iso;

  @override
  Widget build(BuildContext context) => Padding(
        key: const Key('next-delivery'),
        padding: const EdgeInsets.only(top: 10),
        child: Row(children: [
          const Icon(Icons.local_shipping_outlined, size: 18, color: WmColors.green),
          const SizedBox(width: 8),
          Expanded(
            child: Text('Next delivery ${calendarDay(iso)}',
                style: const TextStyle(fontSize: 13.5, fontWeight: FontWeight.w700, color: WmColors.green)),
          ),
        ]),
      );
}
