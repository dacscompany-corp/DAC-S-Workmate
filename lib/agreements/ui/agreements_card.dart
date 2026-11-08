import 'package:flutter/material.dart';

import '../../attendance/ui/formats.dart' show clockTime;
import '../../ui/theme.dart';
import 'agreements_controller.dart';
import 'agreements_copy.dart';

/// Home's My agreements card (Linked Labor). Shown only after this session's
/// read found at least one agreement; no signal, no agreement, or a refused
/// account shows nothing. No amount is shown on Home — only inside.
class AgreementsCard extends StatelessWidget {
  const AgreementsCard({super.key, required this.controller, required this.onOpen});

  final AgreementsController controller;
  final VoidCallback onOpen;

  @override
  Widget build(BuildContext context) {
    final c = controller;
    if (!c.showCard) return const SizedBox.shrink();
    final n = c.agreements.length;
    final at = c.fetchedAt;
    return Padding(
      padding: const EdgeInsets.only(top: 16),
      child: InkWell(
        key: const Key('agreements-card'),
        onTap: onOpen,
        borderRadius: BorderRadius.circular(18),
        child: Container(
          width: double.infinity,
          padding: const EdgeInsets.all(16),
          decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(18), border: Border.all(color: WmColors.border)),
          child: Row(children: [
            Expanded(
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Text(myAgreementsTitle.english, style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 16)),
                Text(myAgreementsTitle.tagalog, style: const TextStyle(fontSize: 11.5, color: WmColors.textMuted)),
                const SizedBox(height: 6),
                Row(children: [
                  const Icon(Icons.description_outlined, size: 18, color: WmColors.textSecondary),
                  const SizedBox(width: 8),
                  Text('$n agreement${n == 1 ? '' : 's'}', style: const TextStyle(color: WmColors.textSecondary, fontWeight: FontWeight.w600)),
                ]),
                if (at != null)
                  Padding(
                    padding: const EdgeInsets.only(top: 2),
                    child: Text('Updated ${clockTime(at)}', style: const TextStyle(fontSize: 12, color: WmColors.textMuted)),
                  ),
              ]),
            ),
            const Icon(Icons.chevron_right, color: WmColors.textMuted),
          ]),
        ),
      ),
    );
  }
}
