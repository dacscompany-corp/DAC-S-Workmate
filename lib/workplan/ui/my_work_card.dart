import 'package:flutter/material.dart';

import '../../ui/theme.dart';
import '../domain/wp_rules.dart';

/// Home's My Work card (spec §15: no phone push in 1c — the app shows what
/// is new when it opens). Nothing to say → nothing shown.
class MyWorkCard extends StatelessWidget {
  const MyWorkCard({super.key, required this.updates, required this.onOpen});

  final WpUpdates updates;
  final VoidCallback onOpen;

  @override
  Widget build(BuildContext context) {
    final u = updates;
    if (u.isEmpty) return const SizedBox.shrink();
    final lines = <(IconData, String, Color)>[
      if (u.toRead > 0) (Icons.fiber_new_outlined, '${u.toRead} task${u.toRead == 1 ? '' : 's'} to read', WmColors.danger),
      if (u.toCheck > 0) (Icons.fact_check_outlined, '${u.toCheck} to check', WmColors.danger),
      if (u.failed > 0) (Icons.report_outlined, '${u.failed} not accepted', WmColors.danger),
      if (u.pending > 0) (Icons.cloud_off, '${u.pending} waiting for signal', WmColors.brown),
    ];
    return Padding(
      padding: const EdgeInsets.only(top: 16),
      child: InkWell(
        key: const Key('my-work-card'),
        onTap: onOpen,
        borderRadius: BorderRadius.circular(18),
        child: Container(
          width: double.infinity,
          padding: const EdgeInsets.all(16),
          decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(18), border: Border.all(color: WmColors.border)),
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            const Row(children: [
              Expanded(child: Text('My Work', style: TextStyle(fontWeight: FontWeight.w800, fontSize: 16))),
              Icon(Icons.chevron_right, color: WmColors.textMuted),
            ]),
            const SizedBox(height: 6),
            for (final (icon, text, color) in lines)
              Padding(
                padding: const EdgeInsets.only(top: 4),
                child: Row(children: [
                  Icon(icon, size: 18, color: color),
                  const SizedBox(width: 8),
                  Expanded(child: Text(text, style: TextStyle(color: color, fontWeight: FontWeight.w600))),
                ]),
              ),
          ]),
        ),
      ),
    );
  }
}
