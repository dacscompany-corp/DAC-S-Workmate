import 'package:flutter/material.dart';

import '../../attendance/ui/formats.dart' show clockTime;
import '../../ui/theme.dart';
import 'tools_controller.dart';
import 'tools_copy.dart';

/// Home's My tools card (roadmap Part 2): the bottom bar keeps its five tabs.
/// Shown once the server let this worker into tools, or a saved copy exists;
/// tools switched off, or no worker account, shows nothing.
class ToolsCard extends StatelessWidget {
  const ToolsCard({super.key, required this.controller, required this.onOpen});

  final ToolsController controller;
  final VoidCallback onOpen;

  @override
  Widget build(BuildContext context) {
    final c = controller;
    if (!c.showCard) return const SizedBox.shrink();
    final n = c.mine.length;
    final lines = <(IconData, String, Color)>[
      (Icons.handyman_outlined, n == 0 ? 'No tools with you' : '$n tool${n == 1 ? '' : 's'} with you', WmColors.textSecondary),
      if (c.openProblems > 0)
        (Icons.report_outlined, '${c.openProblems} problem${c.openProblems == 1 ? '' : 's'} reported', WmColors.brown),
      if (c.leading) (Icons.groups_outlined, 'Team: ${c.team.length} tool${c.team.length == 1 ? '' : 's'}', WmColors.green),
      if (c.mineSaved && c.mineAt != null) (Icons.cloud_off, 'Saved copy from ${clockTime(c.mineAt!)}', WmColors.textMuted),
    ];
    return Padding(
      padding: const EdgeInsets.only(top: 16),
      child: InkWell(
        key: const Key('tools-card'),
        onTap: onOpen,
        borderRadius: BorderRadius.circular(18),
        child: Container(
          width: double.infinity,
          padding: const EdgeInsets.all(16),
          decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(18), border: Border.all(color: WmColors.border)),
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Row(children: [
              Expanded(
                child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  Text(myToolsTitle.english, style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 16)),
                  Text(myToolsTitle.tagalog, style: const TextStyle(fontSize: 11.5, color: WmColors.textMuted)),
                ]),
              ),
              const Icon(Icons.chevron_right, color: WmColors.textMuted),
            ]),
            const SizedBox(height: 4),
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
